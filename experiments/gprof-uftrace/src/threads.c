/*
 * threads.c - does gprof see time spent in a second thread?
 * main_work() runs in the main thread, thread_work() in another;
 * both run the same loop.
 */
#include <pthread.h>

#define NOINLINE __attribute__((noinline))

NOINLINE static void *thread_work(void *arg)
{
	volatile long x = 0;

	for (long i = 0; i < 1000000000; i++)
		x += i;
	return arg;
}

NOINLINE static void main_work(void)
{
	volatile long x = 0;

	for (long i = 0; i < 1000000000; i++)
		x += i;
}

int main(void)
{
	pthread_t t;

	pthread_create(&t, NULL, thread_work, NULL);
	main_work();
	pthread_join(t, NULL);
	return 0;
}
