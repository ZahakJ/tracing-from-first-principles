/*
 * sleepy.c: about 0.2 s of computing and 1.8 s of waiting.  The waiting
 * is a 1 s nanosleep() and a read() from a pipe: we ask a child process
 * a question and it answers 0.8 s later.  A sampling profiler sees only
 * the 0.2 s.
 */
#include <stdio.h>
#include <time.h>
#include <unistd.h>
#include <sys/wait.h>

unsigned long __attribute__((noinline)) compute(void)
{
	unsigned long x = 1;

	for (unsigned long i = 0; i < 200000000UL; i++)
		x = x * 2862933555777941757UL + 3037000493UL;
	return x;
}

void __attribute__((noinline)) wait_for_timer(void)
{
	struct timespec ts = { 1, 0 };

	nanosleep(&ts, NULL);
}

void __attribute__((noinline)) wait_for_reply(int ask, int answer)
{
	char c = '?';

	write(ask, &c, 1);
	read(answer, &c, 1);
}

int main(void)
{
	int q[2], a[2];
	char c;

	if (pipe(q) < 0 || pipe(a) < 0)
		return 1;
	if (fork() == 0) {	/* child: read a question, answer 0.8 s later */
		struct timespec ts = { 0, 800000000 };

		read(q[0], &c, 1);
		nanosleep(&ts, NULL);
		write(a[1], "!", 1);
		_exit(0);
	}
	printf("%lu\n", compute());
	wait_for_timer();
	wait_for_reply(q[1], a[0]);
	wait(NULL);
	return 0;
}
