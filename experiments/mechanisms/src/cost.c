/* cost: what does one event cost, for each way of reporting it?
 *     cost <mode> [N]
 * Calls a function N times and prints nanoseconds per call. The modes differ
 * only in what the function does to make itself known:
 *     none    nothing
 *     flag    tests an "is tracing on?" variable, which is off
 *     ring    stores {cpu timestamp counter, i} in a memory buffer
 *     clock   stores {clock_gettime(), i} in a memory buffer
 *     printf  fprintf()s a line of text to a file (buffered by stdio)
 *     write   formats a line and write()s it: one system call per event
 *     malloc  calls free(malloc(32)): used to price an LD_PRELOAD shim     */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <x86intrin.h>

#define NOINLINE __attribute__((noinline))
#define RING (1 << 20)

static struct { unsigned long when; int what; } ring[RING];
static unsigned head;
static volatile int tracing_on;
static FILE *logfile;

static unsigned long now(void)
{
	struct timespec t;
	clock_gettime(CLOCK_MONOTONIC, &t);
	return t.tv_sec * 1000000000UL + t.tv_nsec;
}

NOINLINE void tick_none(int i) { __asm__(""); }
NOINLINE void tick_ring(int i)
{
	ring[head & (RING - 1)].when = __rdtsc();
	ring[head++ & (RING - 1)].what = i;
}
NOINLINE void tick_flag(int i) { if (tracing_on) tick_ring(i); }
NOINLINE void tick_clock(int i)
{
	ring[head & (RING - 1)].when = now();
	ring[head++ & (RING - 1)].what = i;
}
NOINLINE void tick_printf(int i) { fprintf(logfile, "%lu tick %d\n", now(), i); }
NOINLINE void tick_write(int i)
{
	char line[64];
	int len = sprintf(line, "%lu tick %d\n", now(), i);

	if (write(fileno(logfile), line, len) != len)
		exit(1);
}
static void *volatile block;      /* volatile: or the compiler deletes the pair */
NOINLINE void tick_malloc(int i)
{
	block = malloc(32);
	free(block);
}

int main(int argc, char **argv)
{
	static const struct { const char *name; void (*fn)(int); } modes[] = {
		{ "none", tick_none }, { "flag", tick_flag }, { "ring", tick_ring },
		{ "clock", tick_clock }, { "printf", tick_printf },
		{ "write", tick_write }, { "malloc", tick_malloc },
	};
	long n = argc > 2 ? atol(argv[2]) : 20000000;
	void (*tick)(int) = NULL;

	for (unsigned m = 0; m < sizeof(modes) / sizeof(modes[0]); m++)
		if (argc > 1 && !strcmp(argv[1], modes[m].name))
			tick = modes[m].fn;
	if (!tick)
		return 2;
	logfile = fopen("/tmp/cost.log", "w");

	unsigned long t0 = now();
	for (long i = 0; i < n; i++)
		tick(i);
	printf("%.2f\n", (double)(now() - t0) / n);
	return 0;
}
