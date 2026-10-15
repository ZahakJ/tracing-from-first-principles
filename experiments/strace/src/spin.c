/* spin: burn about a second of CPU without making a single system call. */

int main(void)
{
	volatile unsigned long x = 0;
	unsigned long i;

	for (i = 0; i < 4000000000UL; i++)
		x += i;
	return 0;
}
