# Num_object_locks_time_waited_usec 오버플로우 분석

## 현상

`cubrid statdump`의 `Num_object_locks_time_waited_usec` 값이 비정상적으로 큼.

```
Snapshot 1: 0
Snapshot 2: 3000
Snapshot 3: 51000
Snapshot 4: 3548512608093174      ← 한 번에 3.5×10^15 점프
Snapshot 5: 3548512608118174      ← 이후 정상 증가 (25000씩)
```

한 번 오염되면 이후 누적값에 영구 반영됨.

## 원인

### 1. power_Savings 판정 오류

`tsc_timer.c:check_power_savings()`에서 `/sys/devices/system/cpu/sched_mc_power_savings` 파일 존재 여부로 TSC 사용 가능 여부를 판정한다.

```c
// tsc_timer.c:218-252
fd_mc = open("/sys/devices/system/cpu/sched_mc_power_savings", O_RDONLY);
// ...
if (mc == '0' && smt == '0')
    power_Savings = 0;   // TSC 사용
else
    power_Savings = 1;   // fallback (clock_gettime)
```

최신 커널(RHEL 8+)에서는 이 파일이 **제거**되어 `power_Savings = 1`로 빠진다. 이 서버는 `constant_tsc + nonstop_tsc`를 지원하지만 TSC를 사용하지 못하고 fallback 경로로 빠짐.

### 2. fallback 경로에서 CLOCK_REALTIME_COARSE 사용

```c
// tsc_timer.c:94-98 (power_Savings != 0 경로)
clock_gettime(CLOCK_REALTIME_COARSE, &ts);
```

문제점:
- `CLOCK_REALTIME`은 **NTP 시간 조정에 영향** 받음
- NTP가 시간을 뒤로 조정하면 `end < start` 발생
- `COARSE` 해상도는 ~4ms (jiffy) → usec 정밀도 통계에 부적합

### 3. 음수 차이 → UINT64 오버플로우

```c
// tsc_timer.c:49-58 CALCULATE_ELAPSED_TIMEVAL 매크로
tv->tv_sec = end.tv_sec - start.tv_sec;   // NTP 조정 시 음수 가능
tv->tv_usec = end.tv_usec - start.tv_usec;

// lock_manager.c:3832-3834
lock_wait_time = tv_diff.tv_sec * 1000000LL + tv_diff.tv_usec;
// lock_wait_time은 UINT64 → 음수가 거대한 양수로 wrap
perfmon_lk_waited_time_on_objects(thread_p, lock, lock_wait_time);
// → ATOMIC_INC_64로 카운터에 더해짐 → 영구 오염
```

## 수정 방안

### 방안 1: CLOCK_MONOTONIC 사용 (추천, 1줄 수정)

```c
// tsc_timer.c:96 수정
clock_gettime(CLOCK_MONOTONIC, &ts);  // was CLOCK_REALTIME_COARSE
```

- NTP 영향 없음 (시간이 절대 뒤로 안 감)
- ns 정밀도
- 코어 간 일관성 보장
- 오버헤드: COARSE 대비 13 cycles 차이 (83 → 96 cycles/call). lock wait 이벤트 측정에 무시할 수준.

### 방안 2: power_Savings 판정 로직 수정

최신 커널에서 `/sys/devices/system/cpu/sched_*` 파일이 없으면 cpuinfo의 `constant_tsc` 플래그로 판정.

```c
// /proc/cpuinfo에서 constant_tsc 확인
// constant_tsc + nonstop_tsc 지원 시 power_Savings = 0 (TSC 사용)
```

rdtsc는 22 cycles/call로 가장 빠르지만, 판정 로직 변경이 필요.

### 방안 3: 음수 방어 (workaround)

```c
// lock_manager.c:3833-3834
lock_wait_time = tv_diff.tv_sec * 1000000LL + tv_diff.tv_usec;
if ((INT64)lock_wait_time > 0)
{
    perfmon_lk_waited_time_on_objects(thread_p, lock, lock_wait_time);
}
```

근본 원인은 해결하지 않지만 오버플로우를 방지.

## 벤치마크 측정 환경

```
$ grep -o 'constant_tsc\|nonstop_tsc' /proc/cpuinfo | sort -u
constant_tsc
nonstop_tsc

$ cat /sys/devices/system/cpu/sched_mc_power_savings
(파일 없음 — 최신 커널에서 제거됨)

$ uname -r
4.18.0-553.92.1.el8_10.x86_64
```

### clock_gettime 벤치마크 (이 서버)

| 방식 | cycles/call | 비고 |
|------|-------------|------|
| rdtsc | 22 | 가장 빠름 |
| CLOCK_*_COARSE | 83 | 해상도 ~4ms |
| CLOCK_MONOTONIC | 96 | NTP 안전, ns 정밀도 |
| CLOCK_REALTIME | 97 | NTP 영향 있음 |

## 변경 가이드

### 방안 1: CLOCK_MONOTONIC (추천)

**변경 파일**: `src/base/tsc_timer.c` 1줄

```diff
--- a/src/base/tsc_timer.c
+++ b/src/base/tsc_timer.c
@@ -93,7 +93,7 @@ tsc_getticks (TSC_TICKS * tck)
 #else
       struct timespec ts;
       /* replace gettimeofday with clock_gettime for performance */
-      clock_gettime (CLOCK_REALTIME_COARSE, &ts);
+      clock_gettime (CLOCK_MONOTONIC, &ts);
       tck->tv.tv_sec = ts.tv_sec;
       tck->tv.tv_usec = ts.tv_nsec / 1000;
 #endif
```

**장점**:
- 1줄 수정, 사이드이펙트 최소
- NTP 시간 조정에 영향 없음 (단조 증가 보장)
- ns 정밀도 (COARSE의 ~4ms 해상도 문제 해결)
- 모든 아키텍처에서 동작 (x86, ARM 등)

**제한사항**:
- COARSE 대비 ~13 cycles 느림 (83 → 96 cycles/call)
- lock wait, page fix 등 대기 이벤트 측정 시에만 호출되므로 성능 영향 무시 가능
- `power_Savings` 판정 로직의 근본 문제(최신 커널 미지원)는 그대로 남음

**검증 방법**:
1. 변경 후 빌드
2. 벤치마크 실행 (sysbench oltp_read_write, 256 threads, 300초)
3. `cubrid statdump`에서 `Num_object_locks_time_waited_usec` 값이 합리적 범위인지 확인
4. 이전 결과와 TPS 비교 — 성능 차이 없어야 함

### 방안 2: rdtsc 직접 사용

**변경 파일**: `src/base/tsc_timer.c` — `check_power_savings()` 수정

```diff
--- a/src/base/tsc_timer.c
+++ b/src/base/tsc_timer.c
@@ -210,17 +210,33 @@ check_power_savings (void)
 #elif defined (LINUX)
-  int fd_mc, fd_smt;
-  char mc = 0, smt = 0;
-
-  fd_mc = open ("/sys/devices/system/cpu/sched_mc_power_savings", O_RDONLY);
-  // ... (기존 파일 기반 판정 로직)
-
-  if (mc == '0' && smt == '0')
+  /*
+   * Check cpuinfo for constant_tsc flag.
+   * constant_tsc guarantees TSC runs at constant rate regardless of
+   * CPU frequency scaling. nonstop_tsc guarantees it doesn't stop in
+   * deep C-states. Both are required for reliable cross-core TSC.
+   */
+  FILE *fp = fopen("/proc/cpuinfo", "r");
+  if (fp != NULL)
     {
-      power_Savings = 0;
-      return;
+      char line[1024];
+      int has_constant_tsc = 0;
+      while (fgets(line, sizeof(line), fp))
+        {
+          if (strstr(line, "constant_tsc"))
+            {
+              has_constant_tsc = 1;
+              break;
+            }
+        }
+      fclose(fp);
+      if (has_constant_tsc)
+        {
+          power_Savings = 0;  /* TSC is reliable */
+          return;
+        }
     }
-
   power_Savings = 1;
```

**장점**:
- 가장 빠름 (22 cycles/call)
- 기존 TSC 경로(`tsc_elapsed_time_usec`)에 이미 `end < start` 방어 로직 있음 (tsc_timer.c:118-123)
- CPU 주파수 변동에도 안정적 (`constant_tsc` 보장)

**제한사항**:
- `constant_tsc` 미지원 CPU에서는 여전히 fallback 필요 (구형 CPU, VM 환경)
- `/proc/cpuinfo` 파싱이 서버 시작 시 1회 수행됨 — 오버헤드 없음
- ARM 아키텍처에서는 rdtsc 불가 — x86 전용
- VM 환경에서 `constant_tsc` 플래그가 있어도 하이퍼바이저가 TSC를 에뮬레이션하면 정밀도 저하 가능

**검증 방법**:
1. 대상 서버에서 TSC 플래그 확인:
   ```bash
   grep -o 'constant_tsc\|nonstop_tsc' /proc/cpuinfo | sort -u
   ```
2. 변경 후 빌드, `power_Savings` 값이 0인지 확인 (로그 또는 디버거)
3. 벤치마크 실행 후 statdump 값 검증
4. VM 환경이라면 방안 1(CLOCK_MONOTONIC) 권장

### 두 방안 비교

| | CLOCK_MONOTONIC | rdtsc |
|---|---|---|
| 속도 | 96 cycles/call | 22 cycles/call |
| 정밀도 | ns | sub-ns |
| 이식성 | 모든 OS/아키텍처 | x86 전용 |
| NTP 안전 | O | O (하드웨어 카운터) |
| 코어 간 일관성 | O (커널 보장) | O (constant_tsc 필요) |
| VM 안정성 | O | 하이퍼바이저 의존 |
| 코드 변경량 | 1줄 | ~20줄 |

**적용**: 방안 1 (CLOCK_MONOTONIC) 적용함.

### rdtsc 방안을 채택하지 않은 이유

**constant_tsc 플래그의 한계**:

| 환경 | constant_tsc | 신뢰도 |
|------|-------------|--------|
| 물리 서버 (Intel Core2 2006~ / AMD Bulldozer 2011~) | O | 높음 — CPU 실리콘이 보장 |
| VM (KVM, VMware) | 패스스루 가능 | 하이퍼바이저 의존 — TSC 에뮬레이션일 수 있음 |
| 구형 CPU (2006 이전) | X | 미지원 |
| ARM | 해당 없음 | rdtsc 자체가 x86 전용 |

- `constant_tsc`가 없는 환경에서 rdtsc를 쓰면 CPU 주파수 변동 시 시간이 부정확
- rdtsc 방안은 반드시 fallback 경로가 필요하므로 fallback 자체를 고치는 것이 우선

**Docker 컨테이너 환경**:

| 항목 | 컨테이너 동작 |
|------|-------------|
| `/proc/cpuinfo` | 호스트와 동일 (커널 공유) → `constant_tsc` 플래그 보임 |
| `/sys/devices/system/cpu/sched_*` | 일반적으로 마운트 안 됨 → **기존 버그 동일하게 발생** (power_Savings=1) |
| `clock_gettime(CLOCK_MONOTONIC)` | 호스트 커널이 처리 → 정상 동작 |
| `rdtsc` | 호스트 CPU에서 직접 실행 → constant_tsc 있으면 정상 |

- 컨테이너는 호스트 커널을 공유하므로 `CLOCK_MONOTONIC`은 호스트와 동일하게 동작
- `sched_mc_power_savings` 파일이 없는 문제가 컨테이너에서도 그대로 재현됨
- 즉, CLOCK_MONOTONIC 수정은 컨테이너 환경에서도 동일하게 효과적

**CLOCK_MONOTONIC이 안전한 이유**:

- 커널이 하드웨어 차이를 추상화 (TSC 있으면 TSC 사용, 없으면 HPET 등 fallback)
- x86, ARM, VM 어디서든 동일하게 동작
- 96 cycles라 해도 lock wait 이벤트(수천~수백만 cycles)에 비하면 측정 오버헤드 무시 가능
- rdtsc의 22 cycles 대비 74 cycles 차이가 실질적 성능 이득을 주는 경우는 없음

## clock_gettime 벤치마크 코드

테스트 파일: `~/.cache/tmp/clock_bench.c`

```c
#include <stdio.h>
#include <time.h>
#include <stdint.h>

static inline uint64_t rdtsc(void) {
    uint32_t lo, hi;
    __asm__ volatile ("rdtsc" : "=a"(lo), "=d"(hi));
    return ((uint64_t)hi << 32) | lo;
}

int main() {
    struct timespec ts;
    int i, N = 10000000;
    uint64_t start, end;

    start = rdtsc();
    for (i = 0; i < N; i++) clock_gettime(CLOCK_REALTIME_COARSE, &ts);
    end = rdtsc();
    printf("CLOCK_REALTIME_COARSE : %6.1f cycles/call\n", (double)(end-start)/N);

    start = rdtsc();
    for (i = 0; i < N; i++) clock_gettime(CLOCK_MONOTONIC_COARSE, &ts);
    end = rdtsc();
    printf("CLOCK_MONOTONIC_COARSE: %6.1f cycles/call\n", (double)(end-start)/N);

    start = rdtsc();
    for (i = 0; i < N; i++) clock_gettime(CLOCK_MONOTONIC, &ts);
    end = rdtsc();
    printf("CLOCK_MONOTONIC       : %6.1f cycles/call\n", (double)(end-start)/N);

    start = rdtsc();
    for (i = 0; i < N; i++) clock_gettime(CLOCK_REALTIME, &ts);
    end = rdtsc();
    printf("CLOCK_REALTIME        : %6.1f cycles/call\n", (double)(end-start)/N);

    start = rdtsc();
    for (i = 0; i < N; i++) { volatile uint64_t t = rdtsc(); (void)t; }
    end = rdtsc();
    printf("rdtsc                 : %6.1f cycles/call\n", (double)(end-start)/N);

    return 0;
}
```

빌드 및 실행:
```bash
gcc -O2 -o clock_bench clock_bench.c && ./clock_bench
```

## 관련 소스 코드

- `src/base/tsc_timer.c:96` — clock_gettime 호출 (fallback 경로)
- `src/base/tsc_timer.c:201-262` — check_power_savings() 판정 로직
- `src/transaction/lock_manager.c:3829-3835` — lock wait time 측정 및 기록
- `src/base/perf_monitor.c:1117-1124` — perfmon_lk_waited_time_on_objects()
- `src/base/perf_monitor.h:1080` — ATOMIC_INC_64 카운터 누적
