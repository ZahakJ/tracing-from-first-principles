/*
 * logger: write N records of 4 KiB one after another to a file (or a disk), fdatasync() after each one,
 * like a database log. Prints the mean and max time of one fdatasync().
 *
 *   logger N FILE      (FILE may be a block device; the records start at sector 0)
 */
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
	double t, d, sum = 0, max = 0, min = 1e18;
	char buf[4096];
	int fd, i, n;

	if (argc != 3) {
		fprintf(stderr, "usage: logger N FILE\n");
		return 2;
	}
	n = atoi(argv[1]);
	fd = open(argv[2], O_WRONLY | O_CREAT, 0644);
	if (fd < 0) {
		perror("open");
		return 1;
	}
	for (i = 0; i < n; i++) {
		memset(buf, 'a' + i % 26, sizeof(buf));
		if (write(fd, buf, sizeof(buf)) != sizeof(buf)) {
			perror("write");
			return 1;
		}
		t = now_us();
		if (fdatasync(fd)) {
			perror("fdatasync");
			return 1;
		}
		d = now_us() - t;
		sum += d;
		if (d > max)
			max = d;
		if (d < min)
			min = d;
	}
	printf("%d fdatasync: mean %.1f us, min %.1f us, max %.1f us\n",
	       n, sum / n, min, max);
	close(fd);
	return 0;
}
