/*
 * paths.c - two callers of one function, with very different costs.
 *
 * fast_path() calls spin() 9900 times with a tiny argument; slow_path()
 * calls it 100 times with a huge one. slow_path() makes 1% of the calls
 * but owns about 99% of spin()'s time. Does the profiler know that?
 */
#define NOINLINE __attribute__((noinline))

NOINLINE static void spin(long n)
{
	volatile long x = 0;

	for (long i = 0; i < n; i++)
		x += i;
}

NOINLINE static void fast_path(void)
{
	for (int i = 0; i < 9900; i++)
		spin(5000);
}

NOINLINE static void slow_path(void)
{
	for (int i = 0; i < 100; i++)
		spin(50000000);
}

int main(void)
{
	fast_path();
	slow_path();
	return 0;
}
