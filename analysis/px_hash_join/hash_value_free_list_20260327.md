# Parallel Hash Join - HASH_SCAN_VALUE Free List 재사용

> 분석일: 2026-03-27
> 대상: 파티션 해시 조인에서 파티션 간 HASH_SCAN_VALUE 메모리 재사용
> 관련 소스: `src/query/query_hash_join.c`, `src/query/query_hash_scan.c`

---

## 1. 개요

파티션 해시 조인에서 각 파티션마다 HASH_SCAN_VALUE를 `db_private_alloc`/`db_private_free`로
반복 할당/해제한다. `HASHJOIN_MANAGER`에 worker 개수만큼 free list 배열을 두고,
worker index로 접근하여 동기화 없이 재사용한다.

---

## 2. 현재 메모리 흐름 (파티션당)

```
hjoin_execute_internal
  → hjoin_init_context      — mht_create_hls (malloc: header + buckets + fixed heap)
  → hjoin_build             — N번 qdata_alloc_hscan_value (db_private_alloc: value + tuple/pos)
  → hjoin_probe
  → hjoin_scan_clear        — mht_clear_hls (value free) + mht_destroy_hls (header + buckets + heap 파괴)
```

### 2.1 할당 경로

```
hjoin_build_key (query_hash_join.c:3051)
  ├── IN_MEM:  qdata_alloc_hscan_value (query_hash_scan.c:630)
  │            → db_private_alloc(sizeof(HASH_SCAN_VALUE))
  │            → db_private_alloc(tuple_size)  ← 가변 크기
  │            → memcpy(value->tuple, tpl, tuple_size)
  │
  └── HYBRID: qdata_alloc_hscan_value_OID (query_hash_scan.c:664)
              → db_private_alloc(sizeof(HASH_SCAN_VALUE))
              → db_private_alloc(sizeof(QFILE_TUPLE_SIMPLE_POS))  ← 고정 크기
```

### 2.2 해제 경로

```
hjoin_scan_clear (query_hash_join.c:2594)
  → mht_clear_hls (memory_hash.c:1292)
    → 콜백: qdata_free_hscan_entry (query_hash_scan.c:730)
      → qdata_free_hscan_key (key=NULL이므로 no-op)
      → qdata_free_hscan_value (query_hash_scan.c:708)
        → db_private_free(value->data)  ← tuple 또는 pos
        → db_private_free(value)        ← HASH_SCAN_VALUE 자체
```

### 2.3 핵심 관찰

- `mht_clear_hls` 콜백: `int (*rem_func)(const void *key, void *data, void *args)`
  - key = **NULL** (mht_clear_hls가 NULL 전달), data = HASH_SCAN_VALUE*, args = thread_p
- HASH_SCAN_KEY는 해시 테이블에 저장되지 않음 (임시 사용) → free list 대상 아님
- **free list 대상은 HASH_SCAN_VALUE만**
- `mht_clear_hls`는 HENTRY_HLS를 이미 prealloc 리스트로 재사용하지만,
  `mht_destroy_hls`에서 fixed heap 자체를 파괴

---

## 3. 관련 자료구조

### 3.1 HASH_SCAN_VALUE (query_hash_scan.h:82)

```c
typedef union hash_scan_value HASH_SCAN_VALUE;
union hash_scan_value
{
  void *data;                      /* for free() — free list에서 next 포인터로 재사용 가능 */
  QFILE_TUPLE_SIMPLE_POS *pos;     /* HYBRID: tuple position */
  QFILE_TUPLE tuple;               /* IN_MEM: tuple data */
};
```

union이므로 `data` 필드를 free list의 next 포인터로 재사용 가능.

### 3.2 MHT_HLS_TABLE (memory_hash.h:149)

```c
struct mht_hls_table
{
  HENTRY_HLS_PTR *table;           /* bucket 배열 */
  HENTRY_HLS_PTR prealloc_entries; /* mht_clear_hls에서 재사용하는 entry pool */
  unsigned int size;               /* bucket 수 */
  unsigned int nentries;           /* 현재 entry 수 */
  HL_HEAPID heap_id;               /* HENTRY_HLS용 fixed heap */
  ...
};
```

### 3.3 HASHJOIN_MANAGER (query_hash_join.h:332)

```c
typedef struct hashjoin_manager
{
  HASHJOIN_CONTEXT single_context;
  HASHJOIN_CONTEXT *contexts;      /* 파티션별 context 배열 */
  UINT32 context_cnt;
  int num_parallel_threads;
  parallel_query::worker_manager *px_worker_manager;
  ...
} HASHJOIN_MANAGER;
```

---

## 4. 변경 설계

### 4.1 자료구조 추가

```c
/* query_hash_join.h — HASHJOIN_MANAGER에 추가 */
HASH_SCAN_VALUE **value_free_lists;  /* [num_parallel_threads] — worker별 free list */
```

- 순차 실행: worker 1개 → `value_free_lists[0]`만 사용
- 병렬 실행: worker N개 → `value_free_lists[worker_idx]` 각자 접근, 충돌 없음

### 4.2 콜백 컨텍스트

```c
/* query_hash_join.c — mht_clear_hls에 args로 전달 */
typedef struct hjoin_recycle_args HJOIN_RECYCLE_ARGS;
struct hjoin_recycle_args
{
  THREAD_ENTRY *thread_p;
  HASH_SCAN_VALUE **free_list_head;  /* &manager->value_free_lists[worker_idx] */
};
```

### 4.3 새 함수 (모두 query_hash_join.c)

**Pop — 할당 대체:**
```c
static HASH_SCAN_VALUE *
hjoin_alloc_hscan_value (THREAD_ENTRY *thread_p, HASH_SCAN_VALUE **free_list_head, QFILE_TUPLE tpl)
{
  HASH_SCAN_VALUE *value = *free_list_head;
  if (value != NULL)
    {
      *free_list_head = (HASH_SCAN_VALUE *) value->data;
      /* tuple buffer 재사용 또는 realloc */
    }
  else
    {
      value = qdata_alloc_hscan_value (thread_p, tpl);
    }
  return value;
}
```

**Push — 해제 대체 (mht_clear_hls 콜백):**
```c
static int
hjoin_recycle_hscan_entry (const void *key, void *data, void *args)
{
  HJOIN_RECYCLE_ARGS *ctx = (HJOIN_RECYCLE_ARGS *) args;
  HASH_SCAN_VALUE *value = (HASH_SCAN_VALUE *) data;

  /* HASH_SCAN_VALUE.data를 next 포인터로 재사용 */
  value->data = *ctx->free_list_head;
  *ctx->free_list_head = value;

  return NO_ERROR;
}
```

**일괄 해제 — 전체 종료 시:**
```c
static void
hjoin_free_value_free_lists (THREAD_ENTRY *thread_p, HASHJOIN_MANAGER *manager)
{
  for (int i = 0; i < manager->num_parallel_threads; i++)
    {
      HASH_SCAN_VALUE *cur = manager->value_free_lists[i];
      while (cur != NULL)
        {
          HASH_SCAN_VALUE *next = (HASH_SCAN_VALUE *) cur->data;
          qdata_free_hscan_value (thread_p, cur);
          cur = next;
        }
      manager->value_free_lists[i] = NULL;
    }
}
```

### 4.4 기존 함수 수정

| 함수 | 변경 내용 |
|------|-----------|
| `hjoin_build_key` | `qdata_alloc_hscan_value` → `hjoin_alloc_hscan_value` (free list pop) |
| `hjoin_scan_clear` | `qdata_free_hscan_entry` 콜백 → `hjoin_recycle_hscan_entry` (free list push) |
| `hjoin_init_manager` | `value_free_lists = calloc(num_parallel_threads)` |
| `hjoin_clear_manager` | `hjoin_free_value_free_lists` → `free(value_free_lists)` |

### 4.5 수명 관리

```
hjoin_init_manager
  └── value_free_lists = calloc(N)    ← N = num_parallel_threads

hjoin_execute_partitions (순차)      또는   join_task::execute (병렬)
  for each partition:                       partition = get_next_context()
    hjoin_build_key                           hjoin_build_key
      └── pop from free_lists[0]                └── pop from free_lists[m_index]
    hjoin_scan_clear                          hjoin_scan_clear
      └── push to free_lists[0]                 └── push to free_lists[m_index]

hjoin_clear_manager
  └── hjoin_free_value_free_lists     ← 일괄 해제
  └── free(value_free_lists)
```

### 4.6 IN_MEM vs HYBRID 처리

- **HYBRID**: HASH_SCAN_VALUE + QFILE_TUPLE_SIMPLE_POS 모두 고정 크기 → 완벽 재사용
- **IN_MEM**: tuple data 가변 크기
  - free list에서 pop 시 기존 buffer 크기 확인
  - 충분하면 memcpy만, 부족하면 realloc

---

## 5. 수정 파일

| 파일 | 변경 |
|------|------|
| `src/query/query_hash_join.h` | `HASHJOIN_MANAGER`에 `value_free_lists` 추가 |
| `src/query/query_hash_join.c` | 새 타입/함수 추가, `hjoin_build_key`/`hjoin_scan_clear` 수정, 초기화/정리 |
| `src/query/parallel/px_hash_join/px_hash_join_task_manager.cpp` | `join_task::execute`에서 `m_index`로 free list 접근 |

---

## 6. 관련 소스 코드

| 위치 | 내용 |
|------|------|
| `src/query/query_hash_join.c:3051` | `hjoin_build_key()` — HASH_SCAN_VALUE 할당 |
| `src/query/query_hash_join.c:2594` | `hjoin_scan_clear()` — 해시 테이블 정리 |
| `src/query/query_hash_join.c:328` | `hjoin_execute_partitions()` — 순차 파티션 루프 |
| `src/query/query_hash_join.c:610` | `hjoin_execute_internal()` — build → probe → clear |
| `src/query/query_hash_scan.c:630` | `qdata_alloc_hscan_value()` — IN_MEM 할당 |
| `src/query/query_hash_scan.c:664` | `qdata_alloc_hscan_value_OID()` — HYBRID 할당 |
| `src/query/query_hash_scan.c:708` | `qdata_free_hscan_value()` — 해제 |
| `src/query/query_hash_scan.c:730` | `qdata_free_hscan_entry()` — mht_clear_hls 콜백 |
| `src/base/memory_hash.c:1292` | `mht_clear_hls()` — entry 순회 + 콜백 호출 |
| `src/base/memory_hash.c:1207` | `mht_destroy_hls()` — 해시 테이블 파괴 |
| `src/query/query_hash_scan.h:82` | `HASH_SCAN_VALUE` union 정의 |
| `src/query/query_hash_join.h:332` | `HASHJOIN_MANAGER` 구조체 정의 |
