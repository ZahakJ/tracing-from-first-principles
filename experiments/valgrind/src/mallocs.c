/* A malloc-heavy workload: many small allocations and frees.
 * Usage: mallocs [n]                                                       */
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char **argv)
{
	long n = argc > 1 ? atol(argv[1]) : 1000000;
	void *keep[64] = { 0 };
	long total = 0;

	for (long i = 0; i < n; i++) {
		int k = i & 63;

		free(keep[k]);
		keep[k] = malloc(16 + (i % 200));
		total += (long)(i % 200);
	}
	for (int k = 0; k < 64; k++)
		free(keep[k]);
	printf("%ld\n", total);
	return 0;
}
