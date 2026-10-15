/*
 * callloop: call labs() through the PLT n times and report ns per call.
 *
 * Built with -O0 -fno-builtin so every iteration is a real
 * "call labs@plt". No syscalls happen inside the loop.
 *
 * Usage: callloop n
 */
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

int main(int argc, char **argv)
{
	long n = argc > 1 ? atol(argv[1]) : 10000000;
	struct timespec a, b;
	long i, sum = 0;
	double ns;

	clock_gettime(CLOCK_MONOTONIC, &a);
	for (i = 0; i < n; i++)
		sum += labs(-i);
	clock_gettime(CLOCK_MONOTONIC, &b);

	ns = (b.tv_sec - a.tv_sec) * 1e9 + (b.tv_nsec - a.tv_nsec);
	fprintf(stderr, "n=%ld sum=%ld total=%.0f ns\n", n, sum, ns);
	printf("%.2f\n", ns / n);
	return 0;
}
