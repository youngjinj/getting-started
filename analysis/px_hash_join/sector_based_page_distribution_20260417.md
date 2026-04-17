# Parallel Hash Join — Sector-Based Page Distribution

> 분석일: 2026-03-25 (membuf 처리 추가: 2026-03-26, 코드 최신화: 2026-04-07, 오버플로우 페이지 처리: 2026-04-17)  
> 대상: `src/query/parallel/px_hash_join/` split phase 의 페이지 분배 방식

---

## 목차

1. [개요](#1-개요)
2. [기존 방식 vs 새 방식](#2-기존-방식-vs-새-방식)
3. [QFILE_LIST_ID 페이지 구조](#3-qfile_list_id-페이지-구조)
4. [전체 동작 흐름](#4-전체-동작-흐름)
5. [변경 파일 상세](#5-변경-파일-상세)
6. [핵심 구조체](#6-핵심-구조체)
7. [주의사항](#7-주의사항)
8. [오버플로우 튜플 처리](#8-오버플로우-튜플-처리)

---

## 1. 개요

Parallel Hash Join 의 split phase 는 outer/inner list file 의 모든 페이지를 읽어 각 worker 가 파티션 단위로 나눠 담는 과정이다. 기존에는 worker 들이 하나의 `scan_mutex` 로 직렬화되어 페이지 단위로 다음 VPID 를 가져왔는데, 이는 worker 수가 늘어날수록 경합이 심해져 확장성을 해친다.

본 패치는 다음 두 아이디어로 이를 해소한다:

1. **Sector bitmap lock-free 분배** — File manager 가 이미 유지하고 있는 `FILE_PARTIAL_SECTOR` 의 VSID/비트맵을 사전에 수집해두고, worker 들이 `atomic<int>::fetch_add` 로 섹터 인덱스만 나눠 갖는다. 한 섹터(최대 64 페이지) 안에서는 mutex 없이 bit 순회로 VPID 를 계산할 수 있다.
2. **Membuf CAS claim** — `QFILE_LIST_ID` 의 첫 번째 list 에만 존재하는 membuf 페이지는 VPID chain 이 없고 `tfile->membuf[]` 배열 인덱스로만 접근 가능하다. 이 영역은 한 worker 가 CAS 로 소유권을 잡은 뒤 단독으로 순회한다.

```
                       +-------------------------+
                       |  qfile_collect_list_    |
                       |  sector_info()          |
                       |                         |
                       |  1. setup membuf info   |
                       |  2. collect disk sects  |
                       +------------+------------+
                                    |
                     +--------------+--------------+
                     |                             |
              membuf region                 disk sector region
          (first list_id only)          (all dependent list_ids)
                     |                             |
              +------+------+            +---------+---------+
              | CAS claim   |            | atomic fetch_add  |
              | (1 winner)  |            | (per sector)      |
              +------+------+            +---------+---------+
                     |                             |
              +------+------+            +---------+---------+
              |  Worker 0   |            | Worker 0,1,2,...N |
              |  pages 0~M  |            | per-sector dist.  |
              |  sequential |            | bitmap bit scan   |
              +------+------+            +---------+---------+
                     |                             |
                     +----- after membuf done -----+
                     |  join sector distribution   |
                     +-----------------------------+
```

---

## 2. 기존 방식 vs 새 방식

### 2.1 기존 방식 (mutex + VPID linked-list)

Split phase 의 각 worker 는 다음 VPID 를 얻기 위해 `scan_mutex` 를 잡고 `qmgr_get_old_page()` 로 페이지를 fix 한 뒤 `QFILE_GET_NEXT_VPID` 로 체인의 다음 포인터를 읽는다.

```
  Worker 0 --+
  Worker 1 --+-- lock(scan_mutex) -- qmgr_get_old_page(&next_vpid)
  Worker 2 --+       |                         |
                     |                         v
                     |               QFILE_GET_NEXT_VPID(page)
                     |                         |
                     +---- unlock <------------+

           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
           mutex contention on every page fetch
```

문제점:

- **직렬화**: 모든 worker 가 동일한 mutex 를 경유 → worker 수에 비례한 선형 확장이 불가능.

### 2.2 새 방식 (sector bitmap + atomic)

수집 단계에서 file manager 내부의 partial sector table 을 훑어 `FILE_PARTIAL_SECTOR` 배열(`{vsid, page_bitmap}`) 을 메모리에 복사해둔다. 분배 단계에서는 `std::atomic<int> next_sector_index` 하나로 모든 worker 가 섹터를 work-stealing 방식으로 나눠 갖는다.

```
  [ collect phase - main thread ]

  file header (temp file)
  +----------------------------------+
  |  partial sector table            |
  |  +---------+------------------+  |
  |  | VSID 0  | bitmap 0         |  |          QFILE_LIST_SECTOR_INFO
  |  | VSID 1  | bitmap 1         |--+------+   +--------------------------+
  |  | VSID 2  | bitmap 2         |  |      +-->| sectors   [0..N-1]       |
  |  |   ...   |   ...            |  |          | tfiles    [0..N-1]       |
  |  +---------+------------------+  |          | sector_cnt = N           |
  |  vpid_next --> [next page]       |          | membuf_tfile = ...       |
  +----------------------------------+          +--------------------------+

  [ distribute phase - lock-free ]

  next_sector_index : atomic<int> = 0

  Worker 0 : fetch_add -> idx=0 -> sectors[0].page_bitmap -> bit scan -> fetch pages
  Worker 1 : fetch_add -> idx=1 -> sectors[1].page_bitmap -> bit scan -> fetch pages
  Worker 2 : fetch_add -> idx=2 -> sectors[2].page_bitmap -> bit scan -> fetch pages
  Worker 0 : (sector 0 done) fetch_add -> idx=3 -> sectors[3] ...
```

### 2.3 비교

| 항목 | 기존 (mutex) | 새 방식 (sector) |
|---|---|---|
| 동기화 지점 | 매 페이지 (`scan_mutex`) | 매 섹터 (~64 페이지마다 `fetch_add`) |
| Membuf 처리 | 자연스러운 VPID chain | 별도 CAS claim 경로 필요 |
| Producer 병목 | 없음 | 없음 (수집은 사전 1회 완료) |
| 확장성 | worker 수에 반비례 | worker 수에 거의 무관 |

---

## 3. QFILE_LIST_ID 페이지 구조

`QFILE_LIST_ID` 의 페이지는 **membuf 영역**과 **disk 영역** 두 곳에 존재할 수 있다. 또한 여러 list 가 `dependent_list_id` 로 체인된다.

```
  QFILE_LIST_ID (base list)
   |
   +-- tfile_vfid --> QMGR_TEMP_FILE (tfile A)
   |                   +-- membuf[0..membuf_last]   (in-memory pages, volid = NULL_VOLID)
   |                   +-- membuf_last = M          (last used index)
   |                   +-- membuf (PAGE_PTR *)      (page pointer array)
   |                   +-- temp_vfid                (disk temp file VFID)
   |
   +-- first_vpid --> { NULL_VOLID, 0 }  (starts from membuf)
   |                  { NULL_VOLID, 1 }  -> ... -> { NULL_VOLID, M }
   |                  { volid    , pid } -> ... -> { volid    , pid }  (spills to disk)
   |
   +-- dependent_list_id --> QFILE_LIST_ID (list_1, tfile B: no membuf)
                              |
                              +-- dependent_list_id --> QFILE_LIST_ID (list_2, tfile C: no membuf)
```

**핵심 규칙:**

- **membuf 는 첫 번째 list_id 에만 존재** (dependent list 에는 없음).
- membuf 페이지: `volid == NULL_VOLID`, `pageid = 0 .. membuf_last`.
- disk 페이지: `volid != NULL_VOLID`, 각 tfile 의 partial sector table 에 기록.
- `qfile_connect_list()` 로 연결된 list 들은 **각각 다른 temp file** 에 속한다.

→ 섹터 분배기는 "**한 base list + 모든 dependent list**" 를 하나의 논리 단위로 본다. 각 섹터에는 어느 tfile 에 속하는지 기록해둬야 `qmgr_get_old_page()` 호출 시 올바른 temp file 핸들을 건넬 수 있다.

---

## 4. 전체 동작 흐름

### 4.1 오케스트레이션: `build_partitions()` — `px_hash_join.cpp:43`

Outer/inner 를 순차적으로 두 번 처리한다. 각 라운드 사이에 sector_info 를 해제하고 다시 수집하며, 두 atomic 상태(`membuf_claimed`, `next_sector_index`)도 재초기화한다.

```cpp
int build_partitions (cubthread::entry &thread_ref, HASHJOIN_MANAGER *manager,
                      HASHJOIN_SPLIT_INFO *split_info)
{
    HASHJOIN_SHARED_SPLIT_INFO shared_info;

    hjoin_init_shared_split_info (&thread_ref, manager, &shared_info);

    /* ====== outer relation split ====== */
    qfile_collect_list_sector_info (&thread_ref, outer->fetch_info->list_id,
                                    &shared_info.sector_info);
    shared_info.membuf_claimed.store (false, std::memory_order_relaxed);
    shared_info.next_sector_index.store (0);

    for (task_index = 0; task_index < task_cnt; task_index++)
      task_manager.push_task (new split_task (..., outer, &shared_info, ...));
    task_manager.join ();

    /* ====== inner relation split ====== */
    qfile_free_list_sector_info (&thread_ref, &shared_info.sector_info);  /* free outer */

    qfile_collect_list_sector_info (&thread_ref, inner->fetch_info->list_id,
                                    &shared_info.sector_info);
    shared_info.membuf_claimed.store (false, std::memory_order_relaxed);
    shared_info.next_sector_index.store (0);

    for (task_index = 0; task_index < task_cnt; task_index++)
      task_manager.push_task (new split_task (..., inner, &shared_info, ...));
    task_manager.join ();

    hjoin_clear_shared_split_info (&thread_ref, manager, &shared_info);
}
```

### 4.2 수집 단계: `qfile_collect_list_sector_info()` — `list_file.c:7085`

Base list 하나와 그 뒤에 체인된 모든 dependent list 를 순회하면서 각 tfile 의 disk sector 정보를 한 배열로 병합한다.

```
  qfile_collect_list_sector_info (thread_p, list_id, sector_info)
   |
   +-- [1] Setup membuf info (first list_id only)
   |       if (tfile_vfid->membuf != NULL && tfile_vfid->membuf_last >= 0)
   |           sector_info->membuf_tfile = tfile_vfid
   |
   +-- [2] Traverse dependent_list_id chain to collect disk VFIDs
   |       for (cur = list_id; cur != NULL; cur = cur->dependent_list_id)
   |           skip if VFID_ISNULL (membuf-only list has no disk file)
   |
   +-- [3] For each disk VFID:
           file_get_all_data_sectors (thread_p, &cur->tfile_vfid->temp_vfid, &collector)
              -> traverse partial sector table via file_extdata_apply_funcs
              -> collect FTAB / header page bits and mask them out of data bitmap
              -> fill collector.partsect_ftab[] with FILE_PARTIAL_SECTOR entries

           merge into sector_info:
              sectors [] = db_private_realloc + memcpy
              tfiles  [] = db_private_realloc + fill with cur->tfile_vfid
              sector_cnt += collector.nsects
```

**왜 partial sector table 만 보는가?** Temp file 은 full sector table 을 유지하지 않는다 (§7.3 참조). 꽉 찬 섹터도 partial table 에 bitmap 이 모두 1 인 상태로 남아 있으므로, partial table 만 훑으면 모든 섹터를 얻을 수 있다.

### 4.3 분배 단계: `split_task::get_next_page()` — `px_hash_join_task_manager.cpp:562`

Worker 마다 한 번씩 호출되어 다음 처리할 페이지를 반환한다. Phase 1 (membuf) → Phase 2 (sector) 로 진행되며, 한 번 membuf 를 claim 한 worker 는 소진될 때까지 Phase 1 을 반복하다가 자연스럽게 Phase 2 로 내려온다.

각 페이지 fetch 시 **overflow continuation 페이지**(`TUPLE_COUNT == -2`) 는 건너뛴다. overflow start 페이지를 가진 worker 가 VPID chain 을 따라 continuation 페이지들을 직접 fetch 하므로, 같은 페이지를 두 번 처리하지 않도록 해야 한다 (§8 참조). 반환할 페이지가 결정되면 `m_current_tfile` 에 해당 페이지의 소속 tfile 을 기록하여 호출자가 페이지 해제 시 올바른 핸들을 사용할 수 있게 한다.

```cpp
PAGE_PTR
split_task::get_next_page (cubthread::entry &thread_ref)
{
    QFILE_LIST_SECTOR_INFO *sector_info = &m_shared_info->sector_info;
    FILE_PARTIAL_SECTOR *sectors = sector_info->sectors;
    void **tfiles = sector_info->tfiles;

    /* ---- Phase 1 : membuf pages ---- */
    while (true)
      {
        if (m_membuf_index >= 0)                            /* already owner */
          {
            if (m_membuf_index <= sector_info->membuf_tfile->membuf_last)
              {
                VPID vpid = { NULL_VOLID, m_membuf_index++ };
                PAGE_PTR page = qmgr_get_old_page (&thread_ref, &vpid,
                                                   sector_info->membuf_tfile);
                if (page == nullptr)
                  return nullptr;

                /* skip overflow continuation pages */
                if (QFILE_GET_TUPLE_COUNT (page) == QFILE_OVERFLOW_TUPLE_COUNT_FLAG)
                  {
                    qmgr_free_old_page_and_init (&thread_ref, page,
                                                 sector_info->membuf_tfile);
                    continue;
                  }

                m_current_tfile = sector_info->membuf_tfile;
                return page;
              }
            m_membuf_index = -1;                            /* exhausted -> go to Phase 2 */
            break;
          }

        if (m_sector_index == -1 && sector_info->membuf_tfile != nullptr)
          {
            /* one-time CAS attempt: exactly one worker wins the membuf region */
            bool expected = false;
            if (m_shared_info->membuf_claimed.compare_exchange_strong (
                    expected, true, std::memory_order_acq_rel))
              {
                m_membuf_index = 0;
                continue;                                   /* re-enter Phase 1 as owner */
              }
          }
        break;                                              /* not the owner -> Phase 2 */
      }

    /* ---- Phase 2 : sector-based disk pages ---- */
    while (true)
      {
        while (m_current_bitmap != 0)                       /* drain current sector */
          {
            int bit_pos = __builtin_ctzll (m_current_bitmap);
            m_current_bitmap &= m_current_bitmap - 1;       /* clear lowest set bit */

            VPID vpid = { m_current_vsid.volid,
                          SECTOR_FIRST_PAGEID (m_current_vsid.sectid) + bit_pos };
            QMGR_TEMP_FILE *tfile = (QMGR_TEMP_FILE *) tfiles[m_sector_index];
            assert (tfile != nullptr);

            PAGE_PTR page = qmgr_get_old_page (&thread_ref, &vpid, tfile);
            if (page == nullptr)
              return nullptr;

            /* skip overflow continuation pages */
            if (QFILE_GET_TUPLE_COUNT (page) == QFILE_OVERFLOW_TUPLE_COUNT_FLAG)
              {
                qmgr_free_old_page_and_init (&thread_ref, page, tfile);
                continue;
              }

            m_current_tfile = tfile;
            return page;
          }

        /* grab next sector atomically */
        int sector_index = m_shared_info->next_sector_index.fetch_add (
                               1, std::memory_order_relaxed);
        if (sector_index >= sector_info->sector_cnt)
          return nullptr;                                   /* all sectors distributed */

        m_sector_index   = sector_index;
        m_current_vsid   = sectors[sector_index].vsid;
        m_current_bitmap = sectors[sector_index].page_bitmap;
      }
}
```

**Worker 별 실행 시나리오 (4 worker, 10 sector, membuf 존재)**

```
           time ------------------------------------------------>

  W 0 : [CAS win]  membuf p0..pM  |  sec 3  |  sec 7  |  done
  W 1 : [CAS fail]    sec 0       |  sec 4  |  sec 8  |  done
  W 2 : [CAS fail]    sec 1       |  sec 5  |  sec 9  |  done
  W 3 : [CAS fail]    sec 2       |  sec 6  |  done
```

- Worker 0 은 CAS 에 성공해 membuf 를 독점 처리한 뒤 sector 분배에 뒤늦게 합류.
- 나머지는 곧바로 sector 분배에 참여.
- 섹터 할당은 work-stealing 형태 — 빨리 끝난 worker 가 더 많은 섹터를 가져간다.

---

## 5. 변경 파일 상세

| 파일 | 변경 내용 |
|---|---|
| `storage/file_manager.h` | 기존 `FILE_PARTIAL_SECTOR { vsid, page_bitmap }`, `FILE_FTAB_COLLECTOR` 를 재사용. `file_get_all_data_sectors()` 선언 추가 |
| `storage/file_manager.c` | `file_get_all_data_sectors()` 구현. `file_extdata_apply_funcs()` 콜백으로 partial (그리고 perm file 이면 full) sector table 을 한 번에 훑어, FTAB/header 페이지 비트를 마스크 아웃한 data sector 배열을 반환 |
| `query/query_list.h` | `QFILE_LIST_SECTOR_INFO` 구조체 선언 (`membuf_tfile`, `sectors`, `tfiles`, `sector_cnt`), `QFILE_LIST_SECTOR_INFO_INITIALIZER`, `QFILE_INIT_LIST_SECTOR_INFO` 매크로 |
| `query/list_file.h` | `qfile_collect_list_sector_info()`, `qfile_free_list_sector_info()` 선언 |
| `query/list_file.c` | 두 함수 구현 — base list 의 membuf 정보 세팅 + dependent_list_id chain 순회 + `file_get_all_data_sectors()` 호출 + sectors/tfiles 배열 realloc 병합 |
| `query/query_hash_join.h` | `HASHJOIN_SHARED_SPLIT_INFO` 개정: `scan_mutex`, `scan_position`, `next_vpid` 제거. `sector_info` (`QFILE_LIST_SECTOR_INFO`), `membuf_claimed` (`atomic<bool>`), `next_sector_index` (`atomic<int>`) 추가 |
| `query/query_hash_join.c` | `hjoin_init_shared_split_info()` 에서 파티션 mutex 배열 초기화. `hjoin_clear_shared_split_info()` 에서 `qfile_free_list_sector_info()` 호출 |
| `query/parallel/px_hash_join/px_hash_join.cpp` | `build_partitions()` 가 outer/inner 각각에 대해 `qfile_collect_list_sector_info()` + atomic 리셋 + `split_task` 생성/실행 |
| `query/parallel/px_hash_join/px_hash_join_task_manager.hpp` | `split_task` 에 per-thread 상태 추가: `m_membuf_index`, `m_sector_index`, `m_current_bitmap`, `m_current_vsid`, `m_current_tfile`. `QMGR_TEMP_FILE` forward declaration 추가 |
| `query/parallel/px_hash_join/px_hash_join_task_manager.cpp` | `split_task::get_next_page()` 재작성 — Phase 1 (membuf CAS + sequential) → Phase 2 (sector bitmap lock-free). 양 Phase 에서 overflow continuation 페이지(`TUPLE_COUNT == QFILE_OVERFLOW_TUPLE_COUNT_FLAG`) 를 skip. 반환 페이지의 소속 tfile 을 `m_current_tfile` 에 기록. `execute()` 는 페이지 해제/overflow chain fetch 시 `list_id->tfile_vfid` 대신 `m_current_tfile` 을 사용 |

---

## 6. 핵심 구조체

### 6.1 QFILE_LIST_ID → 디스크 페이지 전체 레이아웃

```
  QFILE_LIST_ID
   +-- tfile_vfid --> QMGR_TEMP_FILE
   |                    +-- membuf[0..M]     (in-memory pages, volid = NULL_VOLID)
   |                    +-- temp_vfid (VFID) (disk temp file identifier)
   |                          |
   |                          v
   |   +------------------------------------------------+
   |   |  Disk page 0 (File Header Page)                |
   |   |                                                |
   |   |  FILE_HEADER                                   |
   |   |    self (VFID)                                 |
   |   |    n_sector_total                              |
   |   |    n_sector_partial                            |
   |   |    n_page_free                                 |
   |   |    offset_to_partial_ftab -----+               |
   |   |    ...                         |               |
   |   |                                v               |
   |   |  FILE_EXTENSIBLE_DATA (partial ftab)           |
   |   |    n_items = K                                 |
   |   |    size_of_item = sizeof(FILE_PARTIAL_SECTOR)  |
   |   |    vpid_next --> (overflow page)               |
   |   |                                                |
   |   |    [0]  FILE_PARTIAL_SECTOR                    |
   |   |           { vsid = {vol, sect}, page_bitmap }  |
   |   |    [1]  FILE_PARTIAL_SECTOR                    |
   |   |           { vsid = {vol, sect}, page_bitmap }  |
   |   |    ...                                         |
   |   |    [K]  FILE_PARTIAL_SECTOR                    |
   |   +------------------------------------------------+
   |                          |
   |                          | vpid_next (if items overflow one page)
   |                          v
   |   +------------------------------------------------+
   |   |  Disk page X (extdata overflow page)           |
   |   |                                                |
   |   |  FILE_EXTENSIBLE_DATA                          |
   |   |    [K+1] FILE_PARTIAL_SECTOR                   |
   |   |    [K+2] FILE_PARTIAL_SECTOR                   |
   |   |    ...                                         |
   |   |    vpid_next = NULL  (end of chain)            |
   |   +------------------------------------------------+
   |
   +-- dependent_list_id --> (another QFILE_LIST_ID, another temp_vfid)
```

**요점**

- 하나의 `VFID` = 하나의 `FILE_HEADER` = temp file 의 첫 번째 disk page.
- `FILE_HEADER` 안에 partial sector table (`FILE_EXTENSIBLE_DATA`) 의 시작점이 있음.
- `FILE_EXTENSIBLE_DATA` 는 `FILE_PARTIAL_SECTOR` 배열의 페이지 단위 컨테이너 — 한 페이지에 다 못 담으면 `vpid_next` 로 체이닝.
- Temp file 은 full sector table 을 쓰지 않아 모든 섹터가 partial table 에 존재 (§7.3).

### 6.2 FILE_EXTENSIBLE_DATA 순회 방식

`file_manager.c` 내부에서 extdata chain 을 순회하는 두 가지 방식이 있다. 둘 다 `static`/`STATIC_INLINE` 이라 외부에서 직접 사용할 수 없고, 외부에서는 `file_get_all_data_sectors()` 가 반환한 결과만 소비한다.

**1) 콜백 기반 — `file_extdata_apply_funcs()` (`file_manager.c:1886`)**

```c
/* file_get_all_data_sectors() — file_manager.c:12516 */
FILE_HEADER_GET_PART_FTAB (fhead, extdata_ftab);
file_extdata_apply_funcs (thread_p, extdata_ftab,
    file_extdata_collect_ftab_pages,        /* extdata callback: collect FTAB pages   */
    &ftab_collector,                        /* extdata callback arg                   */
    file_extdata_collect_data_sectors_part, /* item callback  : collect data sectors  */
    collector_out,                          /* item callback arg                      */
    false, NULL, NULL);
```

`vpid_next` chain 전체를 자동 순회하며 각 extdata 페이지와 그 안의 item 에 콜백을 적용한다. `file_get_all_data_sectors()` 는 이 방식을 사용해 FTAB 페이지와 데이터 섹터를 동시에 수집한다.

**2) 직접 순회 — for 루프 + `vpid_next`** (일부 내부 함수에서 사용)

```c
while (true)
  {
    for (ps = (FILE_PARTIAL_SECTOR *) file_extdata_start (extdata_iter);
         ps < (FILE_PARTIAL_SECTOR *) file_extdata_end (extdata_iter); ps++)
      {
        /* access ps->vsid, ps->page_bitmap */
      }

    vpid_next = extdata_iter->vpid_next;
    if (VPID_ISNULL (&vpid_next))
      break;

    page_iter    = pgbuf_fix (thread_p, &vpid_next, ...);
    extdata_iter = (FILE_EXTENSIBLE_DATA *) page_iter;
  }
```

### 6.3 QFILE_LIST_SECTOR_INFO / FILE_PARTIAL_SECTOR / FILE_FTAB_COLLECTOR

```c
/* query_list.h:534 */
typedef struct qfile_list_sector_info QFILE_LIST_SECTOR_INFO;
struct qfile_list_sector_info
{
  struct qmgr_temp_file *membuf_tfile;  /* tfile owning membuf pages (NULL = none) */
  struct file_partial_sector *sectors;  /* data page sectors (FTAB bits excluded)  */
  void **tfiles;                        /* parallel array: tfile pointer per sector */
  int sector_cnt;
};
#define QFILE_LIST_SECTOR_INFO_INITIALIZER { NULL, NULL, NULL, 0 }
```

```c
/* file_manager.h:161 */
typedef struct file_partial_sector FILE_PARTIAL_SECTOR;
struct file_partial_sector
{
  VSID vsid;                       /* sector ID (volid + sectid) */
  FILE_ALLOC_BITMAP page_bitmap;   /* UINT64 : bit N = 1 means page N allocated */
};
```

```c
/* file_manager.h:170 */
typedef struct file_ftab_collector FILE_FTAB_COLLECTOR;
struct file_ftab_collector
{
  int npages;
  int nsects;
  FILE_PARTIAL_SECTOR *partsect_ftab;
};
#define FILE_FTAB_COLLECTOR_INITIALIZER { 0, 0, NULL }
```

**Bitmap → VPID 변환 예시**

```
  sector VSID  = { volid = 10, sectid = 5 }
  page_bitmap  = 0b ... 0000 0000 0101 0011    (bits 0,1,4,6 set)

  SECTOR_FIRST_PAGEID (5) = 5 * 64 = 320

    bit 0 -> VPID { volid = 10, pageid = 320 }
    bit 1 -> VPID { volid = 10, pageid = 321 }
    bit 4 -> VPID { volid = 10, pageid = 324 }
    bit 6 -> VPID { volid = 10, pageid = 326 }
```

### 6.4 HASHJOIN_SHARED_SPLIT_INFO

모든 split_task 가 공유하는 read-mostly 상태. `sector_info` 는 수집 이후 read-only, 두 atomic 변수만 worker 들이 갱신한다.

```cpp
/* query_hash_join.h:252 */
typedef struct hashjoin_shared_split_info
{
  // *INDENT-OFF*
  QFILE_LIST_SECTOR_INFO sector_info;    /* sectors[] + tfiles[] (read-only after collect) */
  std::atomic<bool> membuf_claimed;      /* exactly one worker wins the membuf region     */
  std::atomic<int>  next_sector_index;   /* work-stealing cursor for sectors               */
  std::mutex       *part_mutexes;        /* per-partition mutexes for overflow append      */

  hashjoin_shared_split_info ()
    : sector_info (QFILE_LIST_SECTOR_INFO_INITIALIZER)
    , membuf_claimed (false)
    , next_sector_index (0)
    , part_mutexes (nullptr)
  {
  }
  // *INDENT-ON*
} HASHJOIN_SHARED_SPLIT_INFO;
```

### 6.5 split_task per-thread 상태

각 worker 가 자신만의 이터레이션 상태를 들고 있다. `m_membuf_index == -1` 은 "membuf owner 가 아님" 을, `m_sector_index == -1` 은 "아직 어떤 섹터도 가져오지 않음" 을 의미한다. `m_current_tfile` 은 가장 최근에 반환한 페이지의 소속 tfile 로, `execute()` 가 페이지를 해제하거나 overflow chain 을 따라갈 때 사용한다.

```cpp
/* px_hash_join_task_manager.hpp:141 */
class split_task: public base_task
{
  HASHJOIN_INPUT_SPLIT_INFO  *m_split_info;
  HASHJOIN_SHARED_SPLIT_INFO *m_shared_info;

  /* per-thread membuf iteration state:
   *   m_membuf_index == -1 : not the membuf owner
   *   m_membuf_index >=  0 : current membuf page index to read next
   */
  int m_membuf_index;

  /* per-thread sector iteration state */
  int             m_sector_index;    /* current sector index (-1 = need next sector) */
  UINT64          m_current_bitmap;  /* remaining page bits in current sector        */
  VSID            m_current_vsid;    /* current sector VSID                          */
  QMGR_TEMP_FILE *m_current_tfile;   /* tfile that owns the last returned page       */

  PAGE_PTR get_next_page (cubthread::entry &thread_ref);
};
```

---

## 7. 주의사항

### 7.1 FILE_QUERY_AREA 의 membuf_last 함정

`qmgr_create_result_file()` 로 생성된 result file 은 다음과 같은 상태를 갖는다:

```c
tfile_vfid->membuf_last   = PRM_ID_TEMP_MEM_BUFFER_PAGES - 1;  /* >= 0 */
tfile_vfid->membuf        = NULL;                              /* NULL ! */
tfile_vfid->membuf_npages = 0;
```

즉 **`membuf_last >= 0` 이지만 `membuf == NULL`** 인 케이스가 존재한다. 반드시 `membuf != NULL` 체크를 함께 수행해야 한다.

```c
/* qfile_collect_list_sector_info() — list_file.c:7100 */
if (list_id->tfile_vfid->membuf != NULL             /* <-- mandatory ! */
    && list_id->tfile_vfid->membuf_last >= 0)
  {
    assert (list_id->tfile_vfid->membuf_npages > 0);
    sector_info->membuf_tfile = list_id->tfile_vfid;
  }
```

이 체크가 누락되면 `qmgr_get_old_page()` 에서 `tfile->membuf[pageid]` 에 접근할 때 NULL 역참조로 SEGFAULT 가 발생한다:

```
  qmgr_get_old_page()  at  query_manager.c:2541
    page_p = tfile_vfid_p->membuf[vpid_p->pageid];   /* membuf == NULL -> CRASH */
```

### 7.2 dependent_list_id 의 membuf 부재

`qfile_connect_list()` 로 연결된 dependent list 는 **membuf 를 갖지 않는다**. connect 시 원본 list 의 tfile 이 그대로 연결되며, 모든 데이터 페이지가 disk 에 존재한다.

```
  base_list_id              (tfile A : has membuf, has disk)
    dependent_list_id #1    (tfile B : no membuf , disk only)
      dependent_list_id #2  (tfile C : no membuf , disk only)
```

→ 결과적으로 **membuf 처리 경로는 첫 번째 list_id 에 대해서만** 수행하면 된다. `qfile_collect_list_sector_info()` 도 이에 맞춰 첫 iteration 에서만 membuf 를 세팅한다.

### 7.3 Temp file 의 full sector 처리

Temp file 은 full sector table 을 유지하지 않는다. 꽉 찬 섹터도 partial table 에 bitmap 이 전부 1 인 상태로 남아있다. 이 설계는 `file_temp_alloc()` 의 주석에 명시되어 있다:

```c
/* file_temp_alloc() — file_manager.c:8625 */
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

반면 permanent file (`file_perm_alloc`) 은 섹터가 꽉 차면 partial table 에서 제거하고 full table 로 이동한다:

```c
/* file_perm_alloc() — file_manager.c:5166 */
if (is_full)
  {
    /* move to full table */
    vsid_full = partsect->vsid;
    file_extdata_remove_at (extdata_part_ftab, 0, 1);                        /* remove from partial */
    error_code = file_table_add_full_sector (thread_p, page_fhead, &vsid_full); /* add to full       */
  }
```

**결론:** `QFILE_LIST_ID` 의 temp file 은 항상 `FILE_IS_TEMPORARY` 이므로 partial sector table 만 훑으면 모든 섹터(꽉 찬 것 포함)를 얻을 수 있다. `file_get_all_data_sectors()` 는 safety net 으로 non-temporary 일 때만 full table 도 순회한다:

```c
/* file_get_all_data_sectors() — file_manager.c:12583 */
if (!FILE_IS_TEMPORARY (fhead))
  {
    /* traverse full table too - temp file does not take this path */
    FILE_HEADER_GET_FULL_FTAB (fhead, extdata_ftab);
    file_extdata_apply_funcs (thread_p, extdata_ftab, ...);
  }
```

→ 결과적으로 `file_get_all_data_sectors()` 는 temp / permanent 양쪽 모두 올바르게 처리한다.

### 7.4 Extdata chain 이 여러 페이지에 걸치는 경우

Partial sector table 은 `FILE_EXTENSIBLE_DATA` 컨테이너로 관리되며, 섹터가 많아지면 여러 페이지에 걸쳐 `vpid_next` 로 연결된다.

```
  page 0 (file header)              page X (extdata overflow)
  +----------------------+          +----------------------+
  | FILE_EXTENSIBLE_DATA |          | FILE_EXTENSIBLE_DATA |
  |   items[0..K]        |          |   items[0..J]        |
  |   vpid_next ---------+--------->|   vpid_next = NULL   |
  +----------------------+          +----------------------+
```

→ **첫 페이지만 훑으면 이후 섹터가 누락**된다. `file_extdata_apply_funcs()` 는 `vpid_next` chain 전체를 자동으로 따라가므로 `file_get_all_data_sectors()` 를 쓰면 이 이슈가 자연스럽게 해결된다.

### 7.5 FTAB / header 페이지 비트 제거

File header 페이지와 extdata overflow 페이지는 데이터 페이지가 아니지만, 소속 섹터의 bitmap 에는 bit 가 set 되어 있다. 이를 data sector bitmap 에서 빼주지 않으면 worker 가 FTAB 페이지를 데이터로 읽어 `QFILE_GET_TUPLE_COUNT` 에서 의미 없는 값을 얻는다.

`file_get_all_data_sectors()` 는 이 과정을 자동화한다:

1. `file_extdata_collect_ftab_pages` 콜백이 extdata chain 자체를 따라가면서 방문한 FTAB 페이지들을 `ftab_collector` 에 모은다.
2. 수집이 끝나면 FTAB 섹터/비트를 data sector bitmap 에서 마스크 아웃한다:

```c
/* file_get_all_data_sectors() — file_manager.c:12599 */
for (i = 0; i < ftab_collector.nsects; i++)
  {
    for (j = 0; j < collector_out->nsects; j++)
      {
        if (VSID_EQ (&ftab_collector.partsect_ftab[i].vsid,
                     &collector_out->partsect_ftab[j].vsid))
          {
            collector_out->partsect_ftab[j].page_bitmap
              &= ~ftab_collector.partsect_ftab[i].page_bitmap;
          }
      }
  }
```

참고로 `QFILE_GET_TUPLE_COUNT == 0` 인 페이지는 split 루프에서 자연스럽게 skip 되므로, 설령 FTAB 비트가 남아 있어도 정확성 문제는 없다. (정확한 page count 통계가 필요한 경우에만 영향)

### 7.6 `m_current_tfile` 을 통한 tfile 추적

`get_next_page()` 로 반환된 페이지는 base list 또는 dependent list 중 어느 쪽 tfile 에든 속할 수 있다. `execute()` 에서 페이지를 해제하거나 overflow chain 을 따라갈 때는 반드시 **해당 페이지의 소속 tfile** 을 사용해야 한다.

초기 구현에서는 `list_id->tfile_vfid` (base list 의 tfile) 를 고정으로 전달했으나, 이는 dependent list 의 페이지에 대해 잘못된 tfile 을 넘기는 문제가 있었다. 현재는 `get_next_page()` 가 반환 시점에 `m_current_tfile` 멤버에 정확한 tfile 을 기록하고, `execute()` 는 이 값을 사용한다:

```cpp
/* get_next_page() - Phase 1 */
m_current_tfile = sector_info->membuf_tfile;

/* get_next_page() - Phase 2 */
m_current_tfile = (QMGR_TEMP_FILE *) tfiles[m_sector_index];

/* execute() - page release */
qmgr_free_old_page_and_init (&thread_ref, page, m_current_tfile);

/* execute() - overflow chain follow */
overflow_page = qmgr_get_old_page (&thread_ref, &overflow_vpid, m_current_tfile);
```

overflow continuation 페이지는 `qfile_allocate_new_ovf_page()` 에 의해 start 페이지와 같은 tfile 에 할당되므로, chain 전체가 `m_current_tfile` 로 유효하다 (§8 참조).

### 7.7 `tfiles[]` 병렬 배열을 통한 정확한 tfile 조회

페이지 fetch 시점에도 올바른 tfile 을 넘겨야 한다. `qmgr_get_old_page()` 가 disk 페이지 경로에서 VPID 만 사용하더라도, membuf 경로나 내부 검증에서 tfile 을 참조할 수 있다.

`get_next_page()` 는 `m_sector_index` 로 `tfiles[]` 병렬 배열을 인덱싱하여 현재 섹터가 속한 tfile 을 직접 얻는다:

```cpp
/* px_hash_join_task_manager.cpp:632 */
QMGR_TEMP_FILE *tfile = (QMGR_TEMP_FILE *) tfiles[m_sector_index];
PAGE_PTR page = qmgr_get_old_page (&thread_ref, &vpid, tfile);
```

이는 `qfile_collect_list_sector_info()` 의 수집 단계에서 각 섹터에 대응하는 tfile 을 `tfiles[]` 에 기록해두었기 때문에 가능하다:

```c
/* list_file.c:7148 */
for (int i = 0; i < collector.nsects; i++)
  {
    sector_info->tfiles[old_cnt + i] = (void *) current->tfile_vfid;
  }
```

이 패턴 덕분에 base/dependent list 가 섞여 있는 경우에도 각 섹터의 페이지를 올바른 temp file 핸들과 함께 fetch 할 수 있다. Phase 1 (membuf) 에서는 `sector_info->membuf_tfile` 을 사용한다 — `qfile_collect_list_sector_info()` 에서 `sector_info->membuf_tfile = list_id->tfile_vfid` 로 설정되므로 두 값은 동일하다.

---

## 8. 오버플로우 튜플 처리

튜플 크기가 한 페이지(16KB)를 초과하면 list file 은 **overflow tuple** 로 저장한다. 하나의 튜플이 여러 페이지에 걸쳐 저장되며, 각 페이지는 `QFILE_GET_OVERFLOW_VPID()` chain 으로 연결된다.

### 8.1 overflow 페이지 구조

- **Start 페이지**: `TUPLE_COUNT = 1`, `OVERFLOW_PAGE_ID` 가 첫 번째 continuation 페이지를 가리킨다. 튜플 헤더 + 데이터의 첫 번째 조각을 담는다.
- **Continuation 페이지**: `TUPLE_COUNT = QFILE_OVERFLOW_TUPLE_COUNT_FLAG (-2)`, `OVERFLOW_PAGE_ID` 가 다음 continuation 페이지 또는 `NULL_PAGEID` (chain 의 마지막).

```
  Start page                Continuation 1            Continuation 2 (last)
  +--------------------+    +--------------------+    +--------------------+
  | TUPLE_COUNT = 1    |    | TUPLE_COUNT = -2   |    | TUPLE_COUNT = -2   |
  | OVERFLOW_ID -------+--->| OVERFLOW_ID -------+--->| OVERFLOW_ID = NULL |
  |                    |    |                    |    |                    |
  | tuple header +     |    | tuple data         |    | tuple data         |
  | tuple data (part1) |    | (part 2)           |    | (part 3)           |
  +--------------------+    +--------------------+    +--------------------+
```

`qfile_allocate_new_ovf_page()` 가 continuation 페이지를 할당할 때 **start 페이지와 같은 `tfile_vfid`** 를 사용하므로, 한 튜플의 overflow chain 은 항상 같은 tfile 에 속한다.

### 8.2 섹터 스캔에서의 문제

Overflow continuation 페이지는 일반 데이터 페이지와 같은 `file_alloc()` 으로 할당되므로 **같은 섹터 bitmap 에 비트가 서 있다**. 다른 섹터를 할당받은 worker 가 섹터 스캔 중 continuation 페이지를 만날 수 있다.

```
  sector A : [normal] [normal] [overflow start P3] ---OVERFLOW_ID--> P4
  sector B : [continuation P4 (TUPLE_COUNT=-2)] [normal]
```

만약 continuation 페이지를 일반 페이지처럼 `execute()` 에 넘기면:

- `QFILE_GET_TUPLE_COUNT(page) = -2` → `tuple_cnt` 에 음수가 들어가 로직이 깨짐
- 과거 구현은 `assert(tuple_cnt == 1)` 에서 abort 하여 서버 크래시 발생

### 8.3 해결: 양방향 처리

**(1) Continuation 페이지 skip** — `get_next_page()` 의 Phase 1/Phase 2 에서 반환 직전에 체크:

```cpp
if (QFILE_GET_TUPLE_COUNT (page) == QFILE_OVERFLOW_TUPLE_COUNT_FLAG)
  {
    qmgr_free_old_page_and_init (&thread_ref, page, tfile);
    continue;                /* try next page in bitmap */
  }
```

**(2) Start 페이지에서 chain 전체를 조립** — `execute()` 에서 `OVERFLOW_PAGE_ID != NULL_PAGEID` 인 페이지를 만나면 VPID chain 을 직접 따라가 전체 튜플을 하나의 버퍼에 복원:

```cpp
/* execute() - overflow tuple reconstruction */
if (QFILE_GET_OVERFLOW_PAGE_ID (page) != NULL_PAGEID)
  {
    overflow_page = page;
    copy_offset = 0;

    do
      {
        memcpy (overflow_record.tpl + copy_offset,
                (char *) overflow_page + QFILE_PAGE_HEADER_SIZE, copy_size);

        QFILE_GET_OVERFLOW_VPID (&overflow_vpid, overflow_page);

        if (overflow_page != page)
          {
            /* overflow continuation pages share the same tfile as the start page
             * (see qfile_allocate_new_ovf_page) */
            qmgr_free_old_page_and_init (&thread_ref, overflow_page, m_current_tfile);
          }

        if (VPID_ISNULL (&overflow_vpid))
          break;

        /* follow the chain directly via VPID — crosses sector boundaries */
        overflow_page = qmgr_get_old_page (&thread_ref, &overflow_vpid, m_current_tfile);
      }
    while (!VPID_ISNULL (&overflow_vpid));

    tuple_record.tpl = overflow_record.tpl;
  }
```

**요점:**

- Start 페이지 소유자 worker 는 섹터 경계를 넘어서 VPID chain 을 **직접** 따라간다.
- Continuation 페이지의 섹터 소유자는 해당 페이지를 skip 해서 **이중 처리를 방지** 한다.
- 두 worker 가 동시에 다른 페이지를 처리하므로 동기화는 필요 없다 (각 페이지 fetch 는 page buffer latch 로 보호됨).

### 8.4 Worker 간 상호작용

```
  sector A owner (worker W0)              sector B owner (worker W1)
  -----------------------------           -----------------------------
  1. fetch P3 (start page)                1. fetch P4 (continuation)
     TUPLE_COUNT = 1                         TUPLE_COUNT = -2
     -> process as overflow start           -> skip via get_next_page()
  2. VPID chain follow                     2. move to next bitmap bit
     qmgr_get_old_page(P4)
     memcpy overflow data
  3. QFILE_GET_OVERFLOW_VPID -> NULL
     -> chain complete
  4. tuple_record = reconstructed tpl
```

두 worker 는 독립적으로 동작하지만 overflow 튜플은 정확히 한 번만 처리된다.

### 8.5 회귀 테스트

아래 시나리오가 모두 정상 동작해야 한다:

1. 싱글 해시 조인 (`no_parallel_hash_join`) — 기준점
2. 파티션 해시 조인 (`no_parallel_hash_join` + `max_hash_list_scan_size=256k`)
3. 병렬 해시 조인 (`max_hash_list_scan_size=256k`)
4. 아우터 조인 + 오버플로우 — NULL 키가 마지막 파티션에 배치되는 경로
5. 싱글 vs 병렬 데이터 정합성 (EXCEPT 로 diff 검증)
6. 3 페이지 이상 chain (매우 큰 튜플)
7. membuf 만 사용하는 작은 데이터셋 — Phase 1 에서의 skip 검증
