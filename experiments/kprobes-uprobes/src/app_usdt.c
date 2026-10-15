/* app_usdt: app's bench loop, with a probe point the program declares itself.
 *     app_usdt bench N
 * DTRACE_PROBE1 compiles to a single nop plus a note in the ELF file that
 * says where the nop is and where to find the argument. A tracer that reads
 * the note can put a uprobe on the nop; until then it costs one nop.     */
#include <stdio.h>
#include <stdlib.h>
#include <sys/sdt.h>
#include <time.h>

volatile int sink;

__attribute__((noinline)) int handle(int id)
{
	DTRACE_PROBE1(tracelab, request, id);
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
