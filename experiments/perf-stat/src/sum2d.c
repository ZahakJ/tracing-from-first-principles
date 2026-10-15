/* sum2d: the same work, two ways. Fill an N x N matrix of ints, then sum
 * it either row by row (walking memory in order) or column by column
 * (jumping N * 4 bytes between consecutive loads). Both sum loops execute
 * the same instructions; only the order of the addresses differs. The sum
 * is done PASSES times so that it, not the fill, dominates the run time.
 * Usage: sum2d rows|cols                                                   */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define N 8192			/* 8192 * 8192 * 4 bytes = 256 MiB */
#define PASSES 4

static __attribute__((noinline)) long sum_rows(int *m)
{
	long s = 0;

	for (long i = 0; i < N; i++)
		for (long j = 0; j < N; j++)
			s += m[i * N + j];
	return s;
}

static __attribute__((noinline)) long sum_cols(int *m)
{
	long s = 0;

	for (long j = 0; j < N; j++)
		for (long i = 0; i < N; i++)
			s += m[i * N + j];
	return s;
}

int main(int argc, char **argv)
{
	int *m = malloc((size_t)N * N * sizeof(int));
	long s = 0;

	if (argc < 2 || !m) {
		fprintf(stderr, "usage: sum2d rows|cols\n");
		return 1;
	}
	for (long i = 0; i < (long)N * N; i++)
		m[i] = i & 0xff;
	for (int p = 0; p < PASSES; p++) {
		if (strcmp(argv[1], "cols") == 0)
			s += sum_cols(m);
		else
			s += sum_rows(m);
	}
	printf("%ld\n", s);
	free(m);
	return 0;
}
