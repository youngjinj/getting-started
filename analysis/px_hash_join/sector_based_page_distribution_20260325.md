# Parallel Hash Join - Sector-Based Page Distribution

> 분석일: 2026-03-25 (membuf 처리 추가: 2026-03-26)
> 대상: `src/query/parallel/px_hash_join/` split phase의 페이지 분배 방식
> 패치: `20250325_sector_based.patch`

---

## 1. 개요

기존 mutex 기반 linked-list 순회를 제거하고, 파일 매니저의 **섹터/비트맵 구조**를 활용하여
lock-free로 페이지를 분배한다. membuf 페이지는 별도로 한 워커가 통째로 처리한다.

```
                       +-----------------------+
                       |  collect_list_data_    |
                       |  pages()              |
                       |                       |
                       |  1. membuf 정보 세팅    |
                       |  2. disk sector 수집    |
                       +-----------+-----------+
                                   |
                     +-------------+-------------+
                     |                           |
              membuf 영역                  disk sector 영역
          (first list_id only)         (all dependent list_ids)
                     |                           |
              +------+------+          +---------+---------+
              | CAS claim   |          | atomic fetch_add  |
              | (1 winner)  |          | (per sector)      |
              +------+------+          +---------+---------+
                     |                           |
              +------+------+          +---------+---------+
              |  Worker 0   |          | Worker 0,1,2,...N |
              |  pages 0~M  |          | sector 단위 분배   |
              |  sequential |          | bitmap bit 순회    |
              +-------------+          +-------------------+
                     |                           |
                     +------ membuf 소진 후 ------+
                     |   sector 분배에 합류       |
                     +---------------------------+
```

---

## 2. 기존 방식 vs 새 방식

### 2.1 기존 방식 (mutex + VPID linked-list)

```
Worker 0 ──┐
Worker 1 ──┼── lock(scan_mutex) ── qmgr_get_old_page(&next_vpid) ── QFILE_GET_NEXT_VPID ── unlock
Worker 2 ──┘
               ^^^^^^^^^^^^^^^^
               매 페이지마다 mutex 경합
```

- 모든 worker가 하나의 mutex를 통해 순차적으로 다음 VPID를 획득
- page header를 읽어야 다음 VPID를 알 수 있음 (linked-list 의존)
- worker 수가 늘어날수록 mutex 경합 심화

### 2.2 새 방식 (sector bitmap + atomic)

```
[수집 단계 - 메인 스레드]

  file header
  ┌──────────────────────────────┐
  │  partial sector table        │
  │  ┌────────┬────────────────┐ │     FILE_DATA_PAGE_MAP
  │  │ VSID 0 │ bitmap 0       │ │     ┌──────────────────────┐
  │  │ VSID 1 │ bitmap 1       │─┼────>│ sectors[0] {vsid, bm}│
  │  │ VSID 2 │ bitmap 2       │ │     │ sectors[1] {vsid, bm}│
  │  │  ...   │  ...           │ │     │ sectors[2] {vsid, bm}│
  │  └────────┴────────────────┘ │     │  ...                  │
  │  vpid_next ──> [next page]   │     │ n_sectors = N         │
  └──────────────────────────────┘     └──────────────────────┘

[분배 단계 - lock-free]

  next_sector_idx: atomic<int> = 0

  Worker 0: fetch_add → idx=0 → sectors[0].bitmap → bit순회 → 페이지 처리
  Worker 1: fetch_add → idx=1 → sectors[1].bitmap → bit순회 → 페이지 처리
  Worker 2: fetch_add → idx=2 → sectors[2].bitmap → bit순회 → 페이지 처리
  Worker 0: (sector 0 소진) fetch_add → idx=3 → sectors[3] ...
```

### 2.3 비교

| | 기존 (mutex) | 새 방식 (sector) |
|---|---|---|
| 동기화 | mutex (매 페이지) | atomic fetch_add (매 섹터, ~64페이지마다) |
| I/O 패턴 | 페이지 단위 분산 | 섹터 단위 연속 (locality 향상) |
| chain 의존 | page header 읽어야 다음 VPID | 불필요 (bitmap에서 직접 계산) |
| membuf 처리 | 자연스러운 VPID chain | 별도 로직 필요 (CAS claim) |
| producer 병목 | 없음 | 없음 (수집은 사전 완료) |

---

## 3. QFILE_LIST_ID 페이지 구조

QFILE_LIST_ID의 페이지는 **membuf 영역**과 **disk 영역** 두 곳에 존재할 수 있다.

```
QFILE_LIST_ID
  │
  ├── tfile_vfid ──> QMGR_TEMP_FILE
  │                   ├── membuf[0..membuf_last]    ← 메모리 페이지 (volid = NULL_VOLID)
  │                   ├── membuf_last = M            ← 마지막 사용 인덱스
  │                   ├── membuf (PAGE_PTR *)         ← 페이지 포인터 배열
  │                   └── temp_vfid                  ← 디스크 임시파일 VFID
  │
  ├── first_vpid ──> {NULL_VOLID, 0}  (membuf에서 시작하는 경우)
  │                   ↓ VPID chain
  │                   {NULL_VOLID, 1} → ... → {NULL_VOLID, M}
  │                   ↓ membuf 초과 시
  │                   {vol_id, page_id} → ... → {vol_id, page_id}  (디스크)
  │
  └── dependent_list_id ──> list_1 (tfile_vfid = B, membuf 없음)
                              └── dependent_list_id ──> list_2 (tfile_vfid = C, membuf 없음)
```

**핵심 규칙:**
- **membuf는 첫 번째 list_id에만 존재** (dependent_list_id에는 없음)
- membuf 페이지: `volid == NULL_VOLID`, `pageid = 0..membuf_last`
- disk 페이지: `volid != NULL_VOLID`, 파일 매니저 섹터 비트맵에 존재
- `qfile_append_list`로 연결된 list는 **각각 다른 temp file**에 속함

---

## 4. 전체 동작 흐름

### 4.1 수집 단계: `collect_list_data_pages()`

```
collect_list_data_pages(thread_p, list_id, shared_info)
  │
  ├── [1] membuf 정보 세팅 (첫 번째 list_id만)
  │     if (tfile_vfid->membuf != NULL && membuf_last >= 0)
  │       shared_info->membuf_tfile = tfile_vfid
  │       shared_info->membuf_last  = tfile_vfid->membuf_last
  │     membuf_claimed = false
  │
  ├── [2] dependent_list_id chain 순회 → disk VFID 수집
  │     list_id (VFID=A) → dependent (VFID=B) → dependent (VFID=C) → ...
  │     VFID_ISNULL 건너뜀 (membuf만 있는 list)
  │
  └── [3] file_collect_data_pages_batch(vfids[], tfiles[], n_vfids)
        → file header의 partial sector table 전체 순회
        → FTAB/header 페이지 비트 제거
        → FILE_DATA_PAGE_MAP에 sector별 bitmap 저장
        → 각 sector에 소속 tfile 포인터 기록
```

### 4.2 분배 단계: `split_task::get_next_page()`

```cpp
PAGE_PTR get_next_page (cubthread::entry &thread_ref)
{
    /* ── Phase 1: membuf ── */
    if (m_membuf_owner)                              // 이미 claim한 워커
      {
        if (m_membuf_page_idx <= membuf_last)
          return page(NULL_VOLID, m_membuf_page_idx++);
        m_membuf_owner = false;                      // membuf 소진 → sector로
      }

    if (first_call && membuf_last >= 0)              // 최초 1회 CAS 시도
      {
        if (CAS(membuf_claimed, false → true))
          {
            m_membuf_owner = true;
            m_membuf_page_idx = 0;
            return get_next_page();                  // Phase 1로 재진입
          }
      }

    /* ── Phase 2: sector-based disk pages ── */
    while (true)
      {
        while (m_cur_bitmap != 0)                    // 현재 섹터 bit 순회
          {
            bit_pos = ctzll(m_cur_bitmap);           // 최하위 set bit
            m_cur_bitmap &= m_cur_bitmap - 1;        // clear
            vpid = {vsid.volid, SECTOR_FIRST_PAGEID(vsid.sectid) + bit_pos};
            return qmgr_get_old_page(&vpid, tfile);
          }

        idx = fetch_add(next_sector_idx, 1);         // 다음 섹터 원자적 획득
        if (idx >= n_sectors) return nullptr;         // 모든 섹터 분배 완료

        load sector[idx] → m_cur_vsid, m_cur_bitmap;
      }
}
```

**워커별 동작 시나리오:**

```
                time ──────────────────────────────────────────>

Worker 0:  [CAS win] membuf p0,p1,...,pM  │  sector 3  │  sector 7  │ done
Worker 1:  [CAS fail]  sector 0  │  sector 4  │  sector 8  │ done
Worker 2:  [CAS fail]  sector 1  │  sector 5  │  sector 9  │ done
Worker 3:  [CAS fail]  sector 2  │  sector 6  │ done
```

- Worker 0이 membuf를 claim하고 page 0~M을 모두 처리한 뒤 sector 분배에 합류
- Worker 1,2,3은 바로 sector 분배로 진행
- sector 분배는 work-stealing 형태: 빨리 끝난 워커가 더 많은 sector를 가져감

---

## 5. 변경 파일 상세

| 파일 | 변경 내용 |
|---|---|
| `file_manager.h` | `FILE_DATA_PAGE_SECTOR`, `FILE_DATA_PAGE_MAP` 구조체 선언. `file_collect_data_pages()`, `file_collect_data_pages_batch()`, `file_free_data_page_map()` 함수 선언 |
| `file_manager.c` | sector 수집 함수 구현. partial sector extdata chain 전체 순회, FTAB/header 비트 제거. batch 버전은 여러 VFID를 한번에 처리하고 각 sector에 tfile 포인터 기록 |
| `query_hash_join.h` | `HASHJOIN_SHARED_SPLIT_INFO` 변경: `scan_mutex`/`scan_position`/`next_vpid` 제거. `page_map`, `next_sector_idx`, `membuf_tfile`, `membuf_last`, `membuf_claimed` 추가 |
| `query_hash_join.c` | `hjoin_init_shared_split_info()`에서 `next_sector_idx` 초기화. `hjoin_clear_shared_split_info()`에서 `file_free_data_page_map()` 호출 |
| `px_hash_join.cpp` | `collect_list_data_pages()` 신규. outer/inner 각각 호출. membuf 정보 세팅 + dependent_list_id chain 순회 + batch sector 수집 |
| `px_hash_join_task_manager.hpp` | `split_task`에 membuf 상태(`m_membuf_owner`, `m_membuf_page_idx`)와 sector 상태(`m_cur_sector_idx`, `m_cur_bitmap`, `m_cur_vsid`) 추가 |
| `px_hash_join_task_manager.cpp` | `get_next_page()` 전면 교체: Phase 1(membuf CAS claim + 순회) → Phase 2(sector bitmap lock-free 순회) |

---

## 6. 핵심 구조체

### 6.0 QFILE_LIST_ID → 디스크 페이지 전체 구조

```
QFILE_LIST_ID
  ├── tfile_vfid ──→ QMGR_TEMP_FILE
  │                   ├── membuf[0..M]           ← 메모리 페이지 (volid = NULL_VOLID)
  │                   └── temp_vfid (VFID)       ← 디스크 임시파일 식별자
  │                         │
  │                         ▼
  │                   ┌─────────────────────────────────────┐
  │                   │  디스크 페이지 0 (File Header Page)   │
  │                   │                                     │
  │                   │  FILE_HEADER                        │
  │                   │  ├── self (VFID)                    │
  │                   │  ├── n_sector_total                 │
  │                   │  ├── n_sector_partial               │
  │                   │  ├── n_page_free                    │
  │                   │  ├── offset_to_partial_ftab ────┐   │
  │                   │  └── ...                        │   │
  │                   │                                 ▼   │
  │                   │  FILE_EXTENSIBLE_DATA (partial ftab) │
  │                   │  ├── n_items = K                    │
  │                   │  ├── size_of_item = sizeof(FILE_PARTIAL_SECTOR) │
  │                   │  ├── vpid_next ──→ (overflow page)  │
  │                   │  │                                  │
  │                   │  ├── [0] FILE_PARTIAL_SECTOR        │
  │                   │  │       { vsid={vol,sect}, bitmap } │
  │                   │  ├── [1] FILE_PARTIAL_SECTOR        │
  │                   │  │       { vsid={vol,sect}, bitmap } │
  │                   │  └── [K] ...                        │
  │                   └─────────────────────────────────────┘
  │                         │ vpid_next (항목이 많으면)
  │                         ▼
  │                   ┌─────────────────────────────────────┐
  │                   │  디스크 페이지 X (extdata overflow)   │
  │                   │                                     │
  │                   │  FILE_EXTENSIBLE_DATA                │
  │                   │  ├── [K+1] FILE_PARTIAL_SECTOR      │
  │                   │  ├── [K+2] FILE_PARTIAL_SECTOR      │
  │                   │  └── vpid_next = NULL (끝)          │
  │                   └─────────────────────────────────────┘
  │
  └── dependent_list_id ──→ (다른 QFILE_LIST_ID, 다른 temp_vfid)
```

- `VFID` 하나 = `FILE_HEADER` 하나 (temp file의 첫 번째 디스크 페이지)
- `FILE_HEADER` 안에 `FILE_EXTENSIBLE_DATA`(partial sector table)의 시작점이 있음
- `FILE_EXTENSIBLE_DATA`는 `FILE_PARTIAL_SECTOR` 배열의 페이지 단위 컨테이너
  — 한 페이지에 안 들어가면 `vpid_next`로 체이닝
- temp file은 full sector table을 사용하지 않으므로, 모든 섹터가 partial table에 존재

### 6.0.1 FILE_EXTENSIBLE_DATA 순회 방식

`file_manager.c` 내부에서 extdata chain을 순회하는 두 가지 방식:

**1) 콜백 기반 — `file_extdata_apply_funcs()` (`file_manager.c:1903`)**

```c
/* file_table_collect_all_vsids() 내부 — file_manager.c:3970 */
file_extdata_apply_funcs (thread_p, extdata_ftab,
    NULL, NULL,                    /* extdata 콜백 없음 */
    file_table_collect_vsid,       /* item 콜백: 각 item에 적용 */
    collector_out,                 /* 콜백 인자 */
    false, NULL, NULL);
```

vpid_next chain 전체를 자동 순회하며 각 item에 콜백을 적용.
`file_table_collect_all_vsids`, `file_table_collect_ftab_pages` 등이 이 방식 사용.

**2) 직접 순회 — for 루프 + vpid_next**

```c
/* file_collect_data_pages() 내부 — file_manager.c:11978-12021 */
while (true)
  {
    for (ps = (FILE_PARTIAL_SECTOR *) file_extdata_start (extdata_iter);
         ps < (FILE_PARTIAL_SECTOR *) file_extdata_end (extdata_iter); ps++)
      {
        /* ps->vsid, ps->page_bitmap 사용 */
      }

    vpid_next = extdata_iter->vpid_next;
    if (VPID_ISNULL (&vpid_next))
      break;

    page_iter = pgbuf_fix (thread_p, &vpid_next, ...);
    extdata_iter = (FILE_EXTENSIBLE_DATA *) page_iter;
  }
```

두 방식 모두 `file_manager.c` 내부 함수(`static`/`STATIC_INLINE`)이므로
외부에서 직접 사용할 수 없다. 외부에서는 `file_collect_data_pages()`를 통해
수집된 결과만 받아 사용한다.

### 6.1 FILE_DATA_PAGE_SECTOR / FILE_DATA_PAGE_MAP

```c
/* file_manager.h */
struct file_data_page_sector
{
  VSID vsid;            /* 섹터 ID (volid + sectid) */
  UINT64 page_bitmap;   /* bit N = 1 → 페이지 존재 (FTAB 제외) */
  void *tfile;          /* 소속 QMGR_TEMP_FILE 포인터 (opaque) */
};

struct file_data_page_map
{
  FILE_DATA_PAGE_SECTOR *sectors;
  int n_sectors;
};
```

**비트맵 → VPID 변환:**

```
섹터 VSID = {volid=10, sectid=5}
bitmap = 0b...0000_0000_0101_0011  (bit 0,1,4,6 set)

SECTOR_FIRST_PAGEID(5) = 5 * 64 = 320

  bit 0 → VPID {volid=10, pageid=320}
  bit 1 → VPID {volid=10, pageid=321}
  bit 4 → VPID {volid=10, pageid=324}
  bit 6 → VPID {volid=10, pageid=326}
```

### 6.2 HASHJOIN_SHARED_SPLIT_INFO

```cpp
/* query_hash_join.h */
struct hashjoin_shared_split_info
{
  std::mutex *part_mutexes;              /* 파티션별 mutex (overflow 시 사용) */

  /* sector-based disk page distribution */
  FILE_DATA_PAGE_MAP page_map;           /* 데이터 페이지 섹터 배열 (read-only) */
  std::atomic<int> next_sector_idx;      /* 다음 분배할 섹터 인덱스 */

  /* membuf page distribution (first list_id only) */
  struct qmgr_temp_file *membuf_tfile;   /* membuf 소유 tfile */
  int membuf_last;                       /* 마지막 membuf 페이지 인덱스 (-1 = 없음) */
  std::atomic<bool> membuf_claimed;      /* CAS: 한 워커만 membuf 획득 */
};
```

### 6.3 split_task 상태

```cpp
/* px_hash_join_task_manager.hpp */
class split_task
{
  /* membuf 상태 (Phase 1) */
  bool m_membuf_owner;       /* true = 이 워커가 membuf를 claim함 */
  int  m_membuf_page_idx;    /* 현재 순회 중인 membuf page index */

  /* sector 상태 (Phase 2) */
  int   m_cur_sector_idx;    /* 현재 섹터 인덱스 (-1 = 미시작) */
  UINT64 m_cur_bitmap;       /* 현재 섹터 내 남은 페이지 비트 */
  VSID  m_cur_vsid;          /* 현재 섹터 VSID */
};
```

---

## 7. 주의사항

### 7.1 FILE_QUERY_AREA의 membuf_last 함정

`qmgr_create_result_file()`로 생성된 result file은:

```c
tfile_vfid->membuf_last = PRM_ID_TEMP_MEM_BUFFER_PAGES - 1;  // >= 0
tfile_vfid->membuf      = NULL;                                // NULL!
tfile_vfid->membuf_npages = 0;
```

**`membuf_last >= 0`이지만 `membuf == NULL`**이다. 반드시 `membuf != NULL` 체크를 함께 해야 한다.

```cpp
/* collect_list_data_pages() 에서 올바른 검사 */
if (list_id->tfile_vfid != nullptr
    && list_id->tfile_vfid->membuf != NULL        // ← 이 체크 필수!
    && list_id->tfile_vfid->membuf_last >= 0)
```

이 체크가 누락되면 `qmgr_get_old_page()`에서 `tfile->membuf[pageid]` 접근 시
**NULL 역참조로 SEGFAULT** 발생:

```
qmgr_get_old_page() at query_manager.c:2541
  page_p = tfile_vfid_p->membuf[vpid_p->pageid];  // membuf == NULL → CRASH
```

### 7.2 dependent_list_id의 membuf 부재

`qfile_append_list()`로 연결된 dependent list들은 **membuf가 없다**.
append 시 원본 list의 tfile이 그대로 dependent에 연결되므로, dependent의 페이지는
항상 디스크에 존재한다.

```
base_list_id (tfile A: membuf 있음, disk 있음)
  └── dependent_list_id (tfile B: membuf 없음, disk만)
        └── dependent_list_id (tfile C: membuf 없음, disk만)
```

→ **membuf 처리는 첫 번째 list_id에 대해서만** 수행하면 된다.

### 7.3 temp file의 full sector 처리

temp file은 full sector table을 유지하지 않는다. **모든 섹터(full 포함)가
partial sector table에** bitmap과 함께 존재한다.

이는 `file_temp_alloc()` (`file_manager.c:8660-8671`)의 설계 주석에 명시되어 있다:

```c
/* file_temp_alloc() — file_manager.c:8660 */
/* how it works
 * temporary files, compared to permanent files, have a simplified design.
 * they do not keep two different tables (partial and full).
 * they only keep the partial table, and when sectors become full,
 * they remain in the partial table.
 * the second difference is that temporary files never deallocate pages.
 * since they are temporary, and soon to be freed (or cached for reuse),
 * there is no point in deallocating pages.
 * the simplified design was chosen because temporary files are never logged.
 * and it is hard to undo changes without logging when errors happen
 * (e.g. interrupted transaction).
 */
```

반면 permanent file (`file_perm_alloc`)은 섹터가 꽉 차면 partial table에서
제거하고 full table로 이동한다 (`file_manager.c:5315-5339`):

```c
/* file_perm_alloc() — file_manager.c:5315 */
if (is_full)
  {
    /* move to full table. */
    vsid_full = partsect->vsid;
    /* remove from partial table first */
    file_extdata_remove_at (extdata_part_ftab, 0, 1);
    /* add to full table */
    error_code = file_table_add_full_sector (thread_p, page_fhead, &vsid_full);
  }
```

**결론:** QFILE_LIST_ID의 temp file은 항상 `FILE_IS_TEMPORARY`이므로,
partial sector table만 순회하면 모든 섹터(full 포함)를 얻을 수 있다.

또한 `file_table_collect_all_vsids()` (`file_manager.c:3979`)도 이 사실을 반영한다:

```c
/* file_table_collect_all_vsids() — file_manager.c:3979 */
if (!FILE_IS_TEMPORARY (fhead))
  {
    /* Collect from full table. — temp file은 이 경로를 안 탐 */
  }
```

→ `vsid_collector` (VSID만 수집)를 사용하면 bitmap 정보가 없어 페이지 단위 순회가 불가능하다.
반드시 **partial sector table의 bitmap을 그대로 사용**해야 한다.

### 7.4 extdata chain이 여러 페이지에 걸치는 경우

partial sector table은 `FILE_EXTENSIBLE_DATA`로 관리되며, 섹터가 많으면
여러 페이지에 걸쳐 `vpid_next`로 연결된다.

```
page 0 (file header)           page X (extdata overflow)
┌──────────────────────┐      ┌──────────────────────┐
│ FILE_EXTENSIBLE_DATA │      │ FILE_EXTENSIBLE_DATA │
│   items[0..K]        │      │   items[0..J]        │
│   vpid_next ─────────┼─────>│   vpid_next = NULL   │
└──────────────────────┘      └──────────────────────┘
```

→ **첫 페이지만 순회하면 나머지 섹터가 누락**된다.
`vpid_next`를 따라 chain 전체를 순회해야 한다.

### 7.5 FTAB/header 페이지 비트 제거

file header 페이지와 extdata overflow 페이지는 데이터 페이지가 아니지만
섹터 bitmap에 bit가 set되어 있다. 이를 제거하지 않으면 해당 페이지를
데이터로 읽어서 `QFILE_GET_TUPLE_COUNT`에서 의미 없는 값을 얻는다.

```c
/* file_collect_data_pages_batch() 에서 제거 */
/* file header page bit 제거 */
if (same_sector(ps->vsid, fhead_vsid))
  bitmap &= ~((UINT64) 1 << fhead_bit_offset);

/* extdata (ftab) page bit 제거 */
if (same_sector(ps->vsid, extdata_vpid))
  bitmap &= ~((UINT64) 1 << ext_offset);
```

단, `QFILE_GET_TUPLE_COUNT == 0`인 페이지는 split 루프에서 자연스럽게 skip되므로,
batch 버전에서는 FTAB 비트를 완벽하게 제거하지 않아도 동작에는 문제가 없다.
(정확한 page count 통계가 필요한 경우에만 영향)

### 7.6 qmgr_free_old_page의 tfile 불일치

`execute()`에서 페이지 해제 시 `list_id->tfile_vfid` (첫 번째 list의 tfile)를 사용한다.
그러나 sector에서 가져온 페이지는 dependent list의 tfile에 속할 수 있다.

```cpp
/* execute() 내부 */
qmgr_free_old_page_and_init (&thread_ref, page, list_id->tfile_vfid);
//                                                ^^^^^^^^^^^^^^^^^^
// 이 tfile이 page의 실제 소속 tfile과 다를 수 있음
```

**동작에 문제는 없다.** `qmgr_free_old_page()`는 `qmgr_get_page_type()`으로
페이지가 membuf인지 disk인지 판별하는데:
- disk 페이지: `pgbuf_unfix()` 호출 (tfile 무관, VPID로 동작)
- membuf 페이지: no-op (free할 것이 없음)

따라서 tfile이 달라도 정상 동작하지만, 코드 의도가 불명확하므로 주의가 필요하다.

---

## 8. build_partitions 전체 흐름

```
build_partitions(thread_ref, manager, split_info)
  │
  ├── hjoin_init_shared_split_info()        // part_mutexes 할당, next_sector_idx=0
  │
  ├── ===== outer split =====
  │   ├── collect_list_data_pages(outer)     // membuf 세팅 + sector 수집
  │   ├── for i in 0..task_cnt:
  │   │     new split_task → push_task       // 워커 생성 및 큐잉
  │   ├── task_manager.join()                // 모든 워커 완료 대기
  │   └── error check
  │
  ├── file_free_data_page_map()              // outer page_map 해제
  │
  ├── ===== inner split =====
  │   ├── collect_list_data_pages(inner)     // membuf 세팅 + sector 수집
  │   ├── for i in 0..task_cnt:
  │   │     new split_task → push_task
  │   ├── task_manager.join()
  │   └── error check
  │
  └── hjoin_clear_shared_split_info()        // part_mutexes 해제 + page_map 해제
```

---

## 9. 시행착오 기록

### 9.1 partial sector table 첫 extent만 순회 (버그)

**현상**: 섹터가 많은 파일에서 결과 누락

**원인**: `file_extdata_start`/`file_extdata_end`는 현재 페이지의 항목만 반환.
partial sector table이 여러 페이지에 걸쳐 있을 때(`vpid_next` 링크),
첫 페이지 이후의 섹터들을 수집하지 못함.

**수정**: extdata chain 전체를 `vpid_next`로 따라가며 모든 partial sector를 배열에 수집.

### 9.2 temp file에서 full sector 누락 (버그)

**현상**: `file_table_collect_all_vsids`가 temp file에서 일부 섹터 누락

**원인**: temp file은 full sector table을 유지하지 않음.
`file_table_collect_all_vsids()`의 `if (!FILE_IS_TEMPORARY(fhead))` 분기 때문에
full sector가 수집되지 않음. temp file에서는 모든 섹터(full 포함)가
partial sector table에 존재.

**수정**: `vsid_collector` 사용 중단. partial sector table에서 VSID + bitmap을 직접 수집.

### 9.3 dependent_list_id의 temp file 누락 (버그)

**현상**: page_cnt 대비 bitmap_pages가 약 91% 누락.
```
outer: page_cnt=147392, bitmap_pages=13134, sectors=206
```

**원인**: `qfile_append_list`로 연결된 list의 페이지는 다른 temp file에 속함.
base list의 VFID만으로 수집하면 dependent list들의 페이지가 전부 누락.

**수정**: `dependent_list_id` chain을 따라가며 모든 temp file의 VFID를 수집하고,
`file_collect_data_pages_batch()`로 한번에 처리. 각 sector에 소속 tfile 포인터 기록.

### 9.4 FILE_QUERY_AREA에서 membuf NULL 역참조 (코어 발생)

**현상**: `qmgr_get_old_page()`에서 SEGFAULT
```
[09] qmgr_get_old_page at query_manager.c:2541
       page_p = tfile_vfid_p->membuf[vpid_p->pageid]
[08] split_task::get_next_page at px_hash_join_task_manager.cpp:573
```

**원인**: `qmgr_create_result_file()`로 생성된 FILE_QUERY_AREA는
`membuf_last = PRM - 1` (>= 0)이지만 `membuf = NULL`.
`membuf_last >= 0`만 검사하고 `membuf != NULL`을 검사하지 않아
membuf 포인터 배열이 NULL인 상태에서 인덱스 접근 시도.

**수정**: `membuf != NULL` 조건 추가.

### 9.5 goto와 변수 초기화 충돌 (빌드 에러)

**현상**: `-fpermissive` 에러 - `goto exit`가 변수 초기화를 건너뜀

**원인**: `all_partsects`, `n_partsects`가 블록 내부에서 선언되어 있었음.
앞쪽의 `goto exit`가 이 선언을 건너뛰어 C++ 컴파일 에러.

**수정**: 변수 선언을 함수 상단으로 이동.

---

## 10. 관련 소스 코드

| 위치 | 내용 |
|---|---|
| `src/storage/file_manager.c:11920` | `file_collect_data_pages()` 구현 |
| `src/storage/file_manager.c:12115` | `file_collect_data_pages_batch()` 구현 |
| `src/storage/file_manager.c:269-286` | `FILE_PARTIAL_SECTOR`, `FILE_ALLOC_BITMAP` 정의 |
| `src/storage/file_manager.c:3943-4003` | `file_table_collect_all_vsids()` (temp file 제한사항) |
| `src/storage/file_manager.c:7115-7198` | `file_table_collect_ftab_pages()` |
| `src/storage/storage_common.h:108-121` | `DISK_SECTOR_NPAGES`, `SECTOR_FIRST_PAGEID` 매크로 |
| `src/query/query_manager.c:2520-2573` | `qmgr_get_old_page()` (membuf vs 디스크 분기) |
| `src/query/query_manager.c:2927-3003` | `qmgr_allocate_tempfile_with_buffer()` (membuf 할당) |
| `src/query/query_manager.h:84-97` | `QMGR_TEMP_FILE` (membuf 필드) |
| `src/query/query_list.h:424-444` | `QFILE_LIST_ID` (dependent_list_id 필드) |
