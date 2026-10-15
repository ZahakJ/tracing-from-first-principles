/* hooks: way 2, the compiler does the asking.
 * A program built with -finstrument-functions calls these two functions at
 * the top and bottom of every function it has. We keep, per function, a
 * call count and the total time between entry and exit, and print the
 * table when the program ends.                                           */
#include <stdio.h>
#include <time.h>

#define QUIET __attribute__((no_instrument_function))

static struct { void *fn; unsigned long calls, ns; } table[64];
static struct { unsigned long entered; } stack[64];
static int depth, nfn;

QUIET static unsigned long now(void)
{
	struct timespec t;
	clock_gettime(CLOCK_MONOTONIC, &t);
	return t.tv_sec * 1000000000UL + t.tv_nsec;
}

QUIET void __cyg_profile_func_enter(void *fn, void *call_site)
{
	stack[depth++].entered = now();
}

QUIET void __cyg_profile_func_exit(void *fn, void *call_site)
{
	unsigned long took = now() - stack[--depth].entered;
	int i;

	for (i = 0; i < nfn && table[i].fn != fn; i++)
		;
	if (i == nfn)
		table[nfn++].fn = fn;
	table[i].calls++;
	table[i].ns += took;
}

QUIET __attribute__((destructor)) static void report(void)
{
	for (int i = 0; i < nfn; i++)
		fprintf(stderr, "%p %lu %lu\n", table[i].fn, table[i].calls, table[i].ns);
}
