/*
 * waits: three ways to block. Sleep 200 ms, read from a pipe whose
 * writer (a child) answers after 300 ms, and fsync a small file.
 */
#include <fcntl.h>
#include <stdio.h>
#include <time.h>
#include <unistd.h>
#include <sys/wait.h>

int main(void)
{
	struct timespec ts = { 0, 200 * 1000 * 1000 };
	char buf[16];
	int p[2], fd;

	nanosleep(&ts, NULL);

	pipe(p);
	if (fork() == 0) {
		usleep(300 * 1000);
		write(p[1], "hello", 5);
		_exit(0);
	}
	read(p[0], buf, sizeof(buf));
	wait(NULL);

	fd = open("/tmp/waits.dat", O_WRONLY | O_CREAT | O_TRUNC, 0644);
	write(fd, "some data\n", 10);
	fsync(fd);
	close(fd);
	return 0;
}
