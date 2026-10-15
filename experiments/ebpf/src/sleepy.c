/*
 * sleepy: 0.2 s of computing, then 1 s in nanosleep(), then 0.8 s blocked
 * in read() on a pipe that a child writes to after 0.8 s.
 * A CPU profile sees only the first 0.2 s.
 */
#include <stdio.h>
#include <time.h>
#include <unistd.h>

static volatile unsigned long sink;

static void compute(void)
{
	struct timespec a, b;

	clock_gettime(CLOCK_MONOTONIC, &a);
	do {
		for (int i = 0; i < 100000; i++)
			sink += i;
		clock_gettime(CLOCK_MONOTONIC, &b);
	} while ((b.tv_sec - a.tv_sec) * 1000000000L + (b.tv_nsec - a.tv_nsec) < 200000000L);
}

int main(void)
{
	struct timespec one = { 1, 0 }, eight = { 0, 800000000 };
	int p[2];
	char c;

	compute();
	nanosleep(&one, NULL);
	pipe(p);
	if (fork() == 0) {
		nanosleep(&eight, NULL);
		write(p[1], "x", 1);
		_exit(0);
	}
	read(p[0], &c, 1);
	return 0;
}
