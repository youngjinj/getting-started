# Deep Interview Spec: CUBRID 시간 측정 일관성 — Monotonic Clock 통일 (Tier 0~2)

## Metadata
- Interview ID: di-time-consistency-20260402
- Rounds: 4
- Final Ambiguity Score: 11.4%
- Type: brownfield
- Generated: 2026-04-02
- Threshold: 20%
- Status: PASSED

## Clarity Breakdown
| Dimension | Score | Weight | Weighted |
|-----------|-------|--------|----------|
| Goal Clarity | 0.95 | 35% | 0.333 |
| Constraint Clarity | 0.85 | 25% | 0.213 |
| Success Criteria | 0.85 | 25% | 0.213 |
| Context Clarity | 0.85 | 15% | 0.128 |
| **Total Clarity** | | | **0.886** |
| **Ambiguity** | | | **11.4%** |

## Goal

CUBRID 엔진의 경과 시간(elapsed time) 측정에 사용되는 non-monotonic clock을
monotonic clock으로 통일하여, NTP 동기화/수동 시계 변경/VM 마이그레이션 등
외부 요인에 의한 시간 측정 왜곡을 제거한다.

변경 범위는 분석 문서의 Tier 0~2 (9개 파일, ~21줄)이며, static_assert 가드도 추가한다.

## Constraints
- Tier 0~2만 적용 (Tier 3 Broker/CAS는 별도 작업으로 분리)
- 단일 커밋으로 적용
- `steady_clock::duration`과 `system_clock::duration`이 동일 타입(`nanoseconds`)이므로 API/ABI 호환성 유지
- GCC 8의 `condition_variable`은 내부적으로 여전히 `system_clock` 기반 — 이번 변경으로 해결되지 않지만, 향후 GCC 11+/glibc 2.30+ 전환 시 자동 해결
- 기존 코드 스타일(GNU brace style, 2-space indent, 120-char line width) 준수

## Non-Goals
- Broker/CAS의 `gettimeofday` 50곳 변경 (Tier 3)
- `struct timeval` → `struct timespec` 자료형 전환
- `pthread_cond_timedwait` clock 속성 변경
- 시간 측정 API 통합/리팩토링 (기존 중앙화 구조가 이미 적절)
- unit test 실행 또는 기능 테스트 (CI에서 수행)

## Acceptance Criteria
- [ ] 빌드 성공 (`./build.sh -m debug`)
- [ ] `static_assert(cubperf::clock::is_steady)` 컴파일 통과
- [ ] `static_assert(cubmonitor::clock_type::is_steady)` 컴파일 통과
- [ ] 9개 파일의 모든 clock 타입이 monotonic으로 변경됨

## Assumptions Exposed & Resolved
| Assumption | Challenge | Resolution |
|------------|-----------|------------|
| Tier 0~2를 한번에 적용 가능 | 변경 범위가 큰가? | 9개 파일, ~21줄로 매우 작아 단일 커밋이 적절 |
| static_assert를 같이 넣어야 하는가 | 별도 커밋으로 분리? | clock 변경과 동일 목적이므로 함께 포함 |
| 빌드 검증만으로 충분한가 | unit test가 필요하지 않나? | duration 타입이 동일하므로 컴파일 성공이 실질적 검증. unit test는 CI에서 수행 |

## Technical Context

### 변경 대상 파일 및 구체적 변경 내용

#### Tier 0: tsc_timer (1파일, 1곳)
| 파일 | 라인 | 현재 | 변경 후 |
|------|------|------|---------|
| `src/base/tsc_timer.c` | 96 | `CLOCK_REALTIME_COARSE` | `CLOCK_MONOTONIC` |

#### Tier 1: 성능 모니터링 clock 정의 (2파일, 2곳 + static_assert 2곳)
| 파일 | 라인 | 현재 | 변경 후 |
|------|------|------|---------|
| `src/base/perf_def.hpp` | 39 | `std::chrono::high_resolution_clock` | `std::chrono::steady_clock` |
| `src/monitor/monitor_definition.hpp` | 36 | `std::chrono::high_resolution_clock` | `std::chrono::steady_clock` |

static_assert 추가:
- `perf_def.hpp`: `static_assert(cubperf::clock::is_steady, "cubperf::clock must be steady (monotonic)");`
- `monitor_definition.hpp`: `static_assert(cubmonitor::clock_type::is_steady, "cubmonitor::clock_type must be steady (monotonic)");`

#### Tier 2: 스레드 인프라 및 커넥션 풀 (6파일, 18곳)
| 파일 | 라인 | 변경 내용 |
|------|------|----------|
| `src/thread/thread_waiter.hpp` | 65, 67 | `system_clock` → `steady_clock` |
| `src/thread/thread_waiter.cpp` | 201, 227 | `system_clock` → `steady_clock` |
| `src/thread/thread_looper.hpp` | 40, 155 | `system_clock` → `steady_clock` |
| `src/thread/thread_looper.cpp` | 141, 143, 161 | `system_clock` → `steady_clock` |
| `src/thread/thread_entry.cpp` | 466 | typedef `system_clock` → `steady_clock` (7곳 자동 적용) |
| `src/thread/thread_worker_pool.cpp` | 157, 176 | `system_clock` → `steady_clock` |
| `src/connection/connection_pool.cpp` | 316, 334, 337, 390, 405, 408 | `system_clock` → `steady_clock` |

### 검증 방법
1. `./build.sh -m debug` 빌드 성공 확인
2. static_assert 컴파일 통과 확인 (빌드에 포함)

## Ontology (Key Entities)

| Entity | Type | Fields | Relationships |
|--------|------|--------|---------------|
| tsc_timer | core, C time source | CLOCK_REALTIME_COARSE, tsc_getticks, tsc_elapsed_time_usec | 13개 파일에서 호출 |
| cubperf::clock | core, C++ perf stats | high_resolution_clock → steady_clock, perf_def.hpp | daemon, recovery, worker_pool 통계 |
| cubmonitor::clock_type | core, C++ monitor | high_resolution_clock → steady_clock, monitor_definition.hpp | lockfree_hashmap autotimer |
| thread infrastructure | core, looper/waiter/worker_pool/entry | system_clock → steady_clock, 5 files | daemon sleep, thread wait, slow query tracking |
| connection_pool | supporting, shutdown timeout | system_clock → steady_clock, 1 file | server shutdown deadline |

## Ontology Convergence

| Round | Entity Count | New | Changed | Stable | Stability Ratio |
|-------|-------------|-----|---------|--------|----------------|
| 1 | 5 | 5 | - | - | - |
| 2 | 5 | 0 | 0 | 5 | 100% |
| 3 | 5 | 0 | 0 | 5 | 100% |
| 4 | 5 | 0 | 0 | 5 | 100% |

## Interview Transcript
<details>
<summary>Full Q&A (4 rounds)</summary>

### Round 1
**Q:** 분석 문서의 Tier 0~2 변경사항(9개 파일, ~21줄)을 어떤 방식으로 적용하고 싶으신가요?
**A:** 적용 계획만 먼저 확인
**Ambiguity:** 40.2% (Goal: 0.85, Constraints: 0.40, Criteria: 0.35, Context: 0.75)

### Round 2
**Q:** 분석 문서 9절에서 권장한 static_assert 추가를 이번 적용에 포함할까요?
**A:** 포함
**Ambiguity:** 34.0% (Goal: 0.90, Constraints: 0.55, Criteria: 0.35, Context: 0.80)

### Round 3
**Q:** 적용 후 검증은 어떤 범위까지 수행할 계획인가요?
**A:** 빌드 확인만
**Ambiguity:** 20.8% (Goal: 0.90, Constraints: 0.60, Criteria: 0.80, Context: 0.85)

### Round 4
**Q:** 커밋 전략은 어떻게 하시겠습니까?
**A:** 단일 커밋
**Ambiguity:** 11.4% (Goal: 0.95, Constraints: 0.85, Criteria: 0.85, Context: 0.85)

</details>
