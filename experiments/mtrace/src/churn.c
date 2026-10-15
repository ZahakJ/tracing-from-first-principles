/*
 * churn.c - allocator stress: N malloc/free pairs, 1000 blocks live.
 *
 * Usage: churn [N]   (default 5000000). Prints ns per malloc+free pair.
 * Calls mtrace(), which does nothing unless MALLOC_TRACE is set and
 * libc_malloc_debug.so is preloaded.
 */
#include <mcheck.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

#define WINDOW 1000

int main(int argc, char **argv)
{
	static const size_t sizes[] = { 16, 48, 128, 512, 4096 };
	static void *slot[WINDOW];
	long n = argc > 1 ? atol(argv[1]) : 5000000;
	struct timespec t0, t1;
	long i;
	double ns;

	mtrace();
	clock_gettime(CLOCK_MONOTONIC, &t0);
	for (i = 0; i < n; i++) {
		free(slot[i % WINDOW]);
		slot[i % WINDOW] = malloc(sizes[i % 5]);
		*(char *)slot[i % WINDOW] = 1;
	}
	clock_gettime(CLOCK_MONOTONIC, &t1);
	for (i = 0; i < WINDOW; i++)
		free(slot[i]);
	ns = (t1.tv_sec - t0.tv_sec) * 1e9 + (t1.tv_nsec - t0.tv_nsec);
	printf("%ld pairs, %.1f ns per malloc+free pair\n", n, ns / n);
	return 0;
}
