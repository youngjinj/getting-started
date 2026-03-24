/*
 * clock_compare.c
 *
 * 같은 작업을 CLOCK_REALTIME_COARSE / CLOCK_MONOTONIC 으로
 * 동시에 측정하여 차이를 보여줌.
 *
 * 빌드: gcc -O2 -o clock_compare clock_compare.c
 * 실행: ./clock_compare [반복횟수]
 *
 * 사용 예시:
 *   $ ./clock_compare 100
 *
 *     #   COARSE (us)  MONOTONIC (us)
 *   [  1]       1000 us        730 us
 *   [  2]          0 us        607 us  ← COARSE 0 실패
 *   [  3]          0 us        568 us  ← COARSE 0 실패
 *   [  4]       1000 us        743 us
 *   ...
 *
 *   ms 구간    COARSE  MONOTONIC
 *     0 ms      43       100
 *     1 ms      57         0    ← COARSE에만 존재
 *
 *   0 측정 횟수:
 *     COARSE:    43 / 100 회 (43%)   ← 실제 600us 작업이 0으로 유실
 *     MONOTONIC: 0 / 100 회 (0%)
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

/* CUBRID tsc_timer.c와 동일한 측정 방식 */
static long
measure_usec (clockid_t clk, void (*work) (int), int param)
{
  struct timespec s, e;
  long sec, usec;

  clock_gettime (clk, &s);
  work (param);
  clock_gettime (clk, &e);

  sec = e.tv_sec - s.tv_sec;
  usec = (e.tv_nsec / 1000) - (s.tv_nsec / 1000);

  return sec * 1000000L + usec;
}

/* 정렬 작업 (query order by 시뮬레이션) */
static int g_arr[10000];

static void
do_sort (int n)
{
  int i, j, tmp;
  for (i = 0; i < n; i++)
    g_arr[i] = rand ();
  /* 간단한 insertion sort — 의도적으로 느리게 */
  for (i = 1; i < n; i++)
    {
      tmp = g_arr[i];
      j = i - 1;
      while (j >= 0 && g_arr[j] > tmp)
        {
          g_arr[j + 1] = g_arr[j];
          j--;
        }
      g_arr[j + 1] = tmp;
    }
}

int
main (int argc, char *argv[])
{
  int N = argc > 1 ? atoi (argv[1]) : 100;
  int i;
  long coarse, mono;

  /* 분포 카운트 */
  int coarse_zero = 0, mono_zero = 0;
  int coarse_dist[20] = {0};  /* 0ms, 1ms, 2ms, ... 19ms */
  int mono_dist[20] = {0};

  printf ("\n");
  printf ("╔══════════════════════════════════════════════════════════════╗\n");
  printf ("║  CLOCK_REALTIME_COARSE vs CLOCK_MONOTONIC 비교              ║\n");
  printf ("║  같은 작업을 두 clock으로 동시 측정                          ║\n");
  printf ("╚══════════════════════════════════════════════════════════════╝\n");
  printf ("\n");

  /* 해상도 출력 */
  {
    struct timespec res;
    clock_getres (CLOCK_REALTIME_COARSE, &res);
    printf ("  CLOCK_REALTIME_COARSE 해상도: %ld ns (%ld ms)\n",
            res.tv_nsec, res.tv_nsec / 1000000);
    clock_getres (CLOCK_MONOTONIC, &res);
    printf ("  CLOCK_MONOTONIC 해상도:       %ld ns\n\n", res.tv_nsec);
  }

  printf ("  작업: 배열 정렬 (insertion sort 2000개)\n");
  printf ("  반복: %d 회\n\n", N);

  printf ("  %4s  %12s  %12s  %s\n", "#", "COARSE (us)", "MONOTONIC (us)", "");
  printf ("  %4s  %12s  %12s  %s\n", "----", "-----------", "--------------", "---");

  for (i = 0; i < N; i++)
    {
      coarse = measure_usec (CLOCK_REALTIME_COARSE, do_sort, 2000);
      mono = measure_usec (CLOCK_MONOTONIC, do_sort, 2000);

      /* 처음 20개만 개별 출력 */
      if (i < 20)
        {
          printf ("  [%3d]  %9ld us  %9ld us", i + 1, coarse, mono);
          if (coarse == 0 && mono > 0)
            printf ("  ← COARSE 0 실패");
          if (coarse > 0 && (coarse % 4000 < 100 || coarse % 4000 > 3900))
            printf ("  ← 4ms 배수");
          printf ("\n");
        }
      else if (i == 20)
        {
          printf ("  ...\n");
        }

      /* 분포 수집 */
      if (coarse == 0)
        coarse_zero++;
      int cms = (int) (coarse / 1000);
      if (cms < 20)
        coarse_dist[cms]++;

      if (mono == 0)
        mono_zero++;
      int mms = (int) (mono / 1000);
      if (mms < 20)
        mono_dist[mms]++;
    }

  /* 분포 출력 */
  printf ("\n");
  printf ("  %-6s  %8s  %8s\n", "ms 구간", "COARSE", "MONOTONIC");
  printf ("  %-6s  %8s  %8s\n", "------", "------", "---------");

  for (i = 0; i < 15; i++)
    {
      if (coarse_dist[i] == 0 && mono_dist[i] == 0)
        continue;
      printf ("  %3d ms  %6d    %6d", i, coarse_dist[i], mono_dist[i]);

      /* COARSE에만 몰리는 구간 표시 */
      if (coarse_dist[i] > 0 && mono_dist[i] == 0)
        printf ("    ← COARSE에만 존재");
      if (mono_dist[i] > 0 && coarse_dist[i] == 0)
        printf ("    ← MONOTONIC에만 존재");

      printf ("\n");
    }

  printf ("\n");
  printf ("  0 측정 횟수:\n");
  printf ("    COARSE:    %d / %d 회 (%d%%)\n", coarse_zero, N,
          N > 0 ? coarse_zero * 100 / N : 0);
  printf ("    MONOTONIC: %d / %d 회 (%d%%)\n", mono_zero, N,
          N > 0 ? mono_zero * 100 / N : 0);

  printf ("\n");
  printf ("  → COARSE: 0ms 또는 1ms 정수 단위로만 측정 (중간값 없음)\n");
  printf ("    MONOTONIC: 실제 소요 시간이 us 정밀도로 분포\n");
  printf ("\n");
  printf ("  수정 (1줄): src/base/tsc_timer.c:96\n");
  printf ("    - clock_gettime(CLOCK_REALTIME_COARSE, &ts);\n");
  printf ("    + clock_gettime(CLOCK_MONOTONIC, &ts);\n\n");

  return 0;
}
