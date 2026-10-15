/* libgreet.so: a tiny shared library whose function calls into libc. */
#include <stdio.h>
#include <string.h>

int greet(const char *name)
{
	size_t n = strlen(name);

	printf("hello, %s\n", name);
	return (int)n;
}
