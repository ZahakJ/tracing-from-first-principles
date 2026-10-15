/*
 * reader: read a file with read() calls of three sizes, so that the
 * latency of one read() spreads over several orders of magnitude.
 *   1 MiB of 1-byte reads, 32 MiB of 4 KiB reads, the rest in 1 MiB reads.
 * usage: reader FILE
 */
#include <fcntl.h>
#include <time.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

static char buf[1 << 20];

static long phase(int fd, size_t size, long bytes)
{
	long calls = 0, done = 0;
	ssize_t n;

	while (done < bytes && (n = read(fd, buf, size)) > 0) {
		done += n;
		calls++;
	}
	return calls;
}

int main(int argc, char **argv)
{
	int fd = open(argc > 1 ? argv[1] : "/tmp/data64", O_RDONLY);
	long calls = 0;
	struct timespec a, b;

	if (fd < 0) {
		perror("open");
		return 1;
	}
	clock_gettime(CLOCK_MONOTONIC, &a);
	calls += phase(fd, 1, 1 << 20);
	calls += phase(fd, 4096, 32 << 20);
	calls += phase(fd, 1 << 20, 1L << 40);	/* to end of file */
	clock_gettime(CLOCK_MONOTONIC, &b);
	printf("%ld read() calls\n", calls + 1);	/* + the one that returned 0 */
	printf("elapsed_ms %.1f\n", (b.tv_sec - a.tv_sec) * 1e3 + (b.tv_nsec - a.tv_nsec) / 1e6);
	return 0;
}
