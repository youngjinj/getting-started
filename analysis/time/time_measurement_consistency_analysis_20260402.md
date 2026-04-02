# CUBRID 시간 측정 일관성 분석

- 작성자: youngjinj
- 분석일: 2026-04-02
- 브랜치: upstream/develop (de17d0d2e)
- 목적: 경과 시간(elapsed time) 측정에 monotonic clock을 일관되게 사용하도록 전수 조사

---

## 요약

### 문제

CUBRID 엔진에서 경과 시간(elapsed time)을 측정하는 코드가 non-monotonic clock을 사용하고 있다.
non-monotonic clock은 NTP 동기화, 수동 시계 변경, VM 마이그레이션 등 외부 요인에 의해
시간이 앞/뒤로 점프할 수 있어 경과 시간이 음수이거나 비정상적으로 큰 값이 될 수 있다.

해당 코드는 테스트 코드가 아니라 **운영 중인 엔진의 성능 통계 수집, 스레드 sleep/wake 제어,
로그 복구 성능 추적, lockfree 해시맵 연산 측정** 등 핵심 경로에서 사용되고 있다.

### 핵심 변경

경과 시간 측정에 사용되는 clock을 monotonic clock으로 통일한다.

| 변경 | 현재 (non-monotonic) | 변경 후 (monotonic) |
|------|---------------------|-------------------|
| C API | `CLOCK_REALTIME_COARSE` | `CLOCK_MONOTONIC` |
| C++ 성능 통계 | `std::chrono::high_resolution_clock` | `std::chrono::steady_clock` |
| C++ 스레드 인프라 | `std::chrono::system_clock` | `std::chrono::steady_clock` |

### 변경 범위

| Tier | 대상 | 파일 수 | 변경 곳 수 | 위험도 |
|------|------|--------|-----------|--------|
| 0 | tsc_timer (C API fallback) | 1 | 1 | 낮음 |
| 1 | 성능 통계 clock 정의 (cubperf, cubmonitor) | 2 | 2 | 낮음 |
| 2 | 스레드 인프라 + 커넥션 풀 (looper, waiter, worker_pool, entry, connection_pool) | 6 | 18 | 낮음 |
| 3 | Broker/CAS gettimeofday (별도 작업 권장) | 14+ | 50+ | 중간~높음 |

### 영향도

**Tier 0~2 (이번 변경 대상, 9개 파일):**

- `cubperf::clock`을 사용하는 **13개 파일**이 재컴파일 필요 (코드 변경은 불필요)
- `cubrid statdump` 성능 통계 출력에 영향 (값이 더 정확해짐)
- 모든 daemon 스레드 (checkpoint, log flush, vacuum 등)의 sleep 주기 계산에 영향
- lockfree 해시맵(트랜잭션 테이블, 세션 관리)의 연산 시간 측정에 영향
- 로그 복구(redo) 성능 추적에 영향
- slow query 추적 시 lock/latch 대기 시간 측정에 영향 (`thread_entry.cpp`)
- 서버 shutdown timeout 계산에 영향 (`connection_pool.cpp`)
- `steady_clock`과 `system_clock`의 `duration` 타입이 동일(`nanoseconds`)하므로 **API/ABI 호환성 유지**
- 실측 결과 해상도/오버헤드 차이 없음 (둘 다 ~20ns)
- **주의**: GCC 8의 `condition_variable`은 내부적으로 `system_clock` 기반이므로,
  `wait_for`/`wait_until`의 pthread 레벨 대기는 변경 후에도 NTP 영향을 받을 수 있음.
  경과 시간 계산(looper, worker_pool, thread_entry, cubperf, cubmonitor)은 즉시 효과가 있으며,
  향후 GCC 11+ / glibc 2.30+ 전환 시 `condition_variable`도 자동으로 monotonic 대기가 활성화됨

**Tier 3 (별도 작업, Broker/CAS):**

- `struct timeval` -> `struct timespec` 자료형 전환 필요
- 경과 시간과 wall clock 이중 용도 분리 필요
- `pthread_cond_timedwait` clock 속성 변경 필요
- 전역 변수 `tran_start_time`/`query_start_time` 리팩토링 필요
- 별도 프로세스이고 coarse metric 용도이므로 실질적 위험은 낮아 별도 작업으로 분리 권장

---

## 1. 배경

`tsc_timer.c`에서 `CLOCK_REALTIME_COARSE` -> `CLOCK_MONOTONIC` 변경을 계기로
코드베이스 전체에서 시간 측정에 사용하는 clock을 전수 조사하였다.

---

## 2. 사전 지식: 컴퓨터에서 "시간"을 읽는 두 가지 방법

프로그램에서 시간을 읽을 때, 근본적으로 다른 두 종류의 시계가 있다.
이 차이를 이해하는 것이 이 문서의 핵심이다.

### 2.1 Wall Clock (벽시계) — "지금 몇 시인가?"

일상에서 벽에 걸린 시계를 보는 것과 같다. "2026년 4월 2일 오후 3시 15분"처럼
실제 날짜와 시각을 알려준다.

- C API: `clock_gettime(CLOCK_REALTIME, ...)` 또는 `gettimeofday()`
- C++ API: `std::chrono::system_clock`
- Unix epoch(1970-01-01 00:00:00 UTC)부터의 초 단위 값을 반환

**특징: 외부 요인에 의해 값이 바뀔 수 있다.**

벽시계는 누군가가 시계 바늘을 앞으로 돌리거나 뒤로 돌릴 수 있는 것처럼,
다음과 같은 상황에서 시간 값이 갑자기 점프한다:

| 상황 | 설명 |
|------|------|
| **NTP 동기화** | 대부분의 서버는 NTP(Network Time Protocol)로 시계를 자동 맞춤. 시계가 많이 어긋나면 한번에 수초~수분을 점프시킴 (step 조정) |
| **관리자 수동 변경** | `date -s "12:05:00"` 같은 명령으로 시계를 앞/뒤로 변경 |
| **VM 마이그레이션** | 가상 머신이 다른 호스트로 이동하면 호스트 시간과 동기화하면서 점프 |
| **윤초(leap second)** | 매우 드물지만 UTC에 1초가 추가/삭제될 때 영향 |

### 2.2 Monotonic Clock (단조 시계) — "시작 이후 얼마나 지났는가?"

스톱워치와 같다. 시작 버튼을 누른 뒤 흐른 시간만 측정한다.
"지금 몇 시인지"는 알 수 없지만, "얼마나 걸렸는지"는 정확히 알 수 있다.

- C API: `clock_gettime(CLOCK_MONOTONIC, ...)`
- C++ API: `std::chrono::steady_clock`
- 시스템 부팅 이후 경과한 시간 (또는 임의의 기준점 이후) 을 반환

**특징: 외부 요인에 절대 영향받지 않는다.**

"monotonic"은 수학 용어로 "단조 증가"를 뜻한다.
NTP가 시계를 바꾸든, 관리자가 `date` 명령을 실행하든, VM이 마이그레이션되든
이 시계는 항상 앞으로만 간다. 절대 뒤로 가거나 점프하지 않는다.

### 2.3 왜 경과 시간 측정에 Wall Clock을 쓰면 안 되는가?

경과 시간 측정의 기본 패턴:
```
start = 현재_시간()
... 작업 수행 ...
end = 현재_시간()
elapsed = end - start    ← 이 값이 정확해야 함
```

**Wall Clock (system_clock, CLOCK_REALTIME) 사용 시:**

```
start = 12:00:00.000  (wall clock)
... 작업 수행 (실제 0.05초 소요) ...
(이 사이에 NTP가 시계를 -2초 조정!)
end   = 11:59:58.050  (wall clock)

elapsed = end - start = -1.95초 (음수!)
```

시계가 뒤로 갔기 때문에, 실제로는 0.05초 걸린 작업이 -1.95초로 측정된다.
반대로 시계가 앞으로 가면, 0.05초가 300초(5분)로 측정될 수도 있다.

**Monotonic Clock (steady_clock, CLOCK_MONOTONIC) 사용 시:**

```
start = 100000.000  (monotonic)
... 작업 수행 (실제 0.05초 소요) ...
(NTP 조정 발생 → monotonic에는 영향 없음)
end   = 100000.050  (monotonic)

elapsed = end - start = 0.050초 (항상 정확!)
```

NTP가 뭘 하든 monotonic clock은 영향받지 않는다.

### 2.4 C API와 C++ API의 대응 관계

| 용도 | C API | C++ API | Monotonic? |
|------|-------|---------|------------|
| 현재 시각 (wall clock) | `clock_gettime(CLOCK_REALTIME)` | `std::chrono::system_clock` | ❌ |
| 경과 시간 측정 | `clock_gettime(CLOCK_MONOTONIC)` | `std::chrono::steady_clock` | ✅ |
| 고해상도 (구현 의존) | — | `std::chrono::high_resolution_clock` | ⚠️ 구현마다 다름 |
| 저해상도 wall clock | `clock_gettime(CLOCK_REALTIME_COARSE)` | — | ❌ |
| 저해상도 monotonic | `clock_gettime(CLOCK_MONOTONIC_COARSE)` | — | ✅ (그러나 해상도 ~1ms) |

### 2.5 high_resolution_clock의 함정

`std::chrono::high_resolution_clock`은 "가장 높은 해상도의 시계"를 의도한 타입이지만,
C++ 표준은 이것이 monotonic인지 아닌지를 **규정하지 않는다**.
구현체(컴파일러/라이브러리)가 자유롭게 결정한다.

**실제 구현:**
- **libstdc++ (GCC)**: `high_resolution_clock` = `system_clock` (non-monotonic)
- **libc++ (Clang)**: `high_resolution_clock` = `steady_clock` (monotonic)
- **MSVC**: `high_resolution_clock` = `steady_clock` (monotonic)

CUBRID는 GCC + libstdc++로 빌드하므로, `high_resolution_clock`은 `system_clock`과 동일하다.
즉, **경과 시간 측정에 사용하면 안 되는 non-monotonic clock**이다.

이 사실은 실측(11.2절)과 GCC 8 libstdc++ 소스(`/usr/include/c++/8/chrono:878`)로 확인하였다:
```
// GCC 8 libstdc++ 소스
using high_resolution_clock = system_clock;

// 실측 결과
high_resolution_clock == system_clock ? YES (= system_clock, non-monotonic!)
high_resolution_clock == steady_clock ? NO
```

### 2.6 COARSE 계열의 해상도 문제

`CLOCK_REALTIME_COARSE`와 `CLOCK_MONOTONIC_COARSE`는 커널의 tick 업데이트 주기에
의존하는 저해상도 시계이다. 호출 오버헤드가 매우 낮지만(~6ns), 해상도가 ~1ms이다.

이것은 "1ms보다 짧은 시간은 전부 0으로 측정된다"는 뜻이다.
마이크로초(us) 단위 경과 시간 측정이 필요한 곳에서는 사용할 수 없다.

| 비교 항목 | COARSE 계열 | 일반 (MONOTONIC/REALTIME) |
|----------|------------|-------------------------|
| 해상도 | ~1ms (1,000,000ns) | 1ns |
| 호출 오버헤드 | ~6ns | ~20ns |
| 1ms 미만 측정 | ❌ 불가능 (항상 0) | ✅ 가능 |
| 적합 용도 | 초 단위 timeout, 빈번한 타임스탬프 | 정밀 경과 시간 측정 |

### 2.7 요약: 용도별 올바른 clock 선택

| 질문 | 올바른 clock | 설명 |
|------|-------------|------|
| **"지금 몇 시야?"** (로그 타임스탬프, 날짜) | `CLOCK_REALTIME` / `system_clock` | 외부 조정 영향 받아도 OK |
| **"얼마나 걸렸어?"** (경과 시간, 성능 측정) | `CLOCK_MONOTONIC` / `steady_clock` | 외부 조정 영향 안 받음 |
| **high_resolution_clock** (GCC에서 system_clock임) | **사용하지 말 것** | `steady_clock`을 직접 사용 |
| **COARSE 계열** (해상도 1ms) | **정밀 측정에는 사용 불가** | 초 단위 timeout 등에만 |

### 2.8 CUBRID에서의 실제 영향

위 개념이 CUBRID 엔진에서 왜 중요한지:

**1. 성능 통계가 왜곡될 수 있다 (cubperf, cubmonitor)**

`cubrid statdump` 명령이 보여주는 성능 통계(page read 시간, lock 대기 시간, redo 시간 등)는
내부적으로 `cubperf::clock::now()`를 사용한다. 이것이 `system_clock`이면:

- NTP step 조정 시 timer 통계가 **음수**이거나 **비정상적으로 큰 값**이 됨
- 성능 분석 시 잘못된 결론을 내릴 수 있음
- 실제 사용처: 스레드 daemon/looper/waiter/worker_pool 통계, 로그 복구 성능 추적, lockfree 해시맵 성능 추적

**2. 스레드 대기 시간이 왜곡될 수 있다 (thread_waiter)**

`thread_waiter::wait_until(system_clock::time_point)`은 내부적으로
`std::condition_variable::wait_until`을 호출한다.
`system_clock` 기준이면 NTP 조정 시:

- 시계가 **앞으로** 가면 -> 대기가 즉시 풀림 (예상보다 빨리 깨어남)
- 시계가 **뒤로** 가면 -> 대기가 늘어남 (예상보다 오래 잠듦)

데이터베이스 서버에서 백그라운드 스레드가 예기치 않게 깨어나거나 멈추면
성능 저하나 예측 불가능한 동작으로 이어질 수 있다.

**3. 스레드 루퍼 주기가 왜곡될 수 있다 (thread_looper)**

`thread_looper`는 "작업 실행 시간을 빼고 남은 시간만큼 sleep"하는 로직이 있다:
```
실행 시간 = now() - 시작 시점
sleep 시간 = 주기 - 실행 시간
```
`system_clock`이면 NTP 조정으로 `실행 시간`이 왜곡되어
sleep 주기가 비정상적으로 길거나 짧아질 수 있다.

**4. 해상도 부족으로 측정 자체가 불가능하다 (CLOCK_REALTIME_COARSE)**

`tsc_timer.c`는 마이크로초(us) 단위 경과 시간을 측정하는 함수인데,
`CLOCK_REALTIME_COARSE`(해상도 1ms)를 사용하면 1ms 미만의 작업이 전부 0으로 측정된다.
page read, lock acquire 같은 빠른 작업의 시간을 아예 측정할 수 없다.

---

## 3. 호출스택 분석: 어디서 어떻게 clock이 사용되는가

이 섹션에서는 변경 대상 clock들이 실제 엔진 동작에서 어떤 경로로 호출되는지를
호출스택 기반으로 추적한다.

### 3.1 cubperf::clock (perf_def.hpp) — 성능 통계 수집

`cubperf::clock`은 CUBRID 엔진의 성능 통계 프레임워크의 기준 시계이다.
`cubrid statdump` 명령으로 조회할 수 있는 각종 timer 통계가 이 clock에 기반한다.

**핵심 함수들 (src/base/perf.hpp):**

| 함수 | 역할 | clock::now() 호출 위치 |
|------|------|----------------------|
| `generic_time()` | 마지막 측정 시점부터 현재까지 경과 시간을 통계에 기록 | perf.hpp:304 |
| `generic_time_and_increment()` | 경과 시간 기록 + 카운터 1 증가 | perf.hpp:351 |
| `reset_timept()` | 측정 시작 시점을 현재로 재설정 | perf.hpp:642 |
| `generic_statset` 생성자 | 통계 셋 생성 시 시작 시점 초기화 | perf.hpp:484 |
| `generic_stat_timer` 생성자 | 타이머 생성 시 시작 시점 초기화 | perf.hpp:536 |

#### 3.1.1 데몬 스레드 루프 통계

CUBRID의 백그라운드 작업(checkpoint, log flush, vacuum 등)은 모두 daemon 스레드로 동작한다.
각 daemon의 매 루프마다 실행 시간과 대기 시간을 cubperf로 측정한다.

```
daemon::loop_without_context()                    [thread_daemon.cpp:204]
  |
  +-- register_stat_start()                       [thread_daemon.cpp:186]
  |     +-- cubperf::reset_timept()               [perf.hpp:642]
  |           +-- clock::now()                    << 루프 시작 시점 기록
  |
  +-- exec_arg->execute()                         << 실제 작업 수행 (checkpoint, vacuum 등)
  |
  +-- register_stat_execute()                     [thread_daemon.cpp:198]
  |     +-- time_and_increment(STAT_LOOP_EXECUTE_COUNT_AND_TIME)
  |           +-- clock::now()                    << 작업 완료 시점, 실행 시간 계산
  |
  +-- pause()                                     [thread_daemon.cpp:102]
  |     +-- m_looper.put_to_sleep()               << 다음 루프까지 대기
  |
  +-- register_stat_pause()                       [thread_daemon.cpp:192]
        +-- time(STAT_LOOP_PAUSE_TIME)
              +-- clock::now()                    << 대기 완료 시점, 대기 시간 계산
```

**측정되는 통계:**
- `STAT_LOOP_EXECUTE_COUNT_AND_TIME`: 루프 실행 횟수 및 소요 시간
- `STAT_LOOP_PAUSE_TIME`: 루프 간 대기 시간

#### 3.1.2 로그 복구 (redo) 성능 추적

데이터베이스 복구 시 redo 로그를 재적용하는 과정에서 각 단계별 소요 시간을 측정한다.

```
Database Recovery Start
  +-- log_recovery_redo_parallel::execute()         [log_recovery_redo_parallel.cpp]
        +-- redo_task::execute()                    [line 221] (워커 스레드)
              |
              +-- pop_jobs()                        << 작업 큐에서 redo job 가져오기
              |
              +-- time_and_increment(PERF_STAT_ID_PARALLEL_POP)
              |     +-- clock::now()                << pop 소요 시간 기록
              |
              +-- for (auto &job : jobs_vec) {
              |     +-- job->execute()              << 실제 redo 수행 (페이지 복구)
              |     |
              |     +-- time_and_increment(PERF_STAT_ID_PARALLEL_EXECUTE)
              |     |     +-- clock::now()          << redo 실행 시간 기록
              |     |
              |     +-- job->retire()               << job 정리
              |     |
              |     +-- time_and_increment(PERF_STAT_ID_PARALLEL_RETIRE)
              |           +-- clock::now()          << 정리 시간 기록
              +-- }
```

**메인 스레드에서 측정되는 통계:**
- `PERF_STAT_ID_FETCH_PAGE`: 디스크에서 페이지 읽기 시간
- `PERF_STAT_ID_READ_LOG`: 로그 레코드 읽기 시간
- `PERF_STAT_ID_REDO_OR_PUSH_DO_SYNC`: 동기 redo 실행 시간
- `PERF_STAT_ID_REDO_OR_PUSH_DO_ASYNC`: 비동기 redo 실행 시간
- `PERF_STAT_ID_WAIT_FOR_PARALLEL`: 병렬 워커 대기 시간

### 3.2 cubmonitor::clock_type (monitor_definition.hpp) — 모니터 통계

`cubmonitor::clock_type`은 모니터링 프레임워크의 기준 시계이다.
RAII 패턴의 `autotimer`로 scope 진입/퇴장 시 자동으로 시간을 측정한다.

**핵심 함수들 (src/monitor/monitor_collect.hpp):**

| 함수 | 역할 | clock_type::now() 호출 위치 |
|------|------|---------------------------|
| `timer::timer()` 생성자 | 타이머 시작 시점 기록 | monitor_collect.hpp:546 |
| `timer::reset()` | 시작 시점 재설정 | monitor_collect.hpp:554 |
| `timer::time()` | 경과 시간 반환 및 시점 갱신 | monitor_collect.hpp:561 |
| `autotimer` 생성자 | scope 진입 시 `reset()` 호출 | monitor_collect.hpp:423 |
| `autotimer` 소멸자 | scope 퇴장 시 `time_and_increment()` 호출 | monitor_collect.hpp:429 |

#### 3.2.1 Lockfree 해시맵 연산별 성능 추적

CUBRID 엔진의 lockfree 해시맵은 트랜잭션 테이블, 세션 관리 등 핵심 자료구조에 사용된다.
모든 find/insert/erase 연산마다 autotimer로 자동 시간 측정한다.

```
hashmap::find()                                     [lockfree_hashmap.hpp:280]
  |
  +-- autotimer stat_autotimer(m_stat_find)         [line 282]
  |     +-- timer::reset()                          [monitor_collect.hpp:552]
  |           +-- clock_type::now()                 << 검색 시작 시점 기록
  |
  +-- (해시 버킷 탐색, 키 비교 등 실제 검색 수행)
  |
  +-- ~autotimer()                                  [scope 종료 시 자동 호출]
        +-- time_and_increment()
              +-- timer::time()                     [monitor_collect.hpp:558]
                    +-- clock_type::now()            << 검색 완료 시점, 소요 시간 기록
```

**동일한 패턴으로 측정되는 연산들:**

| 해시맵 연산 | 통계 변수 | 용도 |
|-----------|----------|------|
| `find()` | `m_stat_find` | 키 검색 시간 |
| `insert()` | `m_stat_insert` | 삽입 시간 |
| `erase()` | `m_stat_erase` | 삭제 시간 |
| `unlock()` | `m_stat_unlock` | 잠금 해제 시간 |
| `clear()` | `m_stat_clear` | 전체 삭제 시간 |
| `freelist_claim()` | `m_stat_claim` | 메모리 할당 시간 |
| `freelist_retire()` | `m_stat_retire` | 메모리 반환 시간 |

### 3.3 system_clock (thread_looper/waiter) — 스레드 sleep/wake 제어

스레드의 sleep 주기를 계산하고, condition_variable로 대기하는 곳에서 사용된다.

#### 3.3.1 thread_looper: 실행 시간을 빼고 남은 시간만큼 sleep

```
daemon::loop_without_context()
  +-- daemon::pause()                               [thread_daemon.cpp:102]
        +-- m_looper.put_to_sleep(m_waiter)         [thread_looper.cpp:119]
              |
              +-- system_clock::now()               [line 141]
              |     execution_time = now() - m_start_execution_time
              |     << "이번 루프에서 작업이 얼마나 걸렸는지" 계산
              |
              +-- wait_time = period - execution_time  [line 148]
              |     << "남은 시간만큼만 sleep"
              |
              +-- waiter.wait_for(wait_time)        [line 152]
              |     +-- std::condition_variable::wait_for(lock, delta, ...)
              |     << 실제 sleep (또는 wakeup 신호로 깨어남)
              |
              +-- m_start_execution_time = system_clock::now()  [line 161]
                    << "다음 실행 시작 시점" 기록
```

**문제점**: `system_clock::now()`로 실행 시간을 계산하면, NTP 조정 시:
- 시계가 앞으로 가면 -> `execution_time`이 비정상적으로 커짐 -> `wait_time`이 음수 -> sleep 건너뜀
- 시계가 뒤로 가면 -> `execution_time`이 음수 -> `wait_time`이 비정상적으로 커짐 -> 오래 sleep

#### 3.3.2 thread_waiter: condition_variable 대기

```
looper::put_to_sleep()
  +-- waiter::wait_for(delta)                       [thread_waiter.cpp:201]
        |
        +-- m_condvar.wait_for(lock, delta, predicate)
        |     << 지정 시간만큼 대기
        |
        +-- run()                                   [thread_waiter.cpp:134]
              +-- time_and_increment(STAT_AWAKEN_COUNT_AND_TIME)
                    +-- clock::now()                << 깨어난 시점, 대기 시간 기록
```

```
(다른 경로)
  +-- waiter::wait_until(timeout_time)              [thread_waiter.cpp:227]
        |
        +-- m_condvar.wait_until(lock, timeout_time, predicate)
              << timeout_time이 system_clock::time_point이면
                 NTP 조정 시 대기 시간이 왜곡됨
```

**측정되는 통계:**
- `STAT_SLEEP_COUNT`: sleep 횟수
- `STAT_TIMEOUT_COUNT`: timeout 발생 횟수
- `STAT_AWAKEN_COUNT_AND_TIME`: 깨어난 횟수 및 대기 시간

**참고: GCC 8 `condition_variable`의 한계**

GCC 8의 `std::condition_variable`은 **모든 대기 함수(`wait_for`, `wait_until`)가 내부적으로
`system_clock`(`CLOCK_REALTIME`)을 사용**한다. GCC 14 이상에서 도입된
`_GLIBCXX_USE_PTHREAD_COND_CLOCKWAIT` 분기가 GCC 8에는 존재하지 않기 때문이다.

```cpp
// /usr/include/c++/8/condition_variable:67
class condition_variable {
    typedef chrono::system_clock  __clock_t;   // 무조건 system_clock, 분기 없음
    // ...
    // wait_for도 내부적으로 system_clock::now()를 사용:
    // return wait_until(__lock, __clock_t::now() + __reltime);  // line 143
```

따라서 `waiter::wait_for`의 파라미터를 `steady_clock::duration`으로 바꿔도
**pthread 레벨에서의 대기는 여전히 `CLOCK_REALTIME` 기반**이다.
그러나 API를 `steady_clock`으로 통일해두면 **향후 GCC 업그레이드(GCC 11+, glibc 2.30+) 시
`condition_variable`이 자동으로 `steady_clock` 기반 대기를 수행**하게 된다.

이번 변경의 핵심 이득은 `condition_variable` 대기가 아니라,
**`looper`/`worker_pool`/`thread_entry`에서 `steady_clock::now()`를 직접 호출하는 경과 시간 계산**에 있다.
이 부분은 `condition_variable`을 거치지 않으므로 GCC 버전과 무관하게 즉시 NTP 영향이 제거된다.

#### 3.3.3 thread_worker_pool: 스레드 중지 timeout

```
worker_pool::stop_execution()                       [thread_worker_pool.cpp:143]
  |
  +-- timeout = system_clock::now() + 60s           [line 157]
  |
  +-- while (true) {
        +-- notify_stop()                           << 모든 워커에 중지 요청
        |
        +-- if (system_clock::now() > timeout)      [line 176]
        |     assert(false); break;                 << 60초 초과 시 timeout
        |
        +-- sleep(10ms)                             << 10ms 간격으로 확인
      }
```

**문제점**: NTP가 시계를 60초 이상 뒤로 돌리면 timeout이 사실상 무한대가 됨.
반대로 앞으로 돌리면 즉시 timeout assert 발생 가능.

### 3.4 호출 빈도 요약

| 모듈 | clock 종류 | 호출 빈도 | 영향도 |
|------|-----------|----------|--------|
| thread_daemon (모든 daemon 루프) | `cubperf::clock` | **매 루프마다 3회** (start, execute, pause) | 높음 |
| lockfree_hashmap (find/insert/erase) | `cubmonitor::clock_type` | **매 연산마다 2회** (start, end) | 높음 |
| log_recovery_redo (복구 시) | `cubperf::clock` | **매 redo job마다 3회** | 중간 (복구 시에만) |
| thread_looper (sleep 주기 계산) | `system_clock` | **매 sleep마다 2회** | 높음 |
| thread_waiter (대기/깨움) | `system_clock` + `cubperf::clock` | **매 wait/wakeup마다** | 높음 |
| thread_worker_pool (중지 시) | `system_clock` | **중지 시에만** | 낮음 |
| thread_entry (lock/latch 대기 측정) | `system_clock` | **slow query 추적 시 매 대기마다 2회** | 중간 |
| connection_pool (shutdown timeout) | `system_clock` | **종료 시에만 2회** | 낮음 |

---

## 4. clock_gettime 사용 현황

### 4.1 경과 시간 측정 (elapsed time)

| 파일 | clock 종류 | 상태 |
|------|-----------|------|
| `src/base/tsc_timer.c:96` | `CLOCK_REALTIME_COARSE` | **변경 필요** -> `CLOCK_MONOTONIC` |
| `src/executables/unload_object_file.h:67` | `CLOCK_MONOTONIC` | ✅ 이미 올바름 |
| `src/executables/unload_object_file.c:1141` | `CLOCK_MONOTONIC` | ✅ 이미 올바름 |
| `src/base/cycle.h:451` | `CLOCK_SGI_CYCLE` | ✅ SGI/Irix 전용 (Linux x86-64에서는 컴파일 안됨, `rdtsc` 사용) |

### 4.2 Wall clock (현재 시각 표시 용도) — 변경 불필요

| 파일 | clock 종류 | 용도 |
|------|-----------|------|
| `src/broker/cas.c:1864` | `CLOCK_REALTIME` | 쿼리 취소 시각 기록 (wall clock) |
| `src/executables/unload_object_file.c:1176` | `CLOCK_REALTIME` | 로그 메시지 타임스탬프 |

---

## 5. std::chrono 사용 현황

### 5.1 변경 필요 — high_resolution_clock (= system_clock)

libstdc++에서 `std::chrono::high_resolution_clock`은 `system_clock`의 typedef이다.
즉, monotonic이 아니며 경과 시간 측정에 부적합하다.

| 파일:라인 | 현재 코드 | 용도 |
|----------|----------|------|
| `src/base/perf_def.hpp:39` | `using clock = std::chrono::high_resolution_clock;` | `cubperf` 성능 통계 전체의 기준 clock |
| `src/monitor/monitor_definition.hpp:36` | `using clock_type = std::chrono::high_resolution_clock;` | `cubmonitor` 모니터링 전체의 기준 clock |

**영향 범위**: `perf_def.hpp`/`perf.hpp`를 직접 include하는 **13개 파일**이 재컴파일 필요.
코드 변경은 위 2곳만 하면 되고, 나머지는 재컴파일만으로 충분하다.

`cubperf::clock::now()` 실제 호출처 (8곳):
- `src/base/perf.hpp` — 5곳 (`generic_time`, `generic_time_and_increment`, `reset_timept`, 생성자 2곳)
- `src/thread/thread_worker_pool.hpp` — 1곳 (`set_push_time_now`)
- `src/thread/thread_worker_pool.cpp` — 2곳 (`init_pool_and_workers`, `execute_task`)

`cubmonitor::clock_type::now()` 실제 호출처 (3곳):
- `src/monitor/monitor_collect.hpp` — 3곳 (`timer` 생성자, `reset`, `time`)
- `autotimer`를 사용하는 파일: `src/base/lockfree_hashmap.hpp`, `src/monitor/monitor_collect.hpp`

**권장 변경**:
```cpp
// perf_def.hpp:39
using clock = std::chrono::steady_clock;

// monitor_definition.hpp:36
using clock_type = std::chrono::steady_clock;
```

### 5.2 변경 필요 — system_clock을 경과 시간 측정에 사용

| 파일:라인 | 현재 코드 | 용도 |
|----------|----------|------|
| `src/thread/thread_waiter.hpp:65` | `wait_for(const system_clock::duration &delta)` | 스레드 대기 (duration) |
| `src/thread/thread_waiter.hpp:67` | `wait_until(const system_clock::time_point &timeout_time)` | 스레드 대기 (time_point) |
| `src/thread/thread_waiter.cpp:201` | `wait_for` 구현부 | 위와 동일 |
| `src/thread/thread_waiter.cpp:227` | `wait_until` 구현부 | 위와 동일 |
| `src/thread/thread_looper.hpp:40` | `typedef system_clock::duration delta_time;` | looper 주기 타입 |
| `src/thread/thread_looper.hpp:155` | `system_clock::time_point m_start_execution_time;` | 실행 시작 시점 |
| `src/thread/thread_looper.cpp:141` | `system_clock::time_point()` 비교 | 실행 시간 계산 |
| `src/thread/thread_looper.cpp:143` | `system_clock::now() - m_start_execution_time` | 실행 시간 계산 |
| `src/thread/thread_looper.cpp:161` | `system_clock::now()` | 실행 시작 시점 기록 |
| `src/thread/thread_entry.cpp:466` | `using thread_clock_type = system_clock;` | legacy C 함수용 clock 타입 (이 typedef를 통해 7곳에서 사용) |
| `src/thread/thread_entry.cpp:501,513,520` | `thread_clock_type::now()` | lock 대기 경과 시간 측정 (`lock_waits` 통계) |
| `src/thread/thread_entry.cpp:550,563,570` | `thread_clock_type::now()` | latch 대기 경과 시간 측정 (`latch_waits` 통계) |
| `src/thread/thread_worker_pool.cpp:157` | `system_clock::now() + time_wait_to_thread_stop` | 스레드 중지 timeout |
| `src/thread/thread_worker_pool.cpp:176` | `system_clock::now() > timeout` | timeout 체크 |
| `src/connection/connection_pool.cpp:316,334,337` | `system_clock::time_point deadline, now;` | shutdown timeout deadline 계산 |
| `src/connection/connection_pool.cpp:390,405,408` | 동일 패턴 | coordinator 종료 대기 |

**참고**: `thread_entry.cpp`는 typedef 1곳(line 466)만 `steady_clock`으로 바꾸면
나머지 6곳(line 501, 513, 520, 550, 563, 570)이 자동으로 따라간다.
slow query 추적 활성화 시 lock/latch 대기 시간 측정에 사용되는 경로이다.

**참고**: `connection_pool.cpp`는 `system_clock`으로 deadline을 계산한 뒤 duration으로 변환하여
`cv.wait_for`에 전달한다. `wait_for`가 duration 기반이므로 대기 자체의 위험도는 낮으나,
deadline 계산 시 NTP 영향을 받을 수 있어 `steady_clock`으로의 변경이 권장된다.

**권장 변경**: 모두 `system_clock` → `steady_clock`

### 5.3 이미 올바른 사용 — 변경 불필요

| 파일 | clock 종류 | 용도 |
|------|-----------|------|
| `src/executables/master_server_monitor.hpp` | `steady_clock` | 프로세스 revive 시간 추적 |
| `src/executables/master_server_monitor.cpp:114,165` | `steady_clock` | revive 시점 기록/조회 |
| `src/connection/connection_worker.cpp:499,508,1727,1736` | `steady_clock` | 연결 워커 경과 시간 측정 |
| `src/sp/jsp_cl.cpp:1213` | `system_clock` | PL/CSQL 컴파일 타임스탬프 (`to_time_t` → `localtime` → 날짜 포맷팅, wall clock 용도) |

---

## 6. gettimeofday 사용 현황

### 6.1 개요
- **50개 파일**, **159곳**에서 `gettimeofday` 사용
- 경과 시간 측정과 wall clock 용도가 혼재

### 6.2 경과 시간 측정에 사용하는 주요 파일 (broker/CAS)

| 파일 | 주요 용도 | 호출 수 |
|------|----------|--------|
| `src/broker/cas_function.c` | 트랜잭션/쿼리 실행 시간 | ~17곳 |
| `src/broker/cas_runner.c` | prepare/execute/commit 시간 | ~6곳 |
| `src/broker/cas.c` | 트랜잭션/쿼리 시작 시간 | ~6곳 |
| `src/broker/cas_execute.c` | 트랜잭션/쿼리 시작 시간 | ~2곳 |
| `src/broker/broker_log_replay.c` | 쿼리 실행 시간 | ~4곳 |
| `src/broker/broker_tester.c` | 경과 시간 | ~2곳 |
| `src/broker/ddl_log.c` | DDL 실행 시간 | ~5곳 |
| `src/broker/shard_proxy_io.c` | 클라이언트 시작 시간 | ~1곳 |

### 6.3 Wall clock 용도 (변경 불필요)

| 파일 | 용도 |
|------|------|
| `src/base/error_manager.c` | 에러 메시지 타임스탬프 |
| `src/base/event_log.c` | 이벤트 로그 타임스탬프 |
| `src/executables/cubrid_log.c` | 로그 타임스탬프 |
| `src/broker/cas_sql_log2.c` | SQL 로그 타임스탬프 |
| `src/broker/broker.c` | 디버그 로그 타임스탬프 |
| `src/base/util_func.c` | `srand48_r` 시드 (랜덤) |

### 6.4 Broker/CAS 상세 분석: gettimeofday 호출별 분류

Broker/CAS의 `gettimeofday` 50곳을 용도별로 분류하면 아래와 같다.

#### A. 경과 시간 측정 (30곳) — 변경 대상

start/end 쌍으로 사용되며, `ut_timeval_diff()` 또는 `ut_diff_time()`으로 차이를 계산한다.

| 파일 | 라인 | 변수 | 패턴 | 용도 |
|------|------|------|------|------|
| `cas_function.c` | 189, 199 | `end_tran_begin/end` | start->end->diff | end_tran 소요 시간 |
| `cas_function.c` | 719, 724 | `exec_begin/end` | start->end->diff | execute 소요 시간 |
| `cas_function.c` | 2629, 2633 | `lob_new_begin/end` | start->end->diff | LOB new 소요 시간 |
| `cas_function.c` | 2670, 2674 | (동일 변수 재사용) | start->end->diff | LOB write 소요 시간 |
| `cas_function.c` | 2711, 2715 | (동일 변수 재사용) | start->end->diff | LOB read 소요 시간 |
| `cas_runner.c` | 799, 801 | `begin/end` | start->end->diff | prepare 소요 시간 |
| `cas_runner.c` | 1200, 1202 | `begin/end` | start->end->diff | execute 소요 시간 |
| `cas_runner.c` | 1266, 1268 | `begin/end` | start->end->diff | commit 소요 시간 |
| `broker_log_replay.c` | 191, 367 | `begin/end` | start->end->diff | 전체 프로그램 실행 시간 |
| `broker_log_replay.c` | 893, 905 | `begin/end` | start->end->diff | 개별 쿼리 실행 시간 |
| `broker_tester.c` | 374, 334 | `start_time/end_time` | start->end->diff | 테스트 쿼리 실행 시간 |
| `ddl_log.c` | 1095 | `exec_end` | start->end->diff | DDL 실행 시간 (`logddl_timeval_diff`) |
| `cas_log.c` | 940 | `end_time` | start->end->diff+format | 접속 세션 시간 (이중 용도) |
| `shard_proxy_log.c` | 289 | `end_time` | start->end->diff+format | 프록시 세션 시간 (이중 용도) |

**핵심 diff 함수들:**
- `ut_timeval_diff(start, end, &sec, &msec)` — `cas_util.c:69`: sec/msec 분리 반환
- `ut_diff_time(begin, end)` — `broker_log_util.c:466`: double 초 반환
- `ut_check_timeout(start, end, timeout_msec, &sec, &msec)` — `cas_util.c:87`: timeout 판정 + diff
- `logddl_timeval_diff(start, end)` — `ddl_log.c:1480`: DDL 로그용 diff

#### B. Wall clock 타임스탬프 (12곳) — 변경 불필요

단일 호출로 현재 시각을 가져와 timeout 관리, 로그 시작 시각 기록 등에 사용한다.

| 파일 | 라인 | 변수 | 용도 |
|------|------|------|------|
| `cas.c` | 728-729 | `tran_start_time`, `query_start_time` | 트랜잭션/쿼리 시작 시각 (전역) |
| `cas.c` | 1440-1442 | (동일 전역 변수) | 트랜잭션 시작 시각 재설정 |
| `cas.c` | 2541-2542 | (동일 전역 변수) | 트랜잭션 시작 시각 재설정 |
| `cas.c` | 2679-2681 | (동일 전역 변수) | 트랜잭션 시작 시각 재설정 |
| `cas.c` | 617 | `cas_start_time` (지역) | CAS 프로세스 시작 시각 |
| `cas.c` | 1126 | `cas_start_time` (지역) | 접속 세션 시작 시각 |
| `cas_function.c` | 244-245 | `tran_start_time`, `query_start_time` | timeout 리셋 |
| `cas_function.c` | 372 | `query_start_time` | 쿼리 시작 시각 |
| `cas_function.c` | 662 | `query_start_time` | 쿼리 시작 시각 |
| `cas_function.c` | 1769, 1819 | (기타) | timeout 관련 |
| `cas_execute.c` | 11038-11039 | `tran_start_time`, `query_start_time` | 트랜잭션 완료 후 리셋 |
| `ddl_log.c` | 480 | `qry_exec_begin_time` | DDL 시작 시각 |

**참고**: `tran_start_time`/`query_start_time`은 전역 변수(`cas.c:156-157`)이며,
`ut_check_timeout()`에서 경과 시간 계산에도 사용되지만 (A와 겹침),
본질적으로 "트랜잭션이 시작된 시각"을 기록하는 wall clock 역할이다.
이 값은 `logddl_set_start_time()`에 전달되어 DDL 감사 로그에도 기록된다.

**공유 메모리 노출**: `struct timeval` 자체는 공유 메모리에 쓰이지 않는다.
공유 메모리에는 `time_t transaction_start_time` (초 단위)과
`num_long_queries`/`num_long_transactions` (카운터)만 저장된다.

#### C. 이중 용도 (5곳) — 가장 변경이 까다로운 부분

경과 시간 계산과 wall clock 포맷팅을 동시에 하는 곳이다.

| 파일 | 라인 | 용도 |
|------|------|------|
| `cas_log.c` | 940 | `end_time`으로 경과 시간 계산 + `localtime_r()`로 시각 포맷팅 |
| `shard_proxy_log.c` | 289 | 동일 (프록시 접속 로그) |
| `broker.c` | 1190 | `gettimeofday` -> `timespec` 변환 -> `pthread_cond_timedwait` 절대 시각 |

`cas_log.c`와 `shard_proxy_log.c`의 접속 로그 함수는 다음 두 가지를 동시에 수행한다:
1. `start_time`, `end_time`을 `localtime_r()`로 변환하여 "시작 시각 ~ 종료 시각" 포맷 출력
2. `end_time - start_time`으로 경과 시간 계산

이 경우 monotonic으로 바꾸면 `localtime_r()`에 전달할 wall clock이 없어지므로,
경과 시간용과 타임스탬프용을 분리해야 한다.

#### D. 디버그/기타 (3곳) — 변경 불필요

| 파일 | 라인 | 용도 |
|------|------|------|
| `broker.c` | 121, 130, 145 | 디버그 매크로 (`BROKER_DEBUG` 플래그 시에만 컴파일) |
| `shard_proxy_function.c` | 3750 | 클라이언트 연결 시각 기록 |
| `shard_proxy_io.c` | 1641 | 클라이언트 요청 시각 기록 |

### 6.5 Broker/CAS 변경을 별도 작업으로 분리하는 이유

단순히 `gettimeofday` -> `clock_gettime(CLOCK_MONOTONIC)`으로 바꾸는 것이 아니라,
아래와 같은 추가 작업이 필요하기 때문에 별도 작업으로 분리하는 것을 권장한다.

#### 이유 1: 자료형 전환 필요

`gettimeofday`는 `struct timeval` (초 + 마이크로초),
`clock_gettime`은 `struct timespec` (초 + 나노초)를 사용한다.

```c
struct timeval  { time_t tv_sec; suseconds_t tv_usec; };  // us 단위
struct timespec { time_t tv_sec; long tv_nsec; };         // ns 단위
```

`struct timeval`을 사용하는 모든 변수, 함수 파라미터, diff 함수를 `struct timespec`으로 변경하거나
wrapper를 만들어야 한다. 영향 범위:

| 변경 필요 항목 | 수량 |
|---------------|------|
| `struct timeval` 변수 선언 | ~30곳 |
| `ut_timeval_diff()` 호출 | ~10곳 |
| `ut_diff_time()` 호출 | ~5곳 |
| `ut_check_timeout()` 호출 + 내부 구현 | 4곳 + 1곳 |
| `logddl_timeval_diff()` 호출 + 내부 구현 | 1곳 + 1곳 |
| 함수 시그니처에 `struct timeval *` 파라미터 | ~10곳 |

#### 이유 2: 이중 용도 분리 필요

`cas_log.c:cas_access_log_write()`와 `shard_proxy_log.c:proxy_access_log_write()`는
하나의 `gettimeofday` 값으로 경과 시간 + 시각 포맷팅을 동시에 한다.
monotonic으로 바꾸면 wall clock이 없어지므로, 다음과 같이 분리해야 한다:

```c
// 변경 전 (하나의 gettimeofday로 두 가지 용도)
gettimeofday(&end_time, NULL);
elapsed_sec = end_time.tv_sec - start_time->tv_sec;     // 경과 시간
localtime_r(&end_time.tv_sec, &ct2);                    // 시각 포맷팅

// 변경 후 (두 종류의 clock 호출)
clock_gettime(CLOCK_MONOTONIC, &end_mono);               // 경과 시간용
clock_gettime(CLOCK_REALTIME, &end_real);                // 시각 포맷팅용
// 또는 gettimeofday(&end_real, NULL);
```

#### 이유 3: pthread_cond_timedwait 변경 필요

`broker.c:1190`에서 `gettimeofday`를 `timespec`으로 변환하여
`pthread_cond_timedwait`에 절대 시각으로 전달한다.
이것을 monotonic으로 바꾸려면 condition variable의 clock 속성도 변경해야 한다:

```c
// 변경 전
pthread_cond_init(&clt_table_cond, NULL);  // 기본 = CLOCK_REALTIME
gettimeofday(&tv, NULL);
ts.tv_sec = tv.tv_sec; ts.tv_nsec = (tv.tv_usec + 30000) * 1000;
pthread_cond_timedwait(&clt_table_cond, &mutex, &ts);

// 변경 후
pthread_condattr_t attr;
pthread_condattr_init(&attr);
pthread_condattr_setclock(&attr, CLOCK_MONOTONIC);       // monotonic 설정
pthread_cond_init(&clt_table_cond, &attr);
pthread_condattr_destroy(&attr);

clock_gettime(CLOCK_MONOTONIC, &ts);
ts.tv_nsec += 30000000;  // +30ms
if (ts.tv_nsec >= 1000000000) { ts.tv_sec++; ts.tv_nsec -= 1000000000; }
pthread_cond_timedwait(&clt_table_cond, &mutex, &ts);
```

#### 이유 4: 전역 변수 `tran_start_time`/`query_start_time`의 이중 역할

이 전역 변수들은:
1. `ut_check_timeout()`의 시작 시점으로 사용 (경과 시간)
2. `logddl_set_start_time()`에 전달되어 DDL 감사 로그에 기록 (wall clock)
3. `cas_slow_log_write()`에서 슬로우 쿼리 로그의 시작 시각으로 출력

monotonic으로 바꾸면 2, 3번 용도에서 시각 정보가 사라진다.
따라서 이 변수를 두 개로 분리하거나 (monotonic용 + wall clock용),
timeout 체크 시점에만 별도로 monotonic 시간을 읽어야 한다.

### 6.6 Broker/CAS를 변경한다면: 단계별 접근

만약 변경을 진행한다면 다음 순서를 권장한다.

#### Phase 1: 인프라 준비 (cas_util.c/h)

새로운 monotonic 시간 함수와 diff 함수를 추가한다.
기존 함수는 그대로 두고, 새 함수를 병행 사용할 수 있게 한다.

```c
// cas_util.c에 추가할 함수들

// monotonic 시간 읽기
void ut_get_monotonic_time(struct timespec *ts) {
    clock_gettime(CLOCK_MONOTONIC, ts);
}

// timespec 차이 계산 (sec + msec 반환)
void ut_timespec_diff(struct timespec *start, struct timespec *end,
                      int *res_sec, int *res_msec) {
    int sec = end->tv_sec - start->tv_sec;
    int msec = (end->tv_nsec / 1000000) - (start->tv_nsec / 1000000);
    if (msec < 0) { msec += 1000; sec--; }
    *res_sec = sec;  *res_msec = msec;
}

// timespec 차이 계산 (double 초 반환)
double ut_timespec_diff_time(struct timespec *start, struct timespec *end) {
    return (end->tv_sec - start->tv_sec)
         + (end->tv_nsec - start->tv_nsec) / 1000000000.0;
}

// monotonic timeout 체크
int ut_check_timeout_monotonic(struct timespec *start_time,
                               struct timespec *end_time,
                               int timeout_msec,
                               int *res_sec, int *res_msec) {
    struct timespec cur_time;
    if (end_time == NULL) {
        end_time = &cur_time;
        clock_gettime(CLOCK_MONOTONIC, end_time);
    }
    ut_timespec_diff(start_time, end_time, res_sec, res_msec);
    if (timeout_msec > 0) {
        int diff_msec = *res_sec * 1000 + *res_msec;
        return (diff_msec >= timeout_msec) ? diff_msec : -1;
    }
    return -1;
}
```

#### Phase 2: 순수 경과 시간 측정만 하는 곳부터 전환

변경이 가장 쉬운 곳 — 결과가 diff 계산에만 쓰이고, wall clock으로 사용되지 않는 곳.

| 우선순위 | 파일 | 이유 |
|---------|------|------|
| 1 | `cas_runner.c` | 테스트/벤치마크 도구, 프로덕션 영향 없음 |
| 2 | `broker_log_replay.c` | 로그 리플레이 도구, 프로덕션 영향 없음 |
| 3 | `broker_tester.c` | 테스트 도구, 프로덕션 영향 없음 |
| 4 | `cas_function.c` (LOB 함수들) | 단순 start/end/diff 패턴, 이중 용도 없음 |
| 5 | `cas_function.c` (execute/end_tran) | 이중 용도 있어 주의 필요 |

#### Phase 3: 이중 용도 분리

`cas_log.c`, `shard_proxy_log.c`의 접속 로그 함수에서
경과 시간과 시각 포맷팅을 분리한다.

#### Phase 4: 전역 변수 리팩토링

`tran_start_time`/`query_start_time`을 monotonic + wall clock 쌍으로 분리하거나,
timeout 체크 전용 monotonic 변수를 별도로 추가한다.

#### Phase 5: pthread 변경

`broker.c`의 `pthread_cond_timedwait`에 `CLOCK_MONOTONIC` 속성을 적용한다.

---

## 7. TSC (Time Stamp Counter) 관련

### 7.1 tsc_timer.c/h
- `power_Savings == 0`이면 `rdtsc` 명령어로 직접 TSC 읽음 (`cycle.h` 경유)
- `power_Savings != 0`이면 fallback으로 `clock_gettime(CLOCK_REALTIME_COARSE)` 사용 <- `CLOCK_MONOTONIC`으로 변경 필요
- Windows fallback: `gettimeofday` (Windows에서는 `QueryPerformanceCounter` 기반이므로 monotonic)

### 7.2 cycle.h
- FFTW 프로젝트에서 가져온 멀티 플랫폼 TSC 읽기 구현
- x86-64: `rdtsc` inline assembly
- 기타: PowerPC, IA64, SPARC, S390 등 지원
- 변경 불필요

---

## 8. 변경 대상 파일 요약

### Tier 0: tsc_timer (1개 파일, 1곳)
- [ ] `src/base/tsc_timer.c:96` — `CLOCK_REALTIME_COARSE` -> `CLOCK_MONOTONIC`

### Tier 1: 성능 모니터링 clock (2개 파일, 2곳)
- [ ] `src/base/perf_def.hpp:39` — `high_resolution_clock` → `steady_clock`
- [ ] `src/monitor/monitor_definition.hpp:36` — `high_resolution_clock` → `steady_clock`

### Tier 2: 스레드 인프라 및 커넥션 풀 (6개 파일, 18곳)
- [ ] `src/thread/thread_waiter.hpp:65,67` — `system_clock` → `steady_clock`
- [ ] `src/thread/thread_waiter.cpp:201,227` — `system_clock` → `steady_clock`
- [ ] `src/thread/thread_looper.hpp:40,155` — `system_clock` → `steady_clock`
- [ ] `src/thread/thread_looper.cpp:141,143,161` — `system_clock` → `steady_clock`
- [ ] `src/thread/thread_entry.cpp:466` — `system_clock` → `steady_clock` (typedef 변경으로 7곳 자동 적용)
- [ ] `src/thread/thread_worker_pool.cpp:157,176` — `system_clock` → `steady_clock`
- [ ] `src/connection/connection_pool.cpp:316,334,337,390,405,408` — `system_clock` → `steady_clock` (shutdown timeout)

### Tier 3: Broker/CAS gettimeofday — 이번 제외
- 50개 파일, 159곳 — 별도 작업으로 분리 권장

---

## 9. 검증 방법

1. **빌드 확인**: `steady_clock`과 `system_clock`의 `duration` 타입이 동일(`nanoseconds`)하므로 컴파일 에러 없을 것
2. **static_assert 추가** (권장):
   ```cpp
   // perf_def.hpp — cubperf::clock 정의 뒤에 추가
   static_assert(cubperf::clock::is_steady, "cubperf::clock must be steady (monotonic)");

   // monitor_definition.hpp — cubmonitor::clock_type 정의 뒤에 추가
   static_assert(cubmonitor::clock_type::is_steady, "cubmonitor::clock_type must be steady (monotonic)");
   ```
3. **unit test**: `unit_tests/thread/`, `unit_tests/lockfree/` 실행
4. **기능 테스트**: `cubrid statdump`로 성능 통계 정상 출력 확인
5. **thread_entry.cpp lock/latch waits 검증**: slow query 추적 활성화 상태에서 `lock_waits`/`latch_waits` 통계 정상 수집 확인
6. **regression test**: 전체 회귀 테스트
7. **빌드 환경 확인**: `_GLIBCXX_USE_PTHREAD_COND_CLOCKWAIT` 정의 여부 확인. 현재 GCC 8(glibc 2.28)에서는 미지원. EL9(glibc 2.34) 이상 전환 시 `condition_variable`의 monotonic 대기가 자동 활성화됨

---

## 10. 참고: clock 종류별 특성

| Clock | Monotonic | 해상도 | NTP 영향 | 용도 |
|-------|-----------|--------|---------|------|
| `CLOCK_MONOTONIC` | ✅ | ns | ❌ | 경과 시간 측정 |
| `CLOCK_REALTIME` | ❌ | ns | ✅ | wall clock (현재 시각) |
| `CLOCK_REALTIME_COARSE` | ❌ | ~1-4ms | ✅ | 빠르지만 저해상도 wall clock |
| `CLOCK_MONOTONIC_COARSE` | ✅ | ~1-4ms | ❌ | 빠르지만 저해상도 경과 시간 |
| `steady_clock` | ✅ | ns | ❌ | C++ 경과 시간 측정 |
| `system_clock` | ❌ | ns | ✅ | C++ wall clock |
| `high_resolution_clock` | 구현 의존 | ns | 구현 의존 | libstdc++에서는 `system_clock` alias |

---

## 11. 실측 결과: 왜 변경해야 하는가

### 테스트 환경
- OS: Linux 6.9.4-1.el8.elrepo.x86_64
- 테스트 코드: `test_clock_resolution.c`, `test_chrono_clock.cpp`

### 11.1 CLOCK_REALTIME_COARSE vs CLOCK_MONOTONIC — 해상도 문제

**시스템 보고 해상도 (clock_getres):**

| Clock | 해상도 |
|-------|--------|
| `CLOCK_REALTIME_COARSE` | **1,000,000 ns (1ms)** |
| `CLOCK_MONOTONIC_COARSE` | **1,000,000 ns (1ms)** |
| `CLOCK_REALTIME` | 1 ns |
| `CLOCK_MONOTONIC` | 1 ns |

**실제 해상도 측정 (연속 2회 호출 간 시간 차이):**

| Clock | 0ns 비율 | 최소 차이 | 평균 차이 |
|-------|---------|----------|----------|
| `CLOCK_REALTIME_COARSE` | **100/100 (100%)** | 0 ns | 0.0 ns |
| `CLOCK_MONOTONIC_COARSE` | **100/100 (100%)** | 0 ns | 0.0 ns |
| `CLOCK_REALTIME` | 0/100 (0%) | 20 ns | 20.3 ns |
| `CLOCK_MONOTONIC` | 0/100 (0%) | 20 ns | 20.6 ns |

`COARSE` 계열은 해상도가 1ms이므로, 연속 호출 시 항상 동일한 값을 반환한다.
1ms 미만의 경과 시간은 **모두 0으로 측정**된다.

**짧은 작업 측정 비교 (volatile 덧셈 10회):**

| Clock | 측정 결과 |
|-------|----------|
| `CLOCK_REALTIME_COARSE` | **10/10 모두 0ns** — 측정 불가 |
| `CLOCK_MONOTONIC` | 31~40 ns — 정상 측정 |

```
CLOCK_REALTIME_COARSE:
  [ 0] elapsed =      0 ns  <-- 0ns! 측정 불가
  [ 1] elapsed =      0 ns  <-- 0ns! 측정 불가
  ...전부 0ns

CLOCK_MONOTONIC:
  [ 0] elapsed =     40 ns
  [ 1] elapsed =     38 ns
  [ 2] elapsed =     34 ns
  ...정상 측정
```

**결론**: `CLOCK_REALTIME_COARSE`는 1ms 미만의 작업을 측정할 수 없다.
`tsc_timer.c`의 fallback 경로는 마이크로초 단위 경과 시간 측정 함수(`tsc_elapsed_time_usec`)에서
사용되므로, `CLOCK_MONOTONIC`으로 변경해야 한다.

**호출 오버헤드:**

| Clock | 호출당 평균 |
|-------|-----------|
| `CLOCK_REALTIME_COARSE` | 6.2 ns |
| `CLOCK_MONOTONIC_COARSE` | 6.2 ns |
| `CLOCK_REALTIME` | 20.5 ns |
| `CLOCK_MONOTONIC` | 20.5 ns |

`COARSE`는 호출당 ~6ns, `MONOTONIC`은 ~20ns로 약 3배 차이가 있지만,
20ns의 오버헤드는 DB 작업(us~ms 단위) 대비 무시할 수 있는 수준이다.
반면 1ms 해상도의 COARSE로는 의미 있는 경과 시간 측정이 불가능하다.

### 11.2 high_resolution_clock = system_clock 문제 (실측 확인)

```
=== Clock 특성 (is_steady) ===
  system_clock                   : is_steady = FALSE (non-monotonic!)
  steady_clock                   : is_steady = true (monotonic)
  high_resolution_clock          : is_steady = FALSE (non-monotonic!)

=== high_resolution_clock 정체 확인 ===
  high_resolution_clock == system_clock ? YES (= system_clock, non-monotonic!)
  high_resolution_clock == steady_clock ? NO
```

이 시스템의 libstdc++에서 `high_resolution_clock`은 `system_clock`의 alias이다.
`is_steady = false`이므로 monotonic이 아니며, NTP step 조정 시 경과 시간이 왜곡될 수 있다.

현재 `cubperf::clock`과 `cubmonitor::clock_type`이 `high_resolution_clock`을 사용하고 있으므로,
성능 통계 수집 전체가 non-monotonic clock에 의존하고 있다.

**해상도와 오버헤드는 동일:**

| Clock | 호출당 평균 | 해상도 (평균) |
|-------|-----------|-------------|
| `system_clock` | 21.5 ns | 20.4 ns |
| `steady_clock` | 21.9 ns | 20.2 ns |
| `high_resolution_clock` | 21.1 ns | 20.1 ns |

세 clock 모두 해상도와 오버헤드가 거의 동일하다.
`steady_clock`으로 변경해도 성능 저하가 없으면서 monotonic 보장을 얻는다.

### 11.3 system_clock의 NTP 영향 — 재현이 어려운 시나리오

NTP step 조정은 실제 환경에서 드물게 발생하므로 직접 재현이 어렵다.
그러나 다음과 같은 시나리오에서 문제가 발생한다:

**시나리오 1: NTP step 조정 (ntpdate 또는 chronyd step)**
```
시각 12:00:00.000 - system_clock으로 start 기록 (epoch: 1712016000.000)
시각 12:00:00.050 - NTP가 시계를 -2초 조정 → 실제 시각 11:59:58.050
시각 11:59:58.100 - system_clock으로 end 기록 (epoch: 1712015998.100)

경과 시간 = end - start = -1.900초 (음수!)
```

**시나리오 2: 수동 시계 변경 (date 명령 등)**
```
시각 12:00:00.000 - system_clock으로 start 기록
관리자가 date -s "12:05:00" 실행
시각 12:05:00.050 - system_clock으로 end 기록

경과 시간 = 300.050초 (실제 0.050초인데 5분으로 측정)
```

**시나리오 3: VM 라이브 마이그레이션 / 일시 중지-재개**
```
VM이 일시 중지되었다가 재개되면 CLOCK_REALTIME은 host 시간과 동기화하면서 점프할 수 있다.
CLOCK_MONOTONIC은 VM 중지 시간을 포함하지 않거나, 최소한 뒤로 가지는 않는다.
```

**CUBRID에서의 실제 영향:**

1. **성능 통계 (`cubperf`)**: `cubrid statdump`의 timer 통계가 음수이거나 비정상적으로 커질 수 있음
2. **스레드 대기 (`thread_waiter`)**: `wait_until`이 system_clock 기준이면 NTP 조정 시 예상보다 오래/짧게 대기
3. **스레드 루퍼 (`thread_looper`)**: 실행 시간 계산이 왜곡되어 sleep 주기가 비정상적으로 변할 수 있음

`steady_clock`/`CLOCK_MONOTONIC`은 이런 외부 요인에 영향받지 않으므로,
경과 시간 측정에는 항상 monotonic clock을 사용해야 한다.

---

## 12. 기존 시간 측정 API 구조 분석: 새로 모아야 하나?

시간 측정 함수를 하나의 소스 파일에 모아두고 다른 곳에서 일관된 함수만 쓰게 하면
좋을 것 같지만, 현재 구조를 보면 **이미 잘 중앙화되어 있어서 대규모 리팩토링이 불필요**하다.

### 12.1 현재 존재하는 시간 측정 API 목록

코드베이스에 7~8개의 시간 측정 API가 분산되어 있다.

| API | 위치 | 타입 | 사용하는 clock | 사용처 수 |
|-----|------|------|--------------|----------|
| **tsc_timer** | `base/tsc_timer.h` | C | CPU TSC / `CLOCK_REALTIME_COARSE` fallback | 13개 파일 |
| **cubperf** | `base/perf_def.hpp`, `perf.hpp` | C++ template | `high_resolution_clock` | 5개 파일 |
| **cubmonitor** | `monitor/monitor_definition.hpp`, `monitor_collect.hpp` | C++ template | `high_resolution_clock` | lockfree_hashmap 등 |
| **cas_util** | `broker/cas_util.h` | C | `gettimeofday` (struct timeval) | 13개 파일 |
| **broker_log_util** | `broker/broker_log_util.h` | C | `gettimeofday` (struct timeval) | 7개 파일 |
| **ddl_log** | `base/ddl_log.h` | C | `gettimeofday` (내부 static) | 12개 파일 |
| **porting** | `base/porting.h` | C | `struct timeval` | page_buffer 등 소수 |
| **unloaddb** | `executables/unload_object_file.h` | C | `CLOCK_MONOTONIC` (struct timespec) | 1개 파일 |

### 12.2 엔진(src/) 쪽: 이미 중앙화되어 있다

엔진 코드의 시간 측정은 3개의 중앙 정의에 의존하고 있으며,
각 중앙 정의의 clock 타입만 바꾸면 모든 호출자가 자동으로 따라간다.

**C 코드: `tsc_timer.h`가 이미 중앙 API**

```
tsc_getticks()              -- 시간 읽기
tsc_elapsed_time_usec()     -- 경과 시간 계산
tsc_start_time_usec()       -- 시작
tsc_end_time_usec()         -- 끝 + 계산
```

13개 파일(lock_manager.c, page_buffer.c, file_io.c, critical_section.c 등)이
이 함수들을 사용하고 있으며, `tsc_timer.c` 내부의 clock만 `CLOCK_MONOTONIC`으로 바꾸면
**호출자는 아무것도 안 바꿔도 된다**.

**C++ 성능 통계: `cubperf::clock` typedef가 이미 중앙 정의**

```cpp
// perf_def.hpp 한 곳만 바꾸면
using clock = std::chrono::steady_clock;
```

`cubperf::clock::now()`를 사용하는 ~23개 파일이 자동으로 `steady_clock`을 사용하게 된다.
코드 변경 없이 재컴파일만 하면 된다.

**C++ 모니터링: `cubmonitor::clock_type` typedef가 이미 중앙 정의**

```cpp
// monitor_definition.hpp 한 곳만 바꾸면
using clock_type = std::chrono::steady_clock;
```

`cubmonitor::timer`, `autotimer` 등 모니터링 프레임워크 전체가 자동으로 따라간다.

### 12.3 스레드 인프라: 직접 변경 필요하지만 단순 치환

`thread_looper`, `thread_waiter`, `thread_worker_pool`, `thread_entry`에서는
`cubperf`/`cubmonitor`를 거치지 않고 `std::chrono::system_clock`을 직접 사용한다.
이 부분은 12곳에서 `system_clock` -> `steady_clock`으로 직접 바꿔야 한다.

단, `steady_clock::duration`과 `system_clock::duration`은 같은 타입(`nanoseconds`)이므로
호출자 쪽 코드 변경은 없다.

### 12.4 엔진 4개 그룹을 하나로 합칠 수 있는가?

엔진의 4개 그룹은 얼핏 보면 중복처럼 보이지만, 실제로는 **각각 다른 추상화 레이어**를 담당한다.

```
[시간 소스 레이어]
  tsc_timer (C)          "지금 시간을 읽는다" (TSC 또는 clock_gettime)

[통계 프레임워크 레이어]
  cubperf (C++ template)     counter + timer 조합, statset_definition 팩토리
  cubmonitor (C++ template)  트랜잭션 scope 인식, RAII autotimer, 글로벌/트랜잭션 분리

[유틸리티 레이어]
  porting (C)            timeval 산술 (diff, add) 단순 유틸리티
```

| 그룹 | 레이어 | 핵심 역할 | 사용 패턴 |
|------|--------|----------|----------|
| `tsc_timer` | 시간 소스 | "지금 시간은?"을 읽음 | `tsc_getticks()` -> `tsc_elapsed_time_usec()` |
| `cubperf` | 통계 프레임워크 | counter + timer 묶음 관리 | `statset_definition`으로 통계 셋 정의 후 `time_and_increment()` 호출 |
| `cubmonitor` | 모니터링 프레임워크 | scope 기반 자동 측정 + 트랜잭션 분리 | `autotimer` 생성하면 scope 종료 시 자동 기록 |
| `porting` | 유틸리티 | timeval 산술 | `timeval_diff_in_msec(end, start)` |

**합치지 않는 이유:**

1. **cubperf vs cubmonitor**: 설계 철학이 다름
   - cubperf: "명시적 호출" 방식 (`time_and_increment()` 직접 호출)
   - cubmonitor: "scope 기반 자동 측정" 방식 (RAII `autotimer`가 생성/소멸 시 자동 기록)
   - cubmonitor는 글로벌/트랜잭션 sheet 분리 기능이 있음 (cubperf에는 없음)
   - 합치면 하나의 거대한 프레임워크가 되어 오히려 복잡해짐

2. **tsc_timer vs cubperf/cubmonitor**: 레이어가 다름
   - tsc_timer는 "시간을 읽는" 저수준 API (C 코드에서 사용)
   - cubperf/cubmonitor는 "통계를 관리하는" 고수준 프레임워크 (C++ 코드에서 사용)
   - tsc_timer를 없애면 C 코드(lock_manager.c, page_buffer.c 등)에서 C++ 헤더를 include해야 함

3. **porting**: 범용 유틸리티
   - `timeval_diff_in_msec`는 시간 측정 전용이 아니라 timeval 자료형의 산술 유틸리티
   - porting.h는 OS 이식성 레이어이므로 시간 측정 모듈에 넣는 것은 부적절

**결론: 같은 일을 중복하는 4개가 아니라, 각자 다른 레이어를 담당하는 4개이므로
합치는 것은 이득이 없다. clock 정의만 통일하면 충분하다.**

### 12.5 Broker 쪽: 같은 일을 하는 diff 함수가 4개

Broker에는 시간 차이를 계산하는 함수가 4가지나 있다:

| 함수 | 위치 | 반환 타입 | 사용처 |
|------|------|----------|--------|
| `ut_timeval_diff(start, end, &sec, &msec)` | `cas_util.c:69` | void (sec/msec 분리) | 13개 파일 |
| `ut_diff_time(begin, end)` | `broker_log_util.c:466` | double (초) | 7개 파일 |
| `logddl_timeval_diff(start, end)` | `ddl_log.c:1480` | static (내부 전용) | 1개 (내부) |
| `timeval_diff_in_msec(start, end)` | `porting.c` | INT64 (밀리초) | 소수 |

이것들을 하나로 통합하려면 반환 타입, 파라미터 규약이 모두 다르므로 변경이 크다.
하지만 **통합하지 않아도 된다** - 각각 용도와 반환 형식이 다르고,
broker는 엔진과 별도 프로세스이다.

### 12.6 결론: 새로 모을 필요 없이, 중앙 정의 3곳만 바꾸면 된다

| 작업 | 바꿀 파일 | 바꿀 줄 수 | 호출자 변경 |
|------|----------|-----------|-----------|
| `tsc_timer.c` clock 변경 | 1 | 1 | **없음** (이미 중앙화) |
| `perf_def.hpp` clock 변경 | 1 | 1 | **없음** (typedef 따라감, 13개 파일 재컴파일) |
| `monitor_definition.hpp` clock 변경 | 1 | 1 | **없음** (typedef 따라감) |
| `thread_*` system_clock 변경 | 5 | 12 | **없음** (같은 duration 타입) |
| `connection_pool.cpp` system_clock 변경 | 1 | 6 | **없음** (같은 duration 타입) |
| **합계** | **9개 파일** | **~21줄** | **0** |

기존 설계가 clock 타입을 중앙에서 정의하고 나머지가 참조하는 구조이므로,
시간 측정 함수를 새로 모아서 만들 필요 없이 **기존 중앙 정의의 clock만 교체**하면
코드베이스 전체가 일관되게 monotonic clock을 사용하게 된다.

## 13. Docker/VM 환경에서의 steady_clock 동작

### 13.1 Docker 컨테이너

Docker 컨테이너는 호스트 커널을 공유하므로 `CLOCK_MONOTONIC`(`steady_clock`)은
호스트와 완전히 동일하게 동작한다. 컨테이너 고유의 문제는 없다.

### 13.2 가상 머신 (VM)

Linux 커널은 VM 환경에서도 `CLOCK_MONOTONIC`의 단조 증가를 보장한다.
KVM(`kvm-clock`), VMware, Hyper-V 등 주요 하이퍼바이저 모두 이 보장을 준수한다.

| 시나리오 | CLOCK_MONOTONIC / steady_clock | CLOCK_REALTIME / system_clock |
|---------|-------------------------------|-------------------------------|
| NTP step 조정 | 영향 없음 | 앞/뒤로 점프 |
| 수동 시계 변경 | 영향 없음 | 앞/뒤로 점프 |
| VM 라이브 마이그레이션 | **뒤로 가지 않음** (앞으로는 점프 가능) | 앞/뒤 모두 점프 가능 |
| VM 일시중지→재개 | **뒤로 가지 않음** (중지 시간 포함될 수 있음) | 앞/뒤 모두 점프 가능 |

### 13.3 VM 일시중지→재개 시 edge case

VM이 일시중지되었다가 재개되면 `CLOCK_MONOTONIC`이 중지 시간을 포함하여
앞으로 크게 점프할 수 있다. 예를 들어 VM이 5분 중지되면 elapsed time이
실제 작업 시간 + 5분으로 측정될 수 있다.

그러나 이것은 실질적으로 문제가 되지 않는다:

- **뒤로 가지 않으므로** 음수/오버플로우가 발생하지 않음
- VM 일시중지는 매우 드문 이벤트이고, 이 동안에는 DB 프로세스 자체도 멈춰 있으므로 실질적 영향 없음
- `system_clock`은 같은 상황에서 **뒤로도** 갈 수 있어 더 위험함

### 13.4 결론

Docker/VM 환경 모두 `steady_clock`이 `system_clock`보다 안전하다.
`CLOCK_MONOTONIC`의 단조 증가 보장은 가상화 환경에서도 유지된다.
