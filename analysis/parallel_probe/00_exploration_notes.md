# Parallel Probe — 사전 탐색 노트

> Deep Interview 과정 중 수집한 코드베이스 사실 기록. 설계 결정의 근거 자료.

## 해시 조인 실행 경로 (현재)

- 진입: `src/query/query_hash_join.c:hjoin_execute_internal()` (c.610)
- 분기: `hjoin_try_partition()` (c.1167)에서 상태 결정
  - `HASHJOIN_STATUS_SINGLE` → `hjoin_execute` (순차)
  - `HASHJOIN_STATUS_PARTITION` → `hjoin_execute_partitions`
  - `HASHJOIN_STATUS_PARALLEL` → `parallel_query::hash_join::execute_partitions`
- Build: `hjoin_build()` c.2875, Probe: `hjoin_probe()` c.3130

## 해시 테이블 / 스캔 상태

- `MHT_HLS_TABLE` (`src/base/memory_hash.h:150`): 락 없음, build 후 read-only 전제
- `HASH_LIST_SCAN` (`src/query/query_hash_scan.h:110`):
  - `curr_hash_entry`, `curr_hash_key` 커서 포함 → **워커별 독립 복제 필요**
  - 해시 테이블 자체는 `union memory { MHT_HLS_TABLE *hash_table; ... }`로 참조(공유 가능)

## 병렬 인프라 (재사용 가능)

- `src/query/parallel/px_worker_manager.hpp` — `try_reserve_workers`, `push_task`, `wait_workers`, `release_workers`
- `src/query/parallel/px_parallel.cpp:36` `compute_parallel_degree()` — DOP 계산 (코어 수, PRM_ID_PARALLELISM, 페이지 임계값)
- `src/query/parallel/px_hash_join/px_hash_join_spawn_manager.*` — TLS로 워커당 VAL_DESCR/PRED_EXPR/REGU_VARIABLE_LIST 복제
- `src/query/parallel/px_hash_join/px_hash_join_task_manager.cpp:551` `get_next_page()` — 공유 `next_vpid`로 외부 입력 페이지 range 분배

## 결과 병합 템플릿

- `qfile_connect_list()` `src/query/list_file.c:3129`
- 사용처: `px_heap_scan_result_handler.cpp:531,550,1153` — **비파티션 병렬 스캔 결과를 단일 리스트로 연결하는 기존 패턴**

## 재사용성 요약

| 구성요소 | 재사용 | 비고 |
|---------|--------|------|
| `worker_manager`/`spawn_manager` | 직접 | 그대로 |
| 공유 페이지 기반 outer 분배 (`get_next_page`) | 직접 | 파티션 로직 생략 |
| 파티션 빌드 (`split_task` 파티션 파일 생성) | 제거 | non-partition 경로에선 불필요 |
| 공유 in-mem 해시테이블 참조 | 신규 | `MHT_HLS_TABLE` 공유 + 워커별 `HASH_LIST_SCAN` 커서 복제 |
| `qfile_connect_list` 결과 병합 | 직접 | px_heap_scan 패턴 차용 |

## 열린 질문 (인터뷰 대상)

- 트리거 조건 (outer 페이지 수/row 수 임계값?)
- DOP 결정 (기존 `compute_parallel_degree` 재사용? 별도 임계값?)
- 지원 JOIN 타입 (inner/left outer/semi/anti — `hjoin_init_context` c.2299 분기 참고)
- 결과 순서 보존 여부 (ORDER BY 없는 상황에서 append 순서 규정)
- 실패/에러 전파 (한 워커 오류 시 조기 중단 방식)
- 메모리 상한 (DOP × scan 커서 × qfile 버퍼)
- `HASHJOIN_STATUS_PARALLEL`과 공존 vs 대체
