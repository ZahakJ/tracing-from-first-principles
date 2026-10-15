/*
 * sum2d.c: sum a 8192 x 8192 matrix of ints (256 MiB) four times: row
 * by row (walks memory in order) and column by column (jumps 32 KiB
 * every step, so nearly every load misses the L1 cache).
 */
#include <stdio.h>
#include <stdlib.h>

#define N 8192

long __attribute__((noinline)) sum_rows(int *m)
{
	long s = 0;

	for (int i = 0; i < N; i++)
		for (int j = 0; j < N; j++)
			s += m[(long)i * N + j];
	return s;
}

long __attribute__((noinline)) sum_cols(int *m)
{
	long s = 0;

	for (int j = 0; j < N; j++)
		for (int i = 0; i < N; i++)
			s += m[(long)i * N + j];
	return s;
}

int main(void)
{
	int *m = malloc(sizeof(int) * N * N);
	long s = 0;

	if (!m)
		return 1;
	for (long k = 0; k < (long)N * N; k++)
		m[k] = k & 7;
	for (int r = 0; r < 4; r++)
		s += sum_rows(m) + sum_cols(m);
	printf("%ld\n", s);
	return 0;
}
