/*
 * minitrace: a tiny strace. Runs a command under ptrace and prints
 * "syscall <nr> = <ret>" for every system call it makes.
 * With -q it only counts the syscalls and prints the total at the end.
 * x86-64 only. Usage: minitrace [-q] cmd [args...]
 */
#include <signal.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <sys/ptrace.h>
#include <sys/user.h>
#include <sys/wait.h>

int main(int argc, char **argv)
{
	int quiet = argc > 1 && strcmp(argv[1], "-q") == 0;
	char **cmd = argv + 1 + quiet;
	struct user_regs_struct regs;
	long count = 0;
	int status, entering = 1;
	pid_t pid;

	pid = fork();
	if (pid == 0) {
		ptrace(PTRACE_TRACEME, 0, 0, 0);
		raise(SIGSTOP);		/* let the parent set options */
		execvp(cmd[0], cmd);
		perror("execvp");
		_exit(127);
	}
	waitpid(pid, &status, 0);	/* the SIGSTOP */
	ptrace(PTRACE_SETOPTIONS, pid, 0, PTRACE_O_TRACESYSGOOD);

	for (;;) {
		/* let it run to the next syscall entry or exit */
		ptrace(PTRACE_SYSCALL, pid, 0, 0);
		waitpid(pid, &status, 0);
		if (WIFEXITED(status) || WIFSIGNALED(status))
			break;
		if (!WIFSTOPPED(status) ||
		    WSTOPSIG(status) != (SIGTRAP | 0x80))
			continue;	/* a signal, not a syscall */
		ptrace(PTRACE_GETREGS, pid, 0, &regs);
		if (entering) {
			count++;
			if (!quiet)
				fprintf(stderr, "syscall %lld",
					regs.orig_rax);
		} else if (!quiet) {
			fprintf(stderr, " = %lld\n", regs.rax);
		}
		entering = !entering;
	}
	if (quiet)
		fprintf(stderr, "minitrace: %ld syscalls\n", count);
	return 0;
}
