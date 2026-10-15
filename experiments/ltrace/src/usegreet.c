/* usegreet: calls greet() in libgreet.so, which calls strlen() and printf(). */
#include <stdio.h>
#include <stdlib.h>

int greet(const char *name);

static int cmp(const void *a, const void *b)
{
	return *(const int *)a - *(const int *)b;
}

int main(void)
{
	int v[4] = { 3, 1, 4, 1 };

	greet("world");
	qsort(v, 4, sizeof(v[0]), cmp);
	return 0;
}
