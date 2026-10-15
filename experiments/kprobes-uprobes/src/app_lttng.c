/* app_lttng: app's bench loop, with an LTTng-UST tracepoint in handle().
 *     app_lttng bench N
 * When a session enables the event, the program itself writes it into a
 * ring buffer shared with the consumer daemon: no trap, no system call.  */
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include "tp.h"

volatile int sink;

__attribute__((noinline)) int handle(int id)
{
	lttng_ust_tracepoint(tracelab, request, id);
	return id * 3 + 1;
}

int main(int argc, char **argv)
{
	long i, n = argc > 2 ? atol(argv[2]) : 1000000;
	struct timespec a, b;

	clock_gettime(CLOCK_MONOTONIC, &a);
	for (i = 0; i < n; i++)
		sink = handle(i);
	clock_gettime(CLOCK_MONOTONIC, &b);
	printf("%.1f\n", ((b.tv_sec - a.tv_sec) * 1e9 + (b.tv_nsec - a.tv_nsec)) / n);
	return 0;
}
