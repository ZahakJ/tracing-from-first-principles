/*
 * shim: an LD_PRELOAD library that interposes on labs().
 *
 * Our labs() is found before libc's, so every call from the program
 * lands here. We count it and forward to the real labs().
 */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdio.h>

static long (*real_labs)(long);
static long calls;

long labs(long x)
{
	if (!real_labs)
		real_labs = (long (*)(long))dlsym(RTLD_NEXT, "labs");
	calls++;
	return real_labs(x);
}

__attribute__((destructor)) static void report(void)
{
	fprintf(stderr, "shim: labs called %ld times\n", calls);
}
