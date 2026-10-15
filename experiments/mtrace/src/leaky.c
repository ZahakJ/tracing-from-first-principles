/*
 * leaky.c - a toy server that leaks on its error paths.
 *
 * Handles 1000 fake requests. Each one allocates a request struct, a name
 * (through xstrdup -> xmalloc) and a payload (plain malloc). Every 10th
 * request bails out and forgets the payload (100 leaks); every 25th forgets
 * the name (40 leaks). Set MALLINFO=1 to print the allocator's view at exit.
 */
#include <malloc.h>
#include <mcheck.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

struct request {
	int id;
	char *name;
	char *payload;
};

static void *xmalloc(size_t n)
{
	void *p = malloc(n);

	if (!p)
		abort();
	return p;
}

static char *xstrdup(const char *s)
{
	return strcpy(xmalloc(strlen(s) + 1), s);
}

static int handle(int id)
{
	struct request *r = malloc(sizeof(*r));
	char name[32];

	r->id = id;
	snprintf(name, sizeof(name), "request-%d", id);
	r->name = xstrdup(name);
	r->payload = malloc(256);
	memset(r->payload, 'x', 256);

	if (id % 10 == 0 || id % 25 == 0) {
		/* error path: bail out early ... and forget things */
		if (id % 25 != 0)
			free(r->name);		/* bug: name kept on every 25th */
		if (id % 10 != 0)
			free(r->payload);	/* bug: payload kept on every 10th */
		free(r);
		return -1;
	}
	free(r->payload);
	free(r->name);
	free(r);
	return 0;
}

int main(void)
{
	int i, errors = 0;

	mtrace();
	for (i = 1; i <= 1000; i++)
		if (handle(i) < 0)
			errors++;
	printf("handled 1000 requests, %d errors\n", errors);
	if (getenv("MALLINFO")) {
		struct mallinfo2 mi = mallinfo2();

		fprintf(stderr, "mallinfo2: arena %zu  in use %zu  free %zu\n",
			mi.arena, mi.uordblks, mi.fordblks);
		malloc_stats();
		malloc_info(0, stderr);
	}
	return 0;
}
