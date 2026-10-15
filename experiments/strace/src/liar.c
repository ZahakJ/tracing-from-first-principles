/*
 * liar: looks for its config file in three places, finds none,
 * and reports only "startup failed". strace shows what it really tried.
 */
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

int main(void)
{
	char home_conf[512];
	const char *paths[3];
	int i, fd = -1;

	snprintf(home_conf, sizeof(home_conf), "%s/.liar.conf", getenv("HOME"));
	paths[0] = "/etc/liar/liar.conf";
	paths[1] = home_conf;
	paths[2] = "./liar.conf";

	for (i = 0; i < 3 && fd < 0; i++)
		fd = open(paths[i], O_RDONLY);
	if (fd < 0) {
		fprintf(stderr, "liar: startup failed\n");
		return 1;
	}
	close(fd);
	return 0;
}
