/*
 * test_clock_resolution.c
 *
 * 각 clock 종류별 해상도(resolution)와 오버헤드(overhead)를 비교 측정한다.
 *
 * 테스트 항목:
 *   1. CLOCK_REALTIME_COARSE vs CLOCK_MONOTONIC 해상도 비교
 *   2. CLOCK_REALTIME_COARSE vs CLOCK_MONOTONIC 호출 오버헤드 비교
 *   3. CLOCK_REALTIME vs CLOCK_MONOTONIC 차이 (NTP 영향 시나리오 설명)
 *
 * 빌드: gcc -O2 -o test_clock_resolution test_clock_resolution.c -lrt
 * 실행: ./test_clock_resolution
 */

#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <string.h>

#define ITERATIONS 1000000
#define RESOLUTION_SAMPLES 100

/* 특정 clock의 연속 호출 간 최소 시간 차이(해상도)를 측정 */
static void
test_resolution (clockid_t clk_id, const char *name)
{
  struct timespec ts1, ts2;
  long min_diff_ns = 999999999;
  long max_diff_ns = 0;
  long total_diff_ns = 0;
  int zero_count = 0;
  int i;

  printf ("\n=== %s 해상도 테스트 ===\n", name);

  for (i = 0; i < RESOLUTION_SAMPLES; i++)
    {
      long diff_ns;

      clock_gettime (clk_id, &ts1);
      clock_gettime (clk_id, &ts2);

      diff_ns = (ts2.tv_sec - ts1.tv_sec) * 1000000000L + (ts2.tv_nsec - ts1.tv_nsec);

      if (diff_ns == 0)
        {
          zero_count++;
        }
      else
        {
          if (diff_ns < min_diff_ns)
            min_diff_ns = diff_ns;
          if (diff_ns > max_diff_ns)
            max_diff_ns = diff_ns;
        }
      total_diff_ns += diff_ns;
    }

  printf ("  샘플 수      : %d\n", RESOLUTION_SAMPLES);
  printf ("  0ns 차이 횟수 : %d / %d (%.1f%%)\n",
          zero_count, RESOLUTION_SAMPLES,
          (double) zero_count / RESOLUTION_SAMPLES * 100.0);
  printf ("  최소 차이     : %ld ns\n", (zero_count == RESOLUTION_SAMPLES) ? 0 : min_diff_ns);
  printf ("  최대 차이     : %ld ns\n", max_diff_ns);
  printf ("  평균 차이     : %.1f ns\n", (double) total_diff_ns / RESOLUTION_SAMPLES);
}

/* 짧은 작업(1us 미만)의 경과 시간을 각 clock으로 측정 */
static void
test_short_duration (clockid_t clk_id, const char *name)
{
  struct timespec ts_start, ts_end;
  volatile int sum = 0;
  long elapsed_ns;
  int i;

  printf ("\n=== %s 짧은 작업 측정 테스트 ===\n", name);
  printf ("  (volatile 덧셈 10회 반복을 10번 측정)\n");

  for (i = 0; i < 10; i++)
    {
      int j;

      clock_gettime (clk_id, &ts_start);

      /* 매우 짧은 작업: 덧셈 10회 */
      for (j = 0; j < 10; j++)
        {
          sum += j;
        }

      clock_gettime (clk_id, &ts_end);

      elapsed_ns = (ts_end.tv_sec - ts_start.tv_sec) * 1000000000L
                   + (ts_end.tv_nsec - ts_start.tv_nsec);

      printf ("  [%2d] elapsed = %6ld ns%s\n", i, elapsed_ns,
              (elapsed_ns == 0) ? "  <-- 0ns! 측정 불가" : "");
    }

  (void) sum; /* suppress unused warning */
}

/* clock_gettime 호출 오버헤드 측정 */
static void
test_overhead (clockid_t clk_id, const char *name)
{
  struct timespec ts;
  struct timespec start, end;
  long elapsed_ns;
  int i;

  printf ("\n=== %s 호출 오버헤드 테스트 ===\n", name);
  printf ("  (%d회 clock_gettime 호출)\n", ITERATIONS);

  /* CLOCK_MONOTONIC으로 전체 시간을 측정 (기준) */
  clock_gettime (CLOCK_MONOTONIC, &start);

  for (i = 0; i < ITERATIONS; i++)
    {
      clock_gettime (clk_id, &ts);
    }

  clock_gettime (CLOCK_MONOTONIC, &end);

  elapsed_ns = (end.tv_sec - start.tv_sec) * 1000000000L + (end.tv_nsec - start.tv_nsec);

  printf ("  총 소요 시간  : %ld ns (%.3f ms)\n", elapsed_ns, elapsed_ns / 1000000.0);
  printf ("  호출당 평균   : %.1f ns\n", (double) elapsed_ns / ITERATIONS);
}

/* CLOCK_REALTIME vs CLOCK_MONOTONIC 비교: NTP 조정 시나리오 시뮬레이션 */
static void
test_ntp_scenario (void)
{
  struct timespec rt1, rt2, mt1, mt2;
  long rt_diff_ns, mt_diff_ns, gap_ns;

  printf ("\n=== CLOCK_REALTIME vs CLOCK_MONOTONIC 동시 측정 ===\n");
  printf ("  (현재 시점에서는 NTP step이 없으므로 유사한 값이 나옴)\n");
  printf ("  (NTP step 발생 시 REALTIME만 점프하여 경과 시간이 왜곡됨)\n\n");

  clock_gettime (CLOCK_REALTIME, &rt1);
  clock_gettime (CLOCK_MONOTONIC, &mt1);

  /* 약 100ms 대기 */
  {
    struct timespec sleep_ts = {0, 100000000L}; /* 100ms */
    nanosleep (&sleep_ts, NULL);
  }

  clock_gettime (CLOCK_REALTIME, &rt2);
  clock_gettime (CLOCK_MONOTONIC, &mt2);

  rt_diff_ns = (rt2.tv_sec - rt1.tv_sec) * 1000000000L + (rt2.tv_nsec - rt1.tv_nsec);
  mt_diff_ns = (mt2.tv_sec - mt1.tv_sec) * 1000000000L + (mt2.tv_nsec - mt1.tv_nsec);
  gap_ns = rt_diff_ns - mt_diff_ns;

  printf ("  CLOCK_REALTIME  경과: %ld ns (%.3f ms)\n", rt_diff_ns, rt_diff_ns / 1000000.0);
  printf ("  CLOCK_MONOTONIC 경과: %ld ns (%.3f ms)\n", mt_diff_ns, mt_diff_ns / 1000000.0);
  printf ("  차이 (RT - MT)      : %ld ns (%.3f ms)\n", gap_ns, gap_ns / 1000000.0);
  printf ("\n");
  printf ("  [참고] NTP step 조정이 발생하면:\n");
  printf ("    - CLOCK_REALTIME:  시간이 앞/뒤로 점프 → 음수 또는 비정상적 큰 경과 시간\n");
  printf ("    - CLOCK_MONOTONIC: 영향 없음 → 항상 정확한 경과 시간\n");
}

/* clock_getres로 시스템이 보고하는 해상도 확인 */
static void
test_system_resolution (void)
{
  struct timespec res;

  printf ("\n=== 시스템 보고 clock 해상도 (clock_getres) ===\n");

  clock_getres (CLOCK_REALTIME, &res);
  printf ("  CLOCK_REALTIME        : %ld ns\n", res.tv_sec * 1000000000L + res.tv_nsec);

  clock_getres (CLOCK_REALTIME_COARSE, &res);
  printf ("  CLOCK_REALTIME_COARSE : %ld ns\n", res.tv_sec * 1000000000L + res.tv_nsec);

  clock_getres (CLOCK_MONOTONIC, &res);
  printf ("  CLOCK_MONOTONIC       : %ld ns\n", res.tv_sec * 1000000000L + res.tv_nsec);

  clock_getres (CLOCK_MONOTONIC_COARSE, &res);
  printf ("  CLOCK_MONOTONIC_COARSE: %ld ns\n", res.tv_sec * 1000000000L + res.tv_nsec);
}

int
main (void)
{
  printf ("================================================================\n");
  printf ("  Clock 종류별 해상도/오버헤드 비교 테스트\n");
  printf ("================================================================\n");

  /* 1. 시스템 보고 해상도 */
  test_system_resolution ();

  /* 2. 실제 해상도 테스트 */
  test_resolution (CLOCK_REALTIME_COARSE, "CLOCK_REALTIME_COARSE");
  test_resolution (CLOCK_MONOTONIC_COARSE, "CLOCK_MONOTONIC_COARSE");
  test_resolution (CLOCK_REALTIME, "CLOCK_REALTIME");
  test_resolution (CLOCK_MONOTONIC, "CLOCK_MONOTONIC");

  /* 3. 짧은 작업 측정 */
  test_short_duration (CLOCK_REALTIME_COARSE, "CLOCK_REALTIME_COARSE");
  test_short_duration (CLOCK_MONOTONIC, "CLOCK_MONOTONIC");

  /* 4. 호출 오버헤드 */
  test_overhead (CLOCK_REALTIME_COARSE, "CLOCK_REALTIME_COARSE");
  test_overhead (CLOCK_MONOTONIC_COARSE, "CLOCK_MONOTONIC_COARSE");
  test_overhead (CLOCK_REALTIME, "CLOCK_REALTIME");
  test_overhead (CLOCK_MONOTONIC, "CLOCK_MONOTONIC");

  /* 5. NTP 시나리오 */
  test_ntp_scenario ();

  printf ("\n================================================================\n");
  printf ("  테스트 완료\n");
  printf ("================================================================\n");

  return 0;
}
