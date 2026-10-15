/* Two callers of the same function: fast_path makes many cheap calls,
 * slow_path makes few expensive ones. slow_path costs ~10x more in total.
 * A profiler that counts calls and spreads time evenly over them gets the
 * split backwards; callgrind counts the instructions along each call arc.
 * Build: gcc -O1 -g -o paths paths.c                                       */

static __attribute__((noinline)) void spin(long n)
{
	volatile long x = 0;

	for (long i = 0; i < n; i++)
		x += i;
}

static __attribute__((noinline)) void fast_path(void)
{
	for (int i = 0; i < 9900; i++)
		spin(1000);
}

static __attribute__((noinline)) void slow_path(void)
{
	for (int i = 0; i < 100; i++)
		spin(1000000);
}

int main(void)
{
	fast_path();
	slow_path();
	return 0;
}
