/* hello: call puts() and strlen(), so we can see if ltrace catches them. */
#include <stdio.h>
#include <string.h>

int main(int argc, char **argv)
{
	const char *msg = argc > 1 ? argv[1] : "hello, library";

	puts(msg);
	printf("%zu\n", strlen(msg));
	return 0;
}
