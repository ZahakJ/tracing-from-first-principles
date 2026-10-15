/* sysloop: the price of one getppid() system call.
 *     sysloop N
 * Calls getppid N times through syscall() (so libc cannot cache it) and
 * prints the average time per call in nanoseconds. Put a probe on the
 * kernel's getppid handler and the difference is the price of one hit. */
#include <stdio.h>
#include <stdlib.h>
#include <sys/syscall.h>
#include <time.h>
#include <unistd.h>

int main(int argc, char **argv)
{
	long i, n = argc > 1 ? atol(argv[1]) : 1000000;
	struct timespec a, b;

	clock_gettime(CLOCK_MONOTONIC, &a);
	for (i = 0; i < n; i++)
		syscall(SYS_getppid);
	clock_gettime(CLOCK_MONOTONIC, &b);
	printf("%.1f\n", ((b.tv_sec - a.tv_sec) * 1e9 + (b.tv_nsec - a.tv_nsec)) / n);
	return 0;
}
