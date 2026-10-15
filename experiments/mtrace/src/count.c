/*
 * count.c - the dumbest leak detector: count mallocs and frees.
 *
 * Build: gcc -shared -fPIC -O2 -o count.so count.c -ldl
 * Use:   LD_PRELOAD=./count.so ./prog
 * Our malloc/calloc/realloc/free replace libc's; each counts, then calls
 * the real one, found with dlsym(RTLD_NEXT, ...). At exit, one line.
 */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

static void *(*real_malloc)(size_t);
static void *(*real_calloc)(size_t, size_t);
static void *(*real_realloc)(void *, size_t);
static void (*real_free)(void *);

static unsigned long n_malloc, n_calloc, n_realloc, n_free, bytes;

/*
 * Bootstrap problem: dlsym() itself may call calloc() before we know where
 * the real calloc is. While resolving, hand out memory from a static buffer
 * (never freed; free() ignores pointers into it).
 */
static char boot_buf[4096];
static size_t boot_used;
static int resolving;

static void *boot_alloc(size_t n)
{
	void *p = boot_buf + boot_used;

	boot_used += (n + 15) & ~15UL;
	return boot_used <= sizeof(boot_buf) ? p : NULL;
}

static void resolve(void)
{
	resolving = 1;
	real_malloc = dlsym(RTLD_NEXT, "malloc");
	real_calloc = dlsym(RTLD_NEXT, "calloc");
	real_realloc = dlsym(RTLD_NEXT, "realloc");
	real_free = dlsym(RTLD_NEXT, "free");
	resolving = 0;
}

void *malloc(size_t n)
{
	if (!real_malloc) {
		if (resolving)
			return boot_alloc(n);
		resolve();
	}
	n_malloc++;
	bytes += n;
	return real_malloc(n);
}

void *calloc(size_t k, size_t n)
{
	if (!real_calloc) {
		if (resolving)
			return boot_alloc(k * n);	/* static buffer is zeroed */
		resolve();
	}
	n_calloc++;
	bytes += k * n;
	return real_calloc(k, n);
}

void *realloc(void *p, size_t n)
{
	if (!real_realloc)
		resolve();
	n_realloc++;
	bytes += n;
	return real_realloc(p, n);
}

void free(void *p)
{
	if (!p || ((char *)p >= boot_buf && (char *)p < boot_buf + sizeof(boot_buf)))
		return;
	if (!real_free)
		resolve();
	n_free++;
	real_free(p);
}

/* Print with write(2): printf might call malloc while we report. */
__attribute__((destructor)) static void report(void)
{
	char line[200];
	int len = snprintf(line, sizeof(line),
		"count: %lu malloc + %lu calloc + %lu realloc = %lu allocations, %lu frees, %lu bytes requested\n",
		n_malloc, n_calloc, n_realloc, n_malloc + n_calloc + n_realloc, n_free, bytes);

	write(2, line, len);
}
