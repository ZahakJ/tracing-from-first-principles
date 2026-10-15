/*
 * hot.c: three functions doing the same arithmetic loop, with work in
 * the ratio 6:3:1.  A profiler that tells the truth should report
 * about 60%, 30% and 10% of the time in them.
 */
#include <stdio.h>

#define UNIT 150000000UL	/* iterations for one share of work */

unsigned long __attribute__((noinline)) six(unsigned long x)
{
	for (unsigned long i = 0; i < 6 * UNIT; i++)
		x = x * 2862933555777941757UL + 3037000493UL;
	return x;
}

unsigned long __attribute__((noinline)) three(unsigned long x)
{
	for (unsigned long i = 0; i < 3 * UNIT; i++)
		x = x * 2862933555777941757UL + 3037000493UL;
	return x;
}

unsigned long __attribute__((noinline)) one(unsigned long x)
{
	for (unsigned long i = 0; i < 1 * UNIT; i++)
		x = x * 2862933555777941757UL + 3037000493UL;
	return x;
}

int main(void)
{
	unsigned long x = 1;

	x = six(x);
	x = three(x);
	x = one(x);
	printf("%lu\n", x);
	return 0;
}
