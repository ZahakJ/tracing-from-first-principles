/* Sum a 2048x2048 int matrix (16 MB), either row by row or column by column.
 * Both orders execute the same instructions; only the order of the memory
 * addresses differs.   Usage: sum2d rows|cols [repeats]
 * Build: gcc -O1 -g -o sum2d sum2d.c                                       */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define N 2048

static int m[N][N];

static long sum_rows(void)
{
	long s = 0;

	for (int i = 0; i < N; i++)
		for (int j = 0; j < N; j++)
			s += m[i][j];
	return s;
}

static long sum_cols(void)
{
	long s = 0;

	for (int j = 0; j < N; j++)
		for (int i = 0; i < N; i++)
			s += m[i][j];
	return s;
}

int main(int argc, char **argv)
{
	int cols = argc > 1 && strcmp(argv[1], "cols") == 0;
	int reps = argc > 2 ? atoi(argv[2]) : 1;
	long s = 0;

	for (int i = 0; i < N; i++)
		for (int j = 0; j < N; j++)
			m[i][j] = i ^ j;
	for (int r = 0; r < reps; r++)
		s += cols ? sum_cols() : sum_rows();
	printf("%ld\n", s);
	return 0;
}
