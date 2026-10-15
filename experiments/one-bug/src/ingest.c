/*
 * ingest.c: one bug for every tracer to look at.
 *
 * Makes N (default 300) records (~200 bytes each) in memory. For each
 * record it runs checksum(), which burns about 1 ms of CPU (the red herring),
 * then appends a line to an audit log with audit_log(), which calls
 * write() and then fdatasync() every time (the real problem: the
 * program spends most of its wall time waiting for the disk).
 *
 *   ./ingest [--batch] [-n N] [logfile]
 *
 * --batch: audit_log() only writes; one fdatasync() at the end (the fix).
 * Build with -DFASTSUM to make checksum() about 10x cheaper.
 */
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define RECSZ	200
#ifdef FASTSUM
#define ROUNDS	(ROUNDS_FULL / 10)
#else
#define ROUNDS	ROUNDS_FULL
#endif
#ifndef ROUNDS_FULL
#define ROUNDS_FULL	5000
#endif

static int batch;

/* Validate a record: deliberately slow, ROUNDS passes over its bytes. */
__attribute__((noinline))
static unsigned int checksum(const unsigned char *rec, size_t len)
{
	unsigned int h = 2166136261u;
	int r;
	size_t i;

	for (r = 0; r < ROUNDS; r++)
		for (i = 0; i < len; i++)
			h = (h ^ rec[i]) * 16777619u + r;
	return h;
}

/* Append one line to the log and, unless --batch, make it durable. */
__attribute__((noinline))
static void audit_log(int fd, int id, unsigned int sum)
{
	char line[64];
	int n;

	n = snprintf(line, sizeof(line), "record %d ok sum %08x\n", id, sum);
	if (write(fd, line, n) != n) {
		perror("write");
		exit(1);
	}
	if (!batch && fdatasync(fd) < 0) {
		perror("fdatasync");
		exit(1);
	}
}

__attribute__((noinline))
static void make_record(unsigned char *rec, int id)
{
	int i;

	for (i = 0; i < RECSZ; i++)
		rec[i] = (unsigned char)(id * 31 + i * 7);
}

int main(int argc, char **argv)
{
	const char *path = "/mnt/audit.log";
	unsigned char *recs;
	int n = 300;
	int i, fd;

	for (i = 1; i < argc; i++) {
		if (strcmp(argv[i], "--batch") == 0)
			batch = 1;
		else if (strcmp(argv[i], "-n") == 0 && i + 1 < argc)
			n = atoi(argv[++i]);
		else
			path = argv[i];
	}

	recs = malloc((size_t)n * RECSZ);
	if (!recs)
		return 1;
	for (i = 0; i < n; i++)
		make_record(recs + (size_t)i * RECSZ, i);

	fd = open(path, O_WRONLY | O_CREAT | O_TRUNC | O_APPEND, 0644);
	if (fd < 0) {
		perror(path);
		return 1;
	}
	for (i = 0; i < n; i++) {
		unsigned int sum = checksum(recs + (size_t)i * RECSZ, RECSZ);

		audit_log(fd, i, sum);
	}
	if (batch && fdatasync(fd) < 0) {
		perror("fdatasync");
		return 1;
	}
	close(fd);
	free(recs);
	return 0;
}
