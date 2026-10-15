/*
 * writer: write 4096 bytes to a file and say how long it took.
 *
 *   writer buffered FILE   open, write, close (the data stays in the page cache)
 *   writer fsync FILE      the same, then fsync() before close
 *   writer direct FILE     O_DIRECT: the write goes to the device before returning
 *
 * FILE may be a block device: the 4096 bytes then go to its first sector.
 * Used to show that write() returning is not the data being on disk.
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
	double t0, t1, t2;
	char *buf;
	int fd;

	if (argc != 3) {
		fprintf(stderr, "usage: writer buffered|fsync|direct FILE\n");
		return 2;
	}
	if (strcmp(argv[1], "direct") == 0)
		flags |= O_DIRECT;
	if (posix_memalign((void **)&buf, 4096, 4096))	/* O_DIRECT wants alignment */
		return 1;
	memset(buf, 'x', 4096);

	fd = open(argv[2], flags, 0644);
	if (fd < 0) {
		perror("open");
		return 1;
	}
	t0 = now_us();
	if (write(fd, buf, 4096) != 4096) {
		perror("write");
		return 1;
	}
	t1 = now_us();
	printf("write() took %.1f us\n", t1 - t0);
	if (strcmp(argv[1], "fsync") == 0) {
		if (fsync(fd)) {
			perror("fsync");
			return 1;
		}
		t2 = now_us();
		printf("fsync() took %.1f us\n", t2 - t1);
	}
	close(fd);
	return 0;
}
