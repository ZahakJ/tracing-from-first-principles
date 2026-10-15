/* phases: a program whose behaviour changes over time, to test how well
 * perf stat's scaling estimates a multiplexed counter.
 * Phase A mispredicts branches (a branch on a fresh pseudo-random bit,
 * with no memory traffic); phase B misses the cache (a column walk over 64 MiB) and
 * hardly mispredicts. Each takes about half a second in total.
 * "phases K" cuts each phase into K slices and alternates them
 * (A B A B ...). K = 1 is two long phases; large K gives short ones.       */
#include <stdio.h>
#include <stdlib.h>

#define AUNITS 3000		/* phase A: 3000 units of 2^16 random branches */
#define BN 4096			/* phase B data: 4096 x 4096 ints = 64 MiB */
#define BUNITS 16384		/* phase B: 16384 columns (four sweeps) */

static int *b;
static long sink;

static unsigned long x = 1;

static __attribute__((noinline)) void phase_a(long units)
{
	for (long u = 0; u < units; u++)
		for (long i = 0; i < (1 << 16); i++) {
			x = x * 6364136223846793005UL + 1442695040888963407UL;
			if (x >> 63)
				sink += i;
		}
}

static __attribute__((noinline)) void phase_b(long first, long units)
{
	for (long c = first; c < first + units; c++)
		for (long i = 0; i < BN; i++)
			sink += b[i * BN + c % BN];
}

int main(int argc, char **argv)
{
	long k = argc > 1 ? atol(argv[1]) : 1;
	b = malloc((size_t)BN * BN * sizeof(int));
	if (!b || k < 1)
		return 1;
	for (long i = 0; i < (long)BN * BN; i++)
		b[i] = i & 0xff;
	for (long s = 0; s < k; s++) {
		phase_a(AUNITS * (s + 1) / k - AUNITS * s / k);
		phase_b(BUNITS * s / k, BUNITS * (s + 1) / k - BUNITS * s / k);
	}
	printf("%ld\n", sink);
	return 0;
}
