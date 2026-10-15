/* Write one byte past the end of a malloc'd buffer. malloc rounds sizes
 * up, so the byte lands in slack space and nothing visibly breaks.        */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(void)
{
	char *buf = malloc(10);

	memcpy(buf, "123456789", 10);
	buf[10] = '!';
	printf("buf: %s\n", buf);
	free(buf);
	return 0;
}
