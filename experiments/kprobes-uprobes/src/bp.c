/* bp: way 4, a breakpoint by hand.
 *     bp <hex address> <program> [args]
 * Overwrites one byte of the program's code with 0xCC, the one-byte "int3"
 * instruction. Every time the CPU executes it, the kernel stops the program
 * and wakes us. We count the hit, show the arguments of the first few, put
 * the original byte back for exactly one instruction, and arm it again.   */
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/ptrace.h>
#include <sys/user.h>
#include <sys/wait.h>
#include <unistd.h>

int main(int argc, char **argv)
{
	unsigned long addr = strtoul(argv[1], NULL, 16), hits = 0;
	long original, trap;
	int status;
	pid_t pid = fork();

	if (pid == 0) {
		ptrace(PTRACE_TRACEME, 0, 0, 0);    /* "my parent may control me" */
		execvp(argv[2], argv + 2);          /* the kernel stops us right here */
		_exit(127);
	}
	waitpid(pid, &status, 0);

	original = ptrace(PTRACE_PEEKTEXT, pid, addr, 0);      /* read 8 bytes of code */
	trap = (original & ~0xffL) | 0xcc;                     /* first byte := int3 */
	ptrace(PTRACE_POKETEXT, pid, addr, trap);
	fprintf(stderr, "code at %#lx was %016lx, is now %016lx\n", addr, original, trap);
	ptrace(PTRACE_CONT, pid, 0, 0);

	while (waitpid(pid, &status, 0) > 0 && WIFSTOPPED(status)) {
		struct user_regs_struct r;

		if (WSTOPSIG(status) != SIGTRAP) {             /* not ours: pass it on */
			ptrace(PTRACE_CONT, pid, 0, WSTOPSIG(status));
			continue;
		}
		ptrace(PTRACE_GETREGS, pid, 0, &r);
		if (hits++ < 3)
			fprintf(stderr, "hit %lu: arg1=%#llx arg2=%lld\n", hits, r.rdi, r.rsi);

		r.rip -= 1;                                    /* back onto the patched byte */
		ptrace(PTRACE_SETREGS, pid, 0, &r);
		ptrace(PTRACE_POKETEXT, pid, addr, original);  /* the real instruction... */
		ptrace(PTRACE_SINGLESTEP, pid, 0, 0);          /* ...executed once... */
		waitpid(pid, &status, 0);
		ptrace(PTRACE_POKETEXT, pid, addr, trap);      /* ...and the trap goes back */
		ptrace(PTRACE_CONT, pid, 0, 0);
	}
	fprintf(stderr, "%lu hits\n", hits);
	return 0;
}
