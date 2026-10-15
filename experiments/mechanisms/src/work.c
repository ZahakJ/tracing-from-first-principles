/* work: the program we want to watch.
 * It builds N fake log records, checksums each one, and keeps every tenth.
 * usage: work [N]        (default 2000000)
 *
 * Built with -DTELL, every function announces itself on stderr: the first
 * and dumbest way of finding out what a program did.                       */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define NOINLINE __attribute__((noinline))

#ifdef TELL
static long now(void)
{
	struct timespec t;
	clock_gettime(CLOCK_MONOTONIC, &t);
	return t.tv_sec * 1000000000L + t.tv_nsec;
}
#define SAY(what) fprintf(stderr, "%ld %s\n", now(), what)
#else
#define SAY(what)
#endif

NOINLINE int make_record(char *buf, int i)
{
	SAY("make_record");
	return sprintf(buf, "record %d: user=%d action=%s",
		       i, i % 97, i % 3 ? "read" : "write");
}

NOINLINE unsigned checksum(const char *p, int len)
{
	unsigned h = 2166136261u;

	SAY("checksum");
	for (int round = 0; round < 8; round++)
		for (int i = 0; i < len; i++)
			h = (h ^ (unsigned char)p[i]) * 16777619u;
	return h;
}

NOINLINE char *store(const char *buf, int len)
{
	char *copy;

	SAY("store");
	copy = malloc(len + 1);
	memcpy(copy, buf, len + 1);
	return copy;
}

int main(int argc, char **argv)
{
	int n = argc > 1 ? atoi(argv[1]) : 2000000;
	char **kept = malloc((n / 10 + 1) * sizeof(char *));
	unsigned total = 0;
	char buf[128];

	for (int i = 0; i < n; i++) {
		int len = make_record(buf, i);

		total += checksum(buf, len);
		if (i % 10 == 0)
			kept[i / 10] = store(buf, len);
	}
	printf("%u\n", total);
	return 0;
}
