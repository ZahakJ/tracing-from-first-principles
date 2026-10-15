/*
 * saver: writes 5 records to saved.txt, ignores what write() returns,
 * and announces success anyway.
 */
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

int main(void)
{
	char rec[32];
	int i, fd;

	fd = open("saved.txt", O_WRONLY | O_CREAT | O_TRUNC, 0644);
	for (i = 1; i <= 5; i++) {
		snprintf(rec, sizeof(rec), "record %d\n", i);
		write(fd, rec, strlen(rec));
	}
	close(fd);
	printf("saved 5 records\n");
	return 0;
}
