/* ministat: perf stat by hand. Open two hardware counters with the raw
 * perf_event_open system call, switch them on around a piece of work,
 * switch them off, and read them. The work is the same as ../_lib/count.c. */
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <sys/syscall.h>
#include <linux/perf_event.h>

static int open_counter(unsigned long config)
{
	struct perf_event_attr attr;

	memset(&attr, 0, sizeof(attr));
	attr.size = sizeof(attr);
	attr.type = PERF_TYPE_HARDWARE;
	attr.config = config;
	attr.disabled = 1;		/* start stopped */
	attr.exclude_kernel = 1;	/* user space only */
	/* pid 0: this process; cpu -1: any CPU; no group, no flags */
	return syscall(SYS_perf_event_open, &attr, 0, -1, -1, 0);
}

static unsigned long work(unsigned long limit)
{
	unsigned long total = 0;

	for (unsigned long n = 1; n <= limit; n++)
		for (unsigned long x = n; x != 1; total++)
			x = (x & 1) ? 3 * x + 1 : x / 2;
	return total;
}

int main(void)
{
	int ins = open_counter(PERF_COUNT_HW_INSTRUCTIONS);
	int cyc = open_counter(PERF_COUNT_HW_CPU_CYCLES);
	unsigned long n_ins, n_cyc, total;

	if (ins < 0 || cyc < 0) {
		perror("perf_event_open");
		return 1;
	}
	ioctl(ins, PERF_EVENT_IOC_ENABLE, 0);
	ioctl(cyc, PERF_EVENT_IOC_ENABLE, 0);
	total = work(30000);
	ioctl(cyc, PERF_EVENT_IOC_DISABLE, 0);
	ioctl(ins, PERF_EVENT_IOC_DISABLE, 0);
	read(ins, &n_ins, sizeof(n_ins));
	read(cyc, &n_cyc, sizeof(n_cyc));
	printf("work result   %lu\n", total);
	printf("instructions  %lu\n", n_ins);
	printf("cycles        %lu\n", n_cyc);
	return 0;
}
