# SINGLE 경로 Probe 병렬화 타당성 — 재검증 결과

## 결정된 Scope

- **적용 대상**: `HASHJOIN_STATUS_SINGLE` 진입 케이스 (in-memory `MHT_HLS_TABLE`, 파티션 미사용)
- **중첩 금지**: `HASHJOIN_STATUS_PARALLEL`(파티션+병렬) 실행 중 Parallel Probe 재활성화 금지 — 이미 워커를 소비 중이므로 DOP 폭주/자원 경합 방지
- **JOIN 타입**: INNER / LEFT OUTER / RIGHT OUTER (build target이 JOIN 타입에 의해 고정됨 — SINGLE과 동일)

## 진입점

- `src/query/query_hash_join.c:610` `hjoin_execute_internal()`
- `c.3130` `hjoin_probe()` — outer 루프: `qfile_scan_list_next(...probe->list_scan_id...)` (c.3188–3319)
- `c.3365` `hjoin_outer_probe()` — LEFT/RIGHT 경로, outer 루프 동일 구조 (c.3427–3655)
- SINGLE 분기 조건: `manager->context_cnt == 0` (c.3192)

## 워커별 복제가 필요한 것

| 대상 | 현재 위치 | 복제 근거 |
|------|----------|----------|
| `HASHJOIN_CONTEXT` | 단일 | `build/probe` 독립 상태 유지 |
| `HASH_LIST_SCAN` | `context->hash_scan` | `curr_hash_key`/`curr_hash_entry` 커서 공유 시 충돌 (c.3214, 3228) |
| `QFILE_LIST_ID` 결과 쓰기 | `hjoin_execute_internal()` c.631에서 단일 open | `qfile_generate_tuple_into_list` 동시 호출 시 페이지 경합 (c.3869) |
| `VAL_DESCR` / `PRED_EXPR` / `REGU_VARIABLE_LIST` | `spawn_manager` 이미 복제 | `src/query/parallel/px_hash_join/px_hash_join_spawn_manager.cpp:51-54` |
| `overflow_record` 버퍼 | `hjoin_probe` 스택(c.3132) | 이미 자동 thread-local |
| `any_record_added` (LEFT OUTER) | `hjoin_outer_probe()` c.3484 스택 변수 | 워커 지역 변수로 자연 분리 |

## 공유해도 되는 것

- **`MHT_HLS_TABLE` 그 자체** — build 완료 후 read-only. `mht_get_hls()`는 쓰기 없음
- **Build 결과 리스트 파일** — read-only 스캔만
- **Outer 입력 `list_id`** — `qfile_scan_list_next`는 페이지 fetch 후 커서가 scan_id(워커별)에 있으므로 입력 분배는 `px_hash_join_task_manager.cpp:551 get_next_page()` 패턴 재사용 가능

## 결과 병합

- 워커 i가 자기 `QFILE_LIST_ID[i]`에 `qfile_add_tuple_to_list` / `qfile_generate_tuple_into_list` 호출
- 최종 단계: `hjoin_merge_qlist()` (c.1829–1941) 또는 `qfile_connect_list()` (`src/query/list_file.c:3129`) 로 순차 연결
- px_heap_scan_result_handler 의 비파티션 병합 패턴(`c.531,550,1153`)과 동형

## 식별된 블로커와 해소

| # | 블로커 | 해소책 |
|---|--------|--------|
| 1 | 공유 `list_id` 쓰기 경합 | 워커별 독립 `list_id` + 최종 `qfile_connect_list` |
| 2 | `HASH_LIST_SCAN` 커서 오염 | 워커별 `hash_scan` 복제(해시 테이블은 공유 참조) |
| 3 | `VAL_DESCR` 내 `DB_VALUE` 동시 갱신 | `spawn_manager`가 이미 워커별 복제 제공 |
| 4 | `er_set()` 전역 에러 스택 | 워커별 `THREAD_ENTRY` 에러 큐 사용 + 대표 에러 선택(첫 실패) |
| 5 | LEFT OUTER `any_record_added` | 워커 지역화로 자연 해결 |
| 6 | RIGHT OUTER unmatched 추적 | 이미 `HASHJOIN_STATUS_FILL_NULL_VALUES` 단계로 분리됨 → probe 병렬 종료 후 순차 실행 유지 |

## 중첩 금지 구현 포인트

- `hjoin_try_partition()` (c.1167) 분기에서 PARALLEL 확정 시 Parallel Probe 플래그 off
- 또는 Parallel Probe 진입 시 선결 조건: `manager->status == HASHJOIN_STATUS_SINGLE && manager->context_cnt == 0 && !in_parallel_query_context`
