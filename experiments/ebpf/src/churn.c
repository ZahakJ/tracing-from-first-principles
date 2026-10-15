/*
 * churn: 5,000,000 malloc/free pairs of sizes 16..4096; prints ns per pair.
 */
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

static void *volatile keep;	/* so the compiler cannot drop the malloc */

int main(int argc, char **argv)
{
	long n = argc > 1 ? atol(argv[1]) : 5000000;
	unsigned int seed = 1;
	struct timespec a, b;

	clock_gettime(CLOCK_MONOTONIC, &a);
	for (long i = 0; i < n; i++) {
		seed = seed * 1103515245 + 12345;
		char *p = malloc(16 + (seed >> 16) % 4081);

		keep = p;
		free(p);
	}
	clock_gettime(CLOCK_MONOTONIC, &b);
	printf("%.1f\n", ((b.tv_sec - a.tv_sec) * 1e9 + (b.tv_nsec - a.tv_nsec)) / n);
	return 0;
}
