/* shim: way 5, stand between the program and what it calls.
 *     LD_PRELOAD=./shim.so ./work
 * The dynamic linker searches preloaded libraries first, so the program's
 * calls to malloc land here. We count them and pass each one on to the real
 * malloc, which dlsym(RTLD_NEXT) finds for us. (Single-threaded: no locks.) */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <stddef.h>
#include <stdio.h>

static void *(*real_malloc)(size_t);
static unsigned long calls, bytes, by_bits[65];

void *malloc(size_t n)
{
	if (!real_malloc)
		real_malloc = dlsym(RTLD_NEXT, "malloc");
	calls++;
	bytes += n;
	by_bits[n ? 64 - __builtin_clzl(n) : 0]++;      /* bucket: bits needed for n */
	return real_malloc(n);
}

__attribute__((destructor)) static void report(void)
{
	fprintf(stderr, "malloc: %lu calls, %lu bytes\n", calls, bytes);
	for (int b = 1; b <= 64; b++)
		if (by_bits[b])
			fprintf(stderr, "  %8lu to %-8lu bytes: %lu\n",
				1UL << (b - 1), (1UL << b) - 1, by_bits[b]);
}
