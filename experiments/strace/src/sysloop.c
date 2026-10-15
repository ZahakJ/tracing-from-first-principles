/*
 * sysloop: make N getppid() system calls (default 2000000) and print
 * the average cost of one, in ns, timed with CLOCK_MONOTONIC.
 */
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <unistd.h>
#include <sys/syscall.h>

int main(int argc, char **argv)
{
	long i, n = argc > 1 ? atol(argv[1]) : 2000000;
	struct timespec a, b;
	double ns;

	clock_gettime(CLOCK_MONOTONIC, &a);
	for (i = 0; i < n; i++)
		syscall(SYS_getppid);
	clock_gettime(CLOCK_MONOTONIC, &b);
	ns = (b.tv_sec - a.tv_sec) * 1e9 + (b.tv_nsec - a.tv_nsec);
	printf("%.1f\n", ns / n);
	return 0;
}
