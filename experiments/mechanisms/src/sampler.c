/* sampler: way 3, interrupt it and look. A profiler in one page.
 *     LD_PRELOAD=./sampler.so ./work
 * A timer interrupts the program once per millisecond of CPU time it uses.
 * Each time, we write down the address of the instruction it was about to
 * execute. At exit the addresses go to a file.                            */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/time.h>
#include <ucontext.h>

#define MAX 1000000
static void *where[MAX];
static volatile int n;

static void on_tick(int sig, siginfo_t *info, void *context)
{
	ucontext_t *uc = context;
	greg_t *regs = uc->uc_mcontext.gregs;

	if (n < MAX)
		where[n++] = (void *)regs[REG_RIP];
}

__attribute__((constructor)) static void start(void)
{
	struct sigaction sa = {
		.sa_sigaction = on_tick,
		.sa_flags = SA_SIGINFO | SA_RESTART,
	};
	struct itimerval every_ms = { { 0, 1000 }, { 0, 1000 } };

	sigaction(SIGPROF, &sa, NULL);
	setitimer(ITIMER_PROF, &every_ms, NULL);
}

__attribute__((destructor)) static void stop(void)
{
	struct itimerval off = { { 0, 0 }, { 0, 0 } };
	FILE *f = fopen(getenv("SAMPLES") ? getenv("SAMPLES") : "samples.txt", "w");

	setitimer(ITIMER_PROF, &off, NULL);
	for (int i = 0; i < n; i++) {
		Dl_info d = { 0 };

		dladdr(where[i], &d);      /* which file is this address in? */
		fprintf(f, "%p %s\n", where[i], d.dli_fname ? d.dli_fname : "?");
	}
	fclose(f);
}
