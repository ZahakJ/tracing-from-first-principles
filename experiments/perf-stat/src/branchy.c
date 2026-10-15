/* branchy: sum the bytes >= 128 of a 32 MiB array of random bytes, eight
 * times over. With "sorted" the array is sorted first (a counting sort,
 * before the timed work), so the branch goes one way for the first half and
 * the other way for the second half. With "shuffled" it is random, and the
 * branch predictor guesses wrong about half the time. Both modes make the
 * same sorted copy, so both execute the same preparation code.
 * Usage: branchy sorted|shuffled                                            */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define SIZE (32 << 20)
#define PASSES 8

static __attribute__((noinline)) long sum_big(const unsigned char *a)
{
	long s = 0;

	for (int p = 0; p < PASSES; p++)
		for (long i = 0; i < SIZE; i++)
			if (a[i] >= 128)
				s += a[i];
	return s;
}

static void counting_sort(unsigned char *a)
{
	long count[256] = { 0 };
	long k = 0;

	for (long i = 0; i < SIZE; i++)
		count[a[i]]++;
	for (int v = 0; v < 256; v++)
		for (long c = 0; c < count[v]; c++)
			a[k++] = v;
}

int main(int argc, char **argv)
{
	unsigned char *a = malloc(SIZE);
	unsigned char *b = malloc(SIZE);
	unsigned long x = 1;

	if (argc < 2 || !a || !b) {
		fprintf(stderr, "usage: branchy sorted|shuffled\n");
		return 1;
	}
	for (long i = 0; i < SIZE; i++) {	/* a fixed pseudo-random sequence */
		x = x * 6364136223846793005UL + 1442695040888963407UL;
		a[i] = x >> 56;
	}
	memcpy(b, a, SIZE);
	counting_sort(b);
	if (strcmp(argv[1], "sorted") == 0)
		printf("%ld\n", sum_big(b));
	else
		printf("%ld\n", sum_big(a));
	free(a);
	free(b);
	return 0;
}
