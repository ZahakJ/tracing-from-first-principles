/*
 * saver_checked: like saver, but checks every write() and says
 * which record failed and why.
 */
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

int main(void)
{
	char rec[32];
	int i, fd, ok = 0;

	fd = open("saved.txt", O_WRONLY | O_CREAT | O_TRUNC, 0644);
	for (i = 1; i <= 5; i++) {
		snprintf(rec, sizeof(rec), "record %d\n", i);
		if (write(fd, rec, strlen(rec)) != (ssize_t)strlen(rec))
			fprintf(stderr, "saver: record %d: %s\n", i, strerror(errno));
		else
			ok++;
	}
	if (close(fd) < 0)
		perror("saver: close");
	printf("saved %d of 5 records\n", ok);
	return ok == 5 ? 0 : 1;
}
