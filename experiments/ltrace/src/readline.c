/* readline: open a file with stdio, read one line, close it. */
#include <stdio.h>

int main(void)
{
	char buf[128];
	FILE *f = fopen("/etc/debian_version", "r");

	if (!f)
		return 1;
	if (fgets(buf, sizeof(buf), f))
		fputs(buf, stdout);
	fclose(f);
	return 0;
}
