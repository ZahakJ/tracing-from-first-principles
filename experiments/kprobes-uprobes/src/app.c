/* app: a program with one function worth watching.
 *     app watch      call handle() every 200 ms, showing its first 4 bytes
 *     app bench N    call handle() N times, print ns per call
 * In watch mode the program reads its own machine code through a function
 * pointer, so it can see a uprobe's 0xcc appear in its own text. The
 * pointer is volatile: without it gcc reads the bytes once, before the loop. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

volatile int sink;

__attribute__((noinline)) int handle(int id)
{
	return id * 3 + 1;
}

int main(int argc, char **argv)
{
	volatile unsigned char *code = (volatile unsigned char *)handle;
	struct timespec a, b;
	long i, n;

	if (argc > 1 && strcmp(argv[1], "watch") == 0) {
		for (i = 0; i < 30; i++) {
			sink = handle(i);
			printf("id=%2ld  handle: %02x %02x %02x %02x\n",
			       i, code[0], code[1], code[2], code[3]);
			fflush(stdout);
			usleep(200000);
		}
		return 0;
	}
	n = argc > 2 ? atol(argv[2]) : 1000000;
	clock_gettime(CLOCK_MONOTONIC, &a);
	for (i = 0; i < n; i++)
		sink = handle(i);
	clock_gettime(CLOCK_MONOTONIC, &b);
	printf("%.1f\n", ((b.tv_sec - a.tv_sec) * 1e9 + (b.tv_nsec - a.tv_nsec)) / n);
	return 0;
}
