/*
 * blind.c - three kinds of time a sampling profiler may not see:
 * time asleep, time inside libc, and time in our own code.
 * Each function reports its own wall time so we know the truth.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define NOINLINE __attribute__((noinline))
#define BUF (64 << 20)

static double now(void)
{
	struct timespec ts;

	clock_gettime(CLOCK_MONOTONIC, &ts);
	return ts.tv_sec + ts.tv_nsec / 1e9;
}

NOINLINE static void sleeper(void)
{
	struct timespec ts = { 1, 0 };

	nanosleep(&ts, NULL);
}

NOINLINE static void in_libc(char *buf, int rounds)
{
	for (int i = 0; i < rounds; i++)
		memset(buf, i, BUF);
}

NOINLINE static long compute(long n)
{
	volatile long x = 0;

	for (long i = 0; i < n; i++)
		x += i;
	return x;
}

int main(int argc, char **argv)
{
	int rounds = argc > 1 ? atoi(argv[1]) : 1600;
	long n = argc > 2 ? atol(argv[2]) : 1300000000;
	char *buf = malloc(BUF);
	double t;
	long x;

	t = now();
	sleeper();
	fprintf(stderr, "truth: sleeper %.3f s\n", now() - t);
	t = now();
	in_libc(buf, rounds);
	fprintf(stderr, "truth: in_libc %.3f s\n", now() - t);
	t = now();
	x = compute(n);
	fprintf(stderr, "truth: compute %.3f s (x=%ld)\n", now() - t, x);
	free(buf);
	return 0;
}
