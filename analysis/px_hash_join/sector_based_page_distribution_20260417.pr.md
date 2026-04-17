### Purpose

Parallel Hash Join 의 split phase 에서 worker 들이 페이지를 분배받는 방식을 mutex 기반 직렬화에서 sector bitmap 기반 lock-free 분배로 개선한다.

기존 구현은 모든 worker 가 단일 `scan_mutex` 를 잡고 `qmgr_get_old_page()` + `QFILE_GET_NEXT_VPID` 로 다음 페이지의 VPID 를 한 페이지씩 가져왔다. 모든 worker 가 동일한 mutex 를 경유하므로 worker 수에 비례한 선형 확장이 불가능하며, 매 페이지 fetch 마다 경합이 발생한다.

본 PR 은 file manager 가 이미 유지하고 있는 `FILE_PARTIAL_SECTOR` 의 VSID/page bitmap 을 사전에 수집해두고, worker 들이 atomic counter 로 섹터 인덱스를 work-stealing 방식으로 나눠 갖도록 split phase 를 재설계한다. 한 섹터(최대 64 페이지) 안에서는 mutex 없이 bit 순회로 VPID 를 직접 계산한다. `QFILE_LIST_ID` 의 첫 번째 list 에만 존재하는 membuf 페이지는 별도 CAS claim 경로로 한 worker 가 단독 처리한다.

추가로 overflow tuple(튜플이 한 페이지를 초과해 여러 페이지 chain 으로 저장) 처리를 섹터 기반 스캔과 호환되도록 수정한다. continuation 페이지가 일반 데이터 페이지와 같은 bitmap 에 올라오는 문제를 해결하고, base/dependent list 가 섞인 환경에서 페이지 해제 시 정확한 tfile 을 사용하도록 `m_current_tfile` 추적을 도입한다.

### Implementation

**신규 / 변경 자료구조**

- `QFILE_LIST_SECTOR_INFO` *(신규, query_list.h)* — base list 와 모든 dependent list 의 sector 정보를 단일 배열로 병합 (`membuf_tfile`, `sectors[]`, `tfiles[]`, `sector_cnt`).
- `HASHJOIN_SHARED_SPLIT_INFO` *(개정, query_hash_join.h)* — `scan_mutex` / `scan_position` / `next_vpid` 제거. `sector_info`, `membuf_claimed` (`std::atomic<bool>`), `next_sector_index` (`std::atomic<int>`) 추가.
- `split_task` per-thread 상태 *(px_hash_join_task_manager.hpp)* — `m_membuf_index`, `m_sector_index`, `m_current_bitmap`, `m_current_vsid`, `m_current_tfile`. `QMGR_TEMP_FILE` forward declaration 추가.

**신규 API**

- `file_get_all_data_sectors()` *(file_manager.c)* — temp / permanent file 양쪽에서 partial (perm 인 경우 full 까지) sector table 을 한 번에 훑어, FTAB / header 페이지 비트를 마스크 아웃한 data sector 배열을 반환.
- `qfile_collect_list_sector_info()` / `qfile_free_list_sector_info()` *(list_file.c)* — base list 의 membuf 정보 세팅 + dependent_list_id chain 순회 + sectors/tfiles 배열 realloc 병합 / 해제.

**동작 흐름**

1. **수집 (main thread)** — `build_partitions()` 가 outer/inner 라운드 시작 시 `qfile_collect_list_sector_info()` 호출. base + dependent list chain 을 순회하면서 각 tfile 의 partial sector table 을 `sectors[]` 에 병합하고, 동일 인덱스의 `tfiles[]` 에 tfile 포인터를 기록.
2. **atomic 리셋** — `membuf_claimed.store(false)`, `next_sector_index.store(0)`.
3. **분배 (worker)** — `split_task::get_next_page()`
   - **Phase 1 (membuf)**: `membuf_claimed` 에 CAS 를 시도해 성공한 worker 만 owner 가 되고, `m_membuf_index` 를 0 부터 순차 증가시키며 membuf 페이지를 반환. 반환 직전 `TUPLE_COUNT == QFILE_OVERFLOW_TUPLE_COUNT_FLAG` 인 overflow continuation 페이지는 skip.
   - **Phase 2 (sector)**: 현재 비트맵에서 lowest set bit 를 `__builtin_ctzll` 로 찾아 VPID 계산 후 fetch. 동일한 overflow continuation skip 적용. 비트맵이 비면 `next_sector_index.fetch_add(1)` 로 다음 섹터를 가져오고, `sector_cnt` 도달 시 `nullptr` 반환으로 종료.
   - 반환 페이지의 소속 tfile 을 `m_current_tfile` 에 기록.
4. **Overflow tuple 처리 (execute)** — start 페이지(`OVERFLOW_PAGE_ID != NULL_PAGEID`) 를 만나면 `QFILE_GET_OVERFLOW_VPID` chain 을 따라 continuation 페이지들을 직접 fetch 해 하나의 버퍼로 조립. continuation 페이지는 start 페이지와 같은 tfile 에 할당되므로 `m_current_tfile` 로 전체 chain 을 순회 가능.
5. **해제** — 라운드 종료 후 `qfile_free_list_sector_info()` 호출.

### Remarks

- **Membuf 는 첫 번째 list_id 에만 존재** — `qfile_connect_list()` 로 연결된 dependent list 에는 membuf 가 없다. 따라서 membuf 처리 경로는 base list 에만 적용한다.
- **NULL membuf 가드** — `FILE_QUERY_AREA` result file 은 `membuf_last >= 0` 이면서 `membuf == NULL` 인 경우가 있다. 반드시 `membuf != NULL` 체크를 동반해야 한다 (누락 시 SEGFAULT).
- **Temp file 은 full sector table 미사용** — 꽉 찬 섹터도 partial table 에 bitmap = all-1 상태로 남아 있다 (`file_temp_alloc` 주석 참조). partial table 만 훑어도 모든 섹터를 얻을 수 있다.
- **FTAB / header 비트 제거** — file header 와 extdata overflow 페이지는 데이터가 아니지만 섹터 bitmap 에 bit 가 set 되어 있어 `file_get_all_data_sectors()` 가 FTAB collector 로 마스크 아웃한다.
- **Extdata chain 전체 순회** — `file_extdata_apply_funcs()` 가 `vpid_next` chain 을 자동으로 따라가므로 섹터가 여러 페이지에 걸쳐 있어도 누락 없이 수집된다.
- **`tfiles[]` 병렬 배열** — base/dependent list 가 섞인 환경에서 `qmgr_get_old_page()` 에 올바른 tfile 핸들을 넘기기 위해 sector 와 동일 인덱스로 tfile 포인터를 보관한다.
- **`m_current_tfile` 추적** — `get_next_page()` 가 반환 시점에 기록한 tfile 을 `execute()` 가 페이지 해제와 overflow chain fetch 에 사용한다. 초기 구현은 `list_id->tfile_vfid` (base list tfile) 를 고정 사용해 dependent list 의 페이지에 대해 잘못된 tfile 을 넘기는 문제가 있었다.
- **Overflow continuation 페이지 skip** — continuation 페이지(`TUPLE_COUNT == QFILE_OVERFLOW_TUPLE_COUNT_FLAG`)는 일반 데이터 페이지와 같은 섹터 bitmap 에 포함되어 있다. start 페이지 소유 worker 가 VPID chain 으로 직접 따라가 처리하므로, bitmap 을 통해 만난 continuation 페이지는 skip 하여 이중 처리를 방지한다.
- 상세 분석: [`analysis/px_hash_join/sector_based_page_distribution_20260417.md`](./sector_based_page_distribution_20260417.md)
