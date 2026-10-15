/*
 * shout: upper-case a string in place, the slow way.
 *
 * strlen(s) is in the loop condition, so it runs once per character:
 * n calls to toupper() and n+1 calls to strlen(), each of which walks
 * the whole string. Quadratic, and almost no syscalls.
 *
 * Usage: shout [n]    (n bytes of text, default 200000)
 */
#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char **argv)
{
	size_t n = argc > 1 ? strtoul(argv[1], NULL, 10) : 200000;
	char *s = malloc(n + 1);
	size_t i;

	for (i = 0; i < n; i++)
		s[i] = "hello world "[i % 12];
	s[n] = '\0';

	for (i = 0; i < strlen(s); i++)
		s[i] = toupper(s[i]);

	printf("%.12s... (%zu bytes)\n", s, n);
	free(s);
	return 0;
}
