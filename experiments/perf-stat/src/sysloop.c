/* sysloop: make 2,000,000 getppid() system calls. Almost all of the time
 * is spent entering, running and leaving the kernel, so the user/kernel
 * split of the counters is easy to see.                                     */
#include <stdio.h>
#include <unistd.h>
#include <sys/syscall.h>

int main(void)
{
	long s = 0;

	for (int i = 0; i < 2000000; i++)
		s += syscall(SYS_getppid);
	printf("%ld\n", s);
	return 0;
}
