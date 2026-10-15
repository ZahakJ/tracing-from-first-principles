/*
 * calls.c - the cost of a function call, with and without a hook in it.
 * Calls a tiny add() N times (default 200,000,000) and prints ns per call.
 * For -finstrument-functions, link with cyg_hooks.c (empty hooks).
 */
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

__attribute__((noinline)) int add(int a, int b)
{
	return a + b;
}

int main(int argc, char **argv)
{
	long n = argc > 1 ? atol(argv[1]) : 200000000;
	struct timespec a, b;
	volatile int sum = 0;

	clock_gettime(CLOCK_MONOTONIC, &a);
	for (long i = 0; i < n; i++)
		sum = add(sum, (int)i);
	clock_gettime(CLOCK_MONOTONIC, &b);
	printf("%.3f\n", ((b.tv_sec - a.tv_sec) * 1e9 + (b.tv_nsec - a.tv_nsec)) / n);
	return 0;
}
