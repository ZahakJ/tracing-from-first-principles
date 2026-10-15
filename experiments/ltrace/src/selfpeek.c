/*
 * selfpeek: print the first bytes of this program's own PLT stub for puts().
 *
 * Built without PIE, &puts is the address of the PLT stub in our own
 * binary (the "canonical" address of an undefined function). If a tracer
 * has planted a breakpoint there, the first byte reads 0xcc (int3).
 */
#include <stdio.h>

int main(void)
{
	unsigned char *p = (unsigned char *)puts;

	puts("calling puts once");
	printf("puts stub at %p: %02x %02x %02x %02x\n",
	       (void *)p, p[0], p[1], p[2], p[3]);
	puts("calling puts again");
	printf("puts stub at %p: %02x %02x %02x %02x\n",
	       (void *)p, p[0], p[1], p[2], p[3]);
	return 0;
}
