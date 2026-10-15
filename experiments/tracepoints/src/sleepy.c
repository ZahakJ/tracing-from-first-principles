/* sleepy: about 0.2 s of computing, then two kinds of waiting: a 1 s
 * nanosleep(), and a read() on a pipe that a child answers 0.8 s later.
 * At the end it prints its own wall-clock and CPU time, so the waiting
 * the scheduler tracepoints see can be checked against real - cpu.      */
#include <stdio.h>
#include <time.h>
#include <unistd.h>
#include <sys/wait.h>

static double now(clockid_t c)
{
	struct timespec t;

	clock_gettime(c, &t);
	return t.tv_sec + t.tv_nsec / 1e9;
}

int main(void)
{
	struct timespec one = { 1, 0 }, later = { 0, 800000000 };
	double r0 = now(CLOCK_MONOTONIC), c0 = now(CLOCK_PROCESS_CPUTIME_ID);
	volatile unsigned long x = 1;
	int p[2];
	char c;

	for (unsigned long i = 0; i < 100000000UL; i++)	/* compute */
		x = x * 2862933555777941757UL + 3037000493UL;
	nanosleep(&one, NULL);				/* wait for a timer */
	pipe(p);
	if (fork() == 0) {				/* the slow answerer */
		nanosleep(&later, NULL);
		write(p[1], "!", 1);
		_exit(0);
	}
	read(p[0], &c, 1);				/* wait for an answer */
	wait(NULL);
	printf("real %.6f s  cpu %.6f s  real-cpu %.6f s\n",
	       now(CLOCK_MONOTONIC) - r0, now(CLOCK_PROCESS_CPUTIME_ID) - c0,
	       now(CLOCK_MONOTONIC) - r0 - (now(CLOCK_PROCESS_CPUTIME_ID) - c0));
	return 0;
}
