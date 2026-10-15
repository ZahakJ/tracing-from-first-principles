/* A fixed, deterministic piece of work with no system calls in the middle.
 * Used wherever two tools are asked the same question ("how many instructions
 * did this run?") so that their answers can be compared.
 * Build it the same way everywhere:  gcc -O1 -static -o count count.c        */
#include <stdio.h>
#include <stdlib.h>

static unsigned collatz_steps(unsigned long n)
{
	unsigned steps = 0;
	while (n != 1) {
		n = (n & 1) ? 3 * n + 1 : n / 2;
		steps++;
	}
	return steps;
}

int main(int argc, char **argv)
{
	unsigned long limit = argc > 1 ? strtoul(argv[1], 0, 10) : 30000;
	unsigned long total = 0;
	for (unsigned long n = 1; n <= limit; n++)
		total += collatz_steps(n);
	printf("%lu\n", total);
	return 0;
}
