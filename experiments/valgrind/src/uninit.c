/* A struct with one field never set. A later 'if' on that field decides
 * what is printed: the program's behaviour depends on stack garbage.      */
#include <stdio.h>

struct conn {
	int fd;
	int port;
	int verbose;	/* never set */
};

static __attribute__((noinline)) void setup(struct conn *c)
{
	c->fd = 3;
	c->port = 8080;
}

int main(void)
{
	struct conn c;

	setup(&c);
	if (c.verbose)
		printf("verbose: fd=%d port=%d\n", c.fd, c.port);
	else
		printf("quiet\n");
	return 0;
}
