/* step: way 6, taken to its extreme. Run a program one instruction at a time.
 *     step <lo> <hi> <program> [args]      (lo, hi: hex addresses)
 * After every single instruction the kernel stops the program and wakes us.
 * We count the instructions, and how many of them were inside [lo, hi).   */
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/ptrace.h>
#include <sys/user.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

int main(int argc, char **argv)
{
	unsigned long lo = strtoul(argv[1], NULL, 16), hi = strtoul(argv[2], NULL, 16);
	unsigned long total = 0, inside = 0;
	struct timespec t0, t1;
	int status;
	pid_t pid = fork();

	if (pid == 0) {
		ptrace(PTRACE_TRACEME, 0, 0, 0);
		execvp(argv[3], argv + 3);
		_exit(127);
	}
	waitpid(pid, &status, 0);
	clock_gettime(CLOCK_MONOTONIC, &t0);
	while (WIFSTOPPED(status)) {
		long at = offsetof(struct user, regs.rip);
		unsigned long rip = ptrace(PTRACE_PEEKUSER, pid, at, 0);

		total++;
		if (rip >= lo && rip < hi)
			inside++;
		ptrace(PTRACE_SINGLESTEP, pid, 0, 0);
		waitpid(pid, &status, 0);
	}
	clock_gettime(CLOCK_MONOTONIC, &t1);
	double secs = (t1.tv_sec - t0.tv_sec) + (t1.tv_nsec - t0.tv_nsec) / 1e9;
	fprintf(stderr, "%lu instructions, %lu of them in [%#lx, %#lx) = %.1f%%\n",
		total, inside, lo, hi, 100.0 * inside / total);
	fprintf(stderr, "%.2f s, %.0f ns per instruction\n", secs, secs / total * 1e9);
	return 0;
}
