/* fastcat: copy stdin to stdout with a 64 KiB buffer. */
#include <unistd.h>

static char buf[65536];

int main(void)
{
	ssize_t n;

	while ((n = read(0, buf, sizeof(buf))) > 0)
		write(1, buf, n);
	return 0;
}
