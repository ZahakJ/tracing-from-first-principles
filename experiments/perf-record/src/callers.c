/*
 * callers.c: who called the hot function?  render() and compress() both
 * call the same leaf, checksum(), with about 3:1 the work.  sort_things()
 * calls libc's qsort(), which calls back into our slow comparator cmp().
 * A flat profile says "checksum is hot"; only the stack says who called it.
 */
#include <stdio.h>
#include <stdlib.h>

#define LEN 4096
#define NSORT 20000

static unsigned char buf[3 * LEN];
static int things[NSORT];

unsigned long __attribute__((noinline)) checksum(const unsigned char *p, int n)
{
	unsigned long h = 5381;

	for (int i = 0; i < n; i++)
		h = h * 33 + p[i];
	return h;
}

/* the "+ 1" stops the compiler turning the call into a jump (tail call) */
unsigned long __attribute__((noinline)) render(void)
{
	return checksum(buf, 3 * LEN) + 1;	/* three times the work */
}

unsigned long __attribute__((noinline)) compress(void)
{
	return checksum(buf, LEN) + 1;
}

/* deliberately slow: scramble both keys before comparing */
static unsigned int slow_key(unsigned int v)
{
	for (int i = 0; i < 40; i++)
		v = v * 2654435761u + 1;
	return v;
}

int __attribute__((noinline)) cmp(const void *a, const void *b)
{
	unsigned int x = slow_key(*(const int *)a);
	unsigned int y = slow_key(*(const int *)b);

	return (x > y) - (x < y);
}

int __attribute__((noinline)) sort_things(void)
{
	for (int i = 0; i < NSORT; i++)
		things[i] = rand();
	qsort(things, NSORT, sizeof(things[0]), cmp);
	return things[0];	/* work after the call: not a tail call */
}

int main(void)
{
	unsigned long h = 0;

	for (int i = 0; i < 3 * LEN; i++)
		buf[i] = i * 7;
	for (int round = 0; round < 20; round++) {
		for (int i = 0; i < 4000; i++) {
			buf[i % LEN]++;	/* new data each time */
			h += render();
			h += compress();
		}
		h += sort_things();
	}
	printf("%lu\n", h);
	return 0;
}
