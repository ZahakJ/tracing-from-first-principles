/*
 * uaf.c - two heap bugs that malloc/free interposers cannot see.
 *
 * (1) writes one byte past the end of a malloc(n) buffer;
 * (2) reads from a block after freeing it, and prints what it got.
 * Every malloc has its free, so a leak checker is happy. Calls mtrace()
 * so the same binary can be run under glibc's tracer.
 */
#include <mcheck.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(void)
{
	size_t n = 16;
	char *buf;
	int *p;

	mtrace();
	buf = malloc(n);
	memset(buf, 'a', n);
	buf[n] = '\0';			/* bug 1: one byte past the end */
	printf("buf = %.16s\n", buf);
	free(buf);

	p = malloc(8 * sizeof(int));
	p[5] = 42;
	free(p);
	printf("after free, p[5] = %d\n", p[5]);	/* bug 2: use after free */
	return 0;
}
