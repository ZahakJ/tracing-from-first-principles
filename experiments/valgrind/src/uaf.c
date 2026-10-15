/* Read memory after it has been freed. Usually "works": the bytes are
 * still there, so the program prints a plausible number and exits 0.     */
#include <stdio.h>
#include <stdlib.h>

int main(void)
{
	int *p = malloc(4 * sizeof(int));

	p[2] = 42;
	free(p);
	printf("p[2] after free: %d\n", p[2]);
	return 0;
}
