/*
 * paths_truth.c - paths.c with a stopwatch around each caller, so we know
 * how spin()'s time really divides between fast_path() and slow_path().
 */
#include <stdio.h>
#include <time.h>

#define NOINLINE __attribute__((noinline))

NOINLINE static void spin(long n)
{
	volatile long x = 0;

	for (long i = 0; i < n; i++)
		x += i;
}

NOINLINE static void fast_path(void)
{
	for (int i = 0; i < 9900; i++)
		spin(5000);
}

NOINLINE static void slow_path(void)
{
	for (int i = 0; i < 100; i++)
		spin(50000000);
}

static double now(void)
{
	struct timespec ts;

	clock_gettime(CLOCK_MONOTONIC, &ts);
	return ts.tv_sec + ts.tv_nsec / 1e9;
}

int main(void)
{
	double t0, t1, t2;

	t0 = now();
	fast_path();
	t1 = now();
	slow_path();
	t2 = now();
	printf("fast_path %.4f s  slow_path %.4f s  slow share %.2f%%\n",
	       t1 - t0, t2 - t1, 100 * (t2 - t1) / (t2 - t0));
	return 0;
}
