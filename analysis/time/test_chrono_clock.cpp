/*
 * test_chrono_clock.cpp
 *
 * std::chrono의 high_resolution_clock, system_clock, steady_clock 비교 테스트
 *
 * 테스트 항목:
 *   1. high_resolution_clock이 실제로 steady(monotonic)인지 확인
 *   2. system_clock vs steady_clock 해상도/오버헤드 비교
 *   3. system_clock의 비단조성 시나리오 설명
 *
 * 빌드: g++ -std=c++14 -O2 -o test_chrono_clock test_chrono_clock.cpp -lpthread
 * 실행: ./test_chrono_clock
 */

#include <chrono>
#include <cstdio>
#include <cstdint>
#include <thread>
#include <type_traits>

#define ITERATIONS 1000000
#define RESOLUTION_SAMPLES 100

/* clock 특성 출력 */
template <typename Clock>
static void
print_clock_traits (const char *name)
{
  printf ("  %-30s : is_steady = %s\n", name, Clock::is_steady ? "true (monotonic)" : "FALSE (non-monotonic!)");
}

/* 해상도 테스트 */
template <typename Clock>
static void
test_resolution (const char *name)
{
  long min_diff_ns = 999999999;
  long max_diff_ns = 0;
  long total_diff_ns = 0;
  int zero_count = 0;

  printf ("\n=== %s 해상도 테스트 ===\n", name);

  for (int i = 0; i < RESOLUTION_SAMPLES; i++)
    {
      auto t1 = Clock::now ();
      auto t2 = Clock::now ();

      long diff_ns = std::chrono::duration_cast<std::chrono::nanoseconds> (t2 - t1).count ();

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
  printf ("  최소 차이     : %ld ns\n", (zero_count == RESOLUTION_SAMPLES) ? 0L : min_diff_ns);
  printf ("  최대 차이     : %ld ns\n", max_diff_ns);
  printf ("  평균 차이     : %.1f ns\n", (double) total_diff_ns / RESOLUTION_SAMPLES);
}

/* 호출 오버헤드 측정 */
template <typename Clock>
static void
test_overhead (const char *name)
{
  printf ("\n=== %s 호출 오버헤드 테스트 ===\n", name);
  printf ("  (%d회 now() 호출)\n", ITERATIONS);

  /* steady_clock으로 기준 측정 */
  auto start = std::chrono::steady_clock::now ();

  for (int i = 0; i < ITERATIONS; i++)
    {
      volatile auto t = Clock::now ();
      (void) t;
    }

  auto end = std::chrono::steady_clock::now ();
  long elapsed_ns = std::chrono::duration_cast<std::chrono::nanoseconds> (end - start).count ();

  printf ("  총 소요 시간  : %ld ns (%.3f ms)\n", elapsed_ns, elapsed_ns / 1000000.0);
  printf ("  호출당 평균   : %.1f ns\n", (double) elapsed_ns / ITERATIONS);
}

/* 짧은 작업 측정 비교 */
template <typename Clock>
static void
test_short_duration (const char *name)
{
  volatile int sum = 0;

  printf ("\n=== %s 짧은 작업 측정 테스트 ===\n", name);
  printf ("  (volatile 덧셈 10회 반복을 10번 측정)\n");

  for (int i = 0; i < 10; i++)
    {
      auto t_start = Clock::now ();

      for (int j = 0; j < 10; j++)
        {
          sum += j;
        }

      auto t_end = Clock::now ();

      long elapsed_ns = std::chrono::duration_cast<std::chrono::nanoseconds> (t_end - t_start).count ();

      printf ("  [%2d] elapsed = %6ld ns%s\n", i, elapsed_ns,
              (elapsed_ns == 0) ? "  <-- 0ns! 측정 불가" : "");
    }
}

/* high_resolution_clock == system_clock 확인 */
static void
test_identity (void)
{
  printf ("\n=== high_resolution_clock 정체 확인 ===\n");
  printf ("  high_resolution_clock == system_clock ? %s\n",
          std::is_same<std::chrono::high_resolution_clock, std::chrono::system_clock>::value
          ? "YES (= system_clock, non-monotonic!)"
          : "NO");
  printf ("  high_resolution_clock == steady_clock ? %s\n",
          std::is_same<std::chrono::high_resolution_clock, std::chrono::steady_clock>::value
          ? "YES (= steady_clock, monotonic)"
          : "NO");
}

int
main (void)
{
  printf ("================================================================\n");
  printf ("  std::chrono Clock 종류별 비교 테스트\n");
  printf ("================================================================\n");

  /* 1. clock 특성 */
  printf ("\n=== Clock 특성 (is_steady) ===\n");
  print_clock_traits<std::chrono::system_clock> ("system_clock");
  print_clock_traits<std::chrono::steady_clock> ("steady_clock");
  print_clock_traits<std::chrono::high_resolution_clock> ("high_resolution_clock");

  /* 2. high_resolution_clock 정체 */
  test_identity ();

  /* 3. 해상도 */
  test_resolution<std::chrono::system_clock> ("system_clock");
  test_resolution<std::chrono::steady_clock> ("steady_clock");
  test_resolution<std::chrono::high_resolution_clock> ("high_resolution_clock");

  /* 4. 짧은 작업 측정 */
  test_short_duration<std::chrono::system_clock> ("system_clock");
  test_short_duration<std::chrono::steady_clock> ("steady_clock");

  /* 5. 호출 오버헤드 */
  test_overhead<std::chrono::system_clock> ("system_clock");
  test_overhead<std::chrono::steady_clock> ("steady_clock");
  test_overhead<std::chrono::high_resolution_clock> ("high_resolution_clock");

  printf ("\n================================================================\n");
  printf ("  결론\n");
  printf ("================================================================\n");
  printf ("\n");
  printf ("  1. high_resolution_clock은 libstdc++에서 system_clock의 alias이므로\n");
  printf ("     is_steady=false, 즉 monotonic이 아님.\n");
  printf ("     → 경과 시간 측정에 부적합.\n");
  printf ("\n");
  printf ("  2. system_clock은 NTP step 조정 시 시간이 점프할 수 있어\n");
  printf ("     음수 경과 시간 또는 비정상적으로 큰 경과 시간이 발생 가능.\n");
  printf ("     → 경과 시간 측정에 부적합.\n");
  printf ("\n");
  printf ("  3. steady_clock은 항상 monotonic이 보장되어\n");
  printf ("     NTP 조정과 무관하게 정확한 경과 시간을 측정.\n");
  printf ("     → 경과 시간 측정에 적합.\n");
  printf ("\n");

  return 0;
}
