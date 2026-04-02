### Purpose

경과 시간(elapsed time)을 측정하는 코드가 non-monotonic clock(`CLOCK_REALTIME_COARSE`, `system_clock`, `high_resolution_clock`)을 사용하고 있어, NTP 동기화·수동 시계 변경·VM 마이그레이션 등 외부 요인으로 시간이 앞/뒤로 점프하면 경과 시간이 음수이거나 비정상적으로 큰 값이 될 수 있는 문제를 해결합니다.

### Implementation

경과 시간 측정에 사용되는 clock을 monotonic clock으로 통일합니다.

- **Tier 0 — tsc_timer (1파일, 1곳)**
  - `src/base/tsc_timer.c:96` — `CLOCK_REALTIME_COARSE` → `CLOCK_MONOTONIC`

- **Tier 1 — 성능 통계 clock 정의 (2파일, 2곳)**
  - `src/base/perf_def.hpp:39` — `high_resolution_clock` → `steady_clock`
  - `src/monitor/monitor_definition.hpp:36` — `high_resolution_clock` → `steady_clock`
  - `static_assert`로 `is_steady == true` 보장 추가

- **Tier 2 — 스레드 인프라 및 커넥션 풀 (6파일, 18곳)**
  - `thread_waiter.hpp/cpp` — `system_clock` → `steady_clock`
  - `thread_looper.hpp/cpp` — `system_clock` → `steady_clock`
  - `thread_entry.cpp` — typedef 변경으로 7곳 자동 적용
  - `thread_worker_pool.cpp` — `system_clock` → `steady_clock`
  - `connection_pool.cpp` — `system_clock` → `steady_clock`

### Remarks

- Broker/CAS의 `gettimeofday` (14+ 파일, 50+ 곳)는 자료형 전환 등 추가 작업이 필요하여 별도 이슈로 분리합니다.
- GCC 8의 `std::condition_variable`은 내부적으로 `system_clock`(`CLOCK_REALTIME`)을 사용하므로, `wait_for`/`wait_until`의 pthread 레벨 대기는 변경 후에도 NTP 영향을 받을 수 있습니다. 향후 GCC 11+ / glibc 2.30+ 전환 시 자동으로 monotonic 대기가 활성화됩니다.
- `steady_clock::duration`과 `system_clock::duration`은 동일 타입(`nanoseconds`)이므로 API/ABI 호환성이 유지됩니다.
