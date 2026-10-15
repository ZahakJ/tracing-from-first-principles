/* Four threads, each doing the same CPU-bound loop.
 * Natively they run in parallel (user time ~4x wall time).
 * Build: gcc -O1 -pthread -o threads threads.c                            */
#include <pthread.h>
#include <stdio.h>

static void *work(void *arg)
{
	volatile long x = 0;

	for (long i = 0; i < 500000000; i++)
		x += i;
	return arg;
}

int main(void)
{
	pthread_t t[4];

	for (int i = 0; i < 4; i++)
		pthread_create(&t[i], NULL, work, NULL);
	for (int i = 0; i < 4; i++)
		pthread_join(t[i], NULL);
	printf("done\n");
	return 0;
}
