/*
 * seqwrite: N sequential 4 KiB write() calls to a file.
 *
 *   seqwrite buffered N FILE   page cache, then one fsync() at the end
 *   seqwrite direct N FILE     O_DIRECT, each write goes to the device, no fsync
 *
 * Prints the total time and the time per write().
 */
#define _GNU_SOURCE
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

static double now_us(void)
{
	struct timespec ts;

	clock_gettime(CLOCK_MONOTONIC, &ts);
	return ts.tv_sec * 1e6 + ts.tv_nsec / 1e3;
}

int main(int argc, char **argv)
{
	int flags = O_WRONLY | O_CREAT;
	int direct, fd, i, n;
	double t0, t1;
	char *buf;

	if (argc != 4) {
		fprintf(stderr, "usage: seqwrite buffered|direct N FILE\n");
		return 2;
	}
	direct = strcmp(argv[1], "direct") == 0;
	if (direct)
		flags |= O_DIRECT;
	n = atoi(argv[2]);
	if (posix_memalign((void **)&buf, 4096, 4096))
		return 1;
	memset(buf, 'x', 4096);
	fd = open(argv[3], flags, 0644);
	if (fd < 0) {
		perror("open");
		return 1;
	}
	t0 = now_us();
	for (i = 0; i < n; i++) {
		if (write(fd, buf, 4096) != 4096) {
			perror("write");
			return 1;
		}
	}
	if (!direct && fsync(fd)) {
		perror("fsync");
		return 1;
	}
	t1 = now_us();
	printf("%d writes: %.0f us total, %.2f us per write\n",
	       n, t1 - t0, (t1 - t0) / n);
	close(fd);
	return 0;
}
