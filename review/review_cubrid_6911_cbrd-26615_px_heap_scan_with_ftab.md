# PR-6911 [CBRD-26615] Parallel Heap Scan with FTAB 분석

## 변경 개요

Parallel Heap Scan의 input_handler를 **Mutex 기반 순차 페이지 분배**에서
**FTAB 기반 Lock-free 섹터 사전 분배**로 리팩토링.

## 변경 동기

기존 `input_handler_single_table`은 모든 worker 스레드가 하나의 mutex를 경합하며
순차적으로 다음 VPID를 가져가는 구조였다. worker 수가 늘어날수록 mutex 경합이
병목이 되어 병렬 스캔의 scalability가 제한되었다.

## 구조 변경

### 기존 설계 (`input_handler_single_table`)

```
input_handler (abstract base, virtual 메서드)
  └── input_handler_single_table (상속)
        - m_vpid: 현재 스캔 위치 (공유)
        - m_vpid_mutex: VPID 접근 보호 ← 모든 worker 경합 지점
        - heap_page_next_fix_old()로 순차 순회
```

동작:
```
Worker-1 ──┐
Worker-2 ──┼── mutex 대기 ──→ 다음 VPID 가져가기 ──→ 페이지 처리
Worker-3 ──┘
```

### 새로운 설계 (`input_handler_ftabs`)

```
input_handler_ftabs (concrete, 상속 없음)
  - m_ftab_set: master 섹터 집합
  - m_splited_ftab_set[]: worker별 사전 분배된 섹터
  - m_splited_ftab_set_idx: worker 할당 카운터 (atomic)
  - thread_local 상태: 각 worker 독립 동작
```

동작:
```
초기화 시: 전체 섹터 수집 → worker 수만큼 분할

Worker-1 ──→ [섹터 A, D, G] ──→ 독립 순회 (lock-free)
Worker-2 ──→ [섹터 B, E, H] ──→ 독립 순회 (lock-free)
Worker-3 ──→ [섹터 C, F, I] ──→ 독립 순회 (lock-free)
```

## 핵심 자료구조

### `ftab_set` (`px_heap_scan_ftab_set.hpp`)

```cpp
class ftab_set {
    std::vector<FILE_PARTIAL_SECTOR> m_ftab_set;  // 섹터 컬렉션
    size_t iterator;                               // 현재 위치

    void convert(FILE_FTAB_COLLECTOR *ftab_collector);  // collector → ftab_set
    std::vector<ftab_set> split(int n_sets);             // worker 수만큼 분할
    FILE_PARTIAL_SECTOR get_next();                      // 다음 섹터 반환
};
```

`split()` 구현 — 섹터를 worker 수만큼 균등 분배 (`px_heap_scan_ftab_set.hpp` 55-78):
```cpp
std::vector<ftab_set> split (int n_sets)
{
  std::vector<ftab_set> sets;
  size_t size = m_ftab_set.size ();
  size_t n_elements_per_set = size / (size_t) n_sets;
  size_t remainder = size % (size_t) n_sets;
  size_t start_idx = 0;

  for (size_t i = 0; i < (size_t) n_sets; i++)
    {
      size_t current_set_size = n_elements_per_set + (i < remainder ? 1 : 0);
      ftab_set set;
      set.m_ftab_set = std::vector<FILE_PARTIAL_SECTOR> (
          m_ftab_set.begin () + start_idx,
          m_ftab_set.begin () + start_idx + current_set_size);
      sets.push_back (set);
      start_idx += current_set_size;
    }
  return sets;
}
```

### `input_handler_ftabs` (`px_heap_scan_input_handler_ftabs.hpp`)

```cpp
class input_handler_ftabs {
    ftab_set m_ftab_set;                          // master 섹터 집합
    std::vector<ftab_set> m_splited_ftab_set;     // worker별 분배된 섹터
    std::atomic_int m_splited_ftab_set_idx;       // worker 할당 카운터

    // Thread-local 상태 (동기화 불필요)
    thread_local static VPID m_tl_vpid;
    thread_local static HEAP_SCANCACHE *m_tl_scan_cache;
    thread_local static PGBUF_WATCHER m_tl_old_page_watcher;
    thread_local static ftab_set *m_tl_ftab_set;
    thread_local static size_t m_tl_pgoffset;
    thread_local static FILE_PARTIAL_SECTOR m_tl_ftab;
};
```

## 초기화 흐름

`px_heap_scan.cpp` 680-697 라인에서 3단계로 초기화:

```
1. db_private_alloc() + placement new
2. init_on_main(thread_p, hfid, parallelism):
   a. file_get_all_data_sectors() → 전체 heap 섹터 수집
   b. ftab_set::convert() → collector 결과를 ftab_set으로 변환
   c. ftab_set::split(parallelism) → worker 수만큼 분할
3. 각 worker는 init_on_worker()에서 atomic idx로 자기 ftab_set 할당
```

코드 (`px_heap_scan.cpp` 680-697):
```cpp
m_input_handler = (input_handler *) db_private_alloc (m_thread_p, sizeof (input_handler));
new (m_input_handler) input_handler ();

if (m_input_handler->init_on_main (m_thread_p, m_hfid, m_parallelism) != NO_ERROR)
  {
    m_input_handler->~input_handler ();
    db_private_free_and_init (m_thread_p, m_input_handler);
    return ER_FAILED;
  }
```

`init_on_main()` 구현 (`px_heap_scan_input_handler_ftabs.cpp` 69-94):
```cpp
int input_handler_ftabs::init_on_main (THREAD_ENTRY *thread_p, HFID hfid, int parallelism)
{
  FILE_FTAB_COLLECTOR collector;
  m_hfid = hfid;

  /* 1. 전체 데이터 섹터 수집 */
  error_code = file_get_all_data_sectors (thread_p, &m_hfid.vfid, &collector);
  if (error_code != NO_ERROR) return error_code;

  /* 2. collector → ftab_set 변환 */
  m_ftab_set.convert (&collector);

  /* 3. worker 수만큼 분할 */
  m_splited_ftab_set = m_ftab_set.split (parallelism);
  m_splited_ftab_set_idx.store (0);
  m_ftab_set.clear ();

  db_private_free_and_init (thread_p, collector.partsect_ftab);
  return NO_ERROR;
}
```

worker 초기화 — atomic idx로 자기 ftab_set 할당 (`px_heap_scan_input_handler_ftabs.cpp` 51-67):
```cpp
int input_handler_ftabs::initialize (THREAD_ENTRY *thread_p, HFID *hfid, SCAN_ID *scan_id)
{
  m_tl_scan_cache = &scan_id->s.hsid.scan_cache;
  PGBUF_INIT_WATCHER (&m_tl_old_page_watcher, PGBUF_ORDERED_HEAP_NORMAL, hfid);

  /* atomic으로 자기 ftab_set index 할당 — lock-free */
  int idx = m_splited_ftab_set_idx.fetch_add (1);
  m_tl_ftab_set = &m_splited_ftab_set[idx];

  m_tl_vpid = {-1, 0};
  m_tl_pgoffset = 0;
  return NO_ERROR;
}
```

## 페이지 순회 방식 변경

### 기존

```cpp
// mutex 보호 하에 순차 접근
ret_code = heap_page_next_fix_old (thread_p, &m_hfid, &m_vpid, m_tl_scan_cache);
```

### 변경 후 (`px_heap_scan_input_handler_ftabs.cpp` 96-172)

`get_next_vpid_with_fix()` 전체 흐름:
```cpp
SCAN_CODE input_handler_ftabs::get_next_vpid_with_fix (THREAD_ENTRY *thread_p, VPID *vpid)
{
  bool found = false;
  while (!found)
    {
      if (VPID_ISNULL (&m_tl_vpid))
        {
          /* 1. thread-local ftab_set에서 다음 섹터 가져오기 */
          m_tl_ftab = m_tl_ftab_set->get_next ();
          if (VSID_IS_NULL (&m_tl_ftab.vsid))
            return S_END;  /* 더 이상 섹터 없음 */

          m_tl_pgoffset = 0;
          m_tl_vpid.volid = m_tl_ftab.vsid.volid;
          m_tl_vpid.pageid = SECTOR_FIRST_PAGEID (m_tl_ftab.vsid.sectid);

          /* 2. heap header 페이지 skip */
          if (m_tl_vpid.volid == m_hfid.vfid.volid
              && m_tl_vpid.pageid == m_hfid.vfid.fileid)
            {
              m_tl_pgoffset++;
              m_tl_vpid.pageid++;
            }
        }

      /* 3. 섹터 내 페이지를 bitmap으로 순회 */
      for (; m_tl_pgoffset < DISK_SECTOR_NPAGES; m_tl_pgoffset++, m_tl_vpid.pageid++)
        {
          if (bit64_is_set (m_tl_ftab.page_bitmap, (int) m_tl_pgoffset))
            {
              /* 4. 이전 페이지를 old watcher로 이동 */
              if (m_tl_scan_cache->page_watcher.pgptr != NULL)
                pgbuf_replace_watcher (thread_p, &m_tl_scan_cache->page_watcher,
                                       &m_tl_old_page_watcher);

              /* 5. ordered fix (allow_not_ordered_page=true) */
              error_code = pgbuf_ordered_fix (thread_p, &m_tl_vpid,
                  OLD_PAGE_PREVENT_DEALLOC, PGBUF_LATCH_READ,
                  &m_tl_scan_cache->page_watcher, true);
                                             /* ↑ true = FTAB 메타페이지 skip */

              /* 6. 이전 페이지 unfix */
              if (m_tl_old_page_watcher.pgptr != NULL)
                pgbuf_ordered_unfix (thread_p, &m_tl_old_page_watcher);

              /* 7. skip된 페이지(non-ordered type)면 다음으로 */
              if (m_tl_scan_cache->page_watcher.pgptr == NULL)
                continue;

              *vpid = m_tl_vpid;
              return S_SUCCESS;
            }
        }
      /* 섹터 끝 → 다음 섹터로 */
      m_tl_vpid.pageid = -1;  /* VPID_ISNULL 트리거 */
    }
}
```

## FTAB 메타페이지 문제와 `allow_not_ordered_page`

### 문제: bitmap은 페이지 타입을 구분하지 못한다

기존 `heap_page_next_fix_old()`는 heap page chain(`HEAP_CHAIN.next_vpid`)을 따라가므로
heap 데이터 페이지만 방문했다. 그러나 FTAB 방식은 섹터의 `page_bitmap`으로 순회하므로,
같은 섹터 안에 섞여 있는 FTAB 메타데이터 페이지도 만날 수 있다.

```
섹터 N: [heap][heap][FTAB][heap][heap]...
bitmap:   1     1     1     1     1
                      ↑
                      할당은 되어 있지만 FTAB 메타페이지
                      bitmap만으로는 구분 불가
```

### 현재 해결: `allow_not_ordered_page` 파라미터

`pgbuf_ordered_fix`에 `allow_not_ordered_page` 인자가 추가됨.
`true`이면 fix 후 페이지 타입을 확인하고, `PAGE_HEAP`/`PAGE_OVERFLOW`가 아니면
에러 없이 unfix하고 skip한다.

이 파라미터에 `true`를 넘기는 곳은 **parallel heap scan 한 곳뿐**이다.
매크로 `pgbuf_ordered_fix`는 항상 `false`를 하드코딩하므로,
매크로를 우회하여 `pgbuf_ordered_fix_release`/`pgbuf_ordered_fix_debug`를 직접 호출한다.

```c
/* 매크로 (page_buffer.h:325) — 항상 false */
#define pgbuf_ordered_fix(thread_p, req_vpid, fetch_mode, requestmode, req_watcher) \
        pgbuf_ordered_fix_release(thread_p, ..., req_watcher, false)

/* parallel heap scan만 직접 호출 — true */
pgbuf_ordered_fix_release (thread_p, &m_tl_vpid, ..., &watcher, true);
```

`pgbuf_ordered_fix` 내부에서 체크가 **두 군데** 필요한 이유는 fix가 두 경로에서 발생하기 때문이다:

| 경로 | fix 위치 | 타입 체크 위치 |
|------|---------|-------------|
| 낙관적 (conditional fix 성공) | 12062 | 12070 |
| 비관적 (conditional fix 실패 → refix) | 12562 | 12607 |

### `file_get_all_data_sectors`와 `file_table_collect_ftab_pages`의 관계

두 함수는 같은 형태의 결과(`FILE_FTAB_COLLECTOR` — 섹터 + bitmap)를 반환하지만,
수집 대상이 다르다:

| 함수 | 수집 대상 | 순회 방식 |
|------|----------|----------|
| `file_get_all_data_sectors` | 데이터 페이지가 있는 섹터 | partial/full 섹터 테이블 순회 |
| `file_table_collect_ftab_pages` | FTAB 메타데이터 페이지 | FTAB 체인의 `vpid_next` linked list 순회 |

`file_table_collect_ftab_pages`의 FTAB 구분 방식:

```c
/* file_table_collect_ftab_pages (file_manager.c 7097-7171) */

/* 1. file header 페이지 자체를 FTAB으로 등록 */
pgbuf_get_vpid (page_fhead, &vpid_fhead);
file_partsect_set_bit (..., vpid_fhead.pageid);

/* 2. partial 섹터 테이블 체인 순회 */
FILE_HEADER_GET_PART_FTAB (fhead, extdata_ftab);
file_extdata_apply_funcs (..., file_extdata_collect_ftab_pages, ...);

/* 3. full 섹터 테이블 체인 순회 */
FILE_HEADER_GET_FULL_FTAB (fhead, extdata_ftab);
file_extdata_apply_funcs (..., file_extdata_collect_ftab_pages, ...);
```

FTAB 페이지의 식별은 **페이지 타입 검사가 아니라, 파일 테이블 linked list
(`FILE_EXTENSIBLE_DATA.vpid_next`) 체인을 따라가는 구조적 추적**으로 이루어진다.
체인에 속한 페이지 = FTAB 메타페이지, 속하지 않은 페이지 = 데이터 페이지이다.

콜백 `file_extdata_collect_ftab_pages`는 구분 로직 없이, 넘겨받은 `extdata->vpid_next`를
그대로 bitmap에 기록할 뿐이다:

```c
/* file_extdata_collect_ftab_pages (file_manager.c 7183-7223) */
static int
file_extdata_collect_ftab_pages (..., const FILE_EXTENSIBLE_DATA * extdata, ...)
{
  if (!VPID_ISNULL (&extdata->vpid_next))
    {
      /* vpid_next를 bitmap에 기록 — 구분 로직 없이 수집만 */
      file_partsect_set_bit (&collect->partsect_ftab[idx_sect],
          file_partsect_pageid_to_offset (..., extdata->vpid_next.pageid));
    }
}
```

### 개선 가능성: 초기화 시 bitmap에서 FTAB 페이지 제거

`init_on_main()`에서 데이터 섹터 수집 시 FTAB 페이지를 미리 bitmap에서 제거하면,
`pgbuf_ordered_fix`에 `allow_not_ordered_page` 파라미터를 추가할 필요가 없다:

```cpp
// init_on_main에서
FILE_FTAB_COLLECTOR data_collector, ftab_collector;

file_get_all_data_sectors (thread_p, &vfid, &data_collector);
file_table_collect_ftab_pages (thread_p, page_fhead, false, &ftab_collector);

// 데이터 섹터 bitmap에서 FTAB 페이지 비트 제거
for (each ftab_sector in ftab_collector)
  for (each data_sector in data_collector)
    if (같은 섹터)
      data_sector.page_bitmap &= ~ftab_sector.page_bitmap;
```

이 방식의 장점:
- `pgbuf_ordered_fix`의 인터페이스 변경 불필요
- 범용 함수에 특수 용도 파라미터가 들어가지 않음
- 순회 시점이 아닌 초기화 시점에 1회만 처리

## Page Watcher 관리

이전 페이지의 ordered unfix 순서를 보장하기 위해 두 개의 watcher를 사용한다.
새 페이지를 fix하기 전에 현재 페이지를 old watcher로 이동시키고,
새 페이지 fix 후에 old를 unfix하는 순서를 지킨다.

```
[fix 순서]
1. replace_watcher: current → old     (포인터만 이동, unfix 아님)
2. ordered_fix: new → current         (새 페이지 fix)
3. ordered_unfix: old                 (이전 페이지 unfix)
```

이렇게 하면 `pgbuf_ordered_fix` 내부에서 old 페이지와 new 페이지의 VPID 순서를
비교하여 필요 시 재정렬할 수 있다.

`finalize()` — worker 종료 시 남은 watcher 정리 (`px_heap_scan_input_handler_ftabs.cpp` 174-188):
```cpp
int input_handler_ftabs::finalize (THREAD_ENTRY *thread_p)
{
  if (m_tl_old_page_watcher.pgptr != NULL)
    pgbuf_ordered_unfix (thread_p, &m_tl_old_page_watcher);

  if (m_tl_scan_cache->page_watcher.pgptr != NULL)
    pgbuf_ordered_unfix (thread_p, &m_tl_scan_cache->page_watcher);

  m_tl_scan_cache = NULL;
  m_tl_old_page_watcher.pgptr = NULL;
  return NO_ERROR;
}
```

## 파일 변경 목록

| 변경 | 파일 | 설명 |
|------|------|------|
| 삭제 | `px_heap_scan_input_handler.hpp` | abstract base class 제거 |
| 삭제 | `px_heap_scan_input_handler_single_table.hpp` | 기존 구현 헤더 제거 |
| 삭제 | `px_heap_scan_input_handler_single_table.cpp` | 기존 구현 제거 |
| 신규 | `px_heap_scan_input_handler_ftabs.hpp` | 새 concrete class 헤더 |
| 신규 | `px_heap_scan_input_handler_ftabs.cpp` | 새 구현 |
| 신규 | `px_heap_scan_ftab_set.hpp` | 섹터 분배 컨테이너 |
| 수정 | `px_heap_scan.hpp` | type alias + 멤버 변수 타입 변경 |
| 수정 | `px_heap_scan.cpp` | includes, 초기화 로직, 소멸자 |
| 수정 | `px_heap_scan_task.hpp` | type alias 업데이트 |
| 수정 | `page_buffer.h` | `allow_not_ordered_page` 파라미터 시그니처 |
| 수정 | `page_buffer.c` | `allow_not_ordered_page` 처리 로직 |
| 수정 | `heap_file.c` | 새 pgbuf API에 맞춰 파라미터 업데이트 |
| 수정 | `file_manager.h` | `file_get_all_data_sectors()` 선언 |
| 수정 | `file_manager.c` | `file_get_all_data_sectors()` 구현 |

## 기존 대비 개선 효과

| | 기존 (single_table) | 변경 후 (ftabs) |
|---|---|---|
| 동기화 | mutex (모든 worker 경합) | lock-free (thread-local) |
| 페이지 분배 | 런타임 순차 할당 | 초기화 시 사전 분배 |
| 분배 비용 | O(n) per page access | O(1) per worker init |
| scalability | worker 증가 시 mutex 병목 | worker 증가에 선형 확장 |
| 상속 구조 | virtual 메서드 + abstract base | concrete class (오버헤드 없음) |

## 관련 소스 파일

- `src/query/parallel/px_heap_scan/px_heap_scan.cpp` — 초기화 흐름 (680-697)
- `src/query/parallel/px_heap_scan/px_heap_scan_input_handler_ftabs.cpp` — 페이지 순회 (96-172)
- `src/query/parallel/px_heap_scan/px_heap_scan_ftab_set.hpp` — 섹터 분배 자료구조
- `src/storage/page_buffer.c` — `allow_not_ordered_page` 처리 (12070-12078)
- `src/storage/file_manager.c` — `file_get_all_data_sectors()` 구현
