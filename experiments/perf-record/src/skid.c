/*
 * skid.c: a loop where one instruction is the expensive one.  Each
 * iteration divides, and the next division needs the result of this one,
 * so the divide dominates; the instructions after it are cheap.  Where
 * do the samples land: on the divide, or after it?
 */
#include <stdio.h>

unsigned long __attribute__((noinline)) divloop(unsigned long n, unsigned long x)
{
	for (unsigned long i = 0; i < n; i++) {
		x = 0xffffffffffffUL / (x | 1);	/* the expensive instruction */
		x += i;
		x ^= 0x5555;
		x += 12345;
	}
	return x;
}

int main(void)
{
	printf("%lu\n", divloop(100000000UL, 7));
	return 0;
}
