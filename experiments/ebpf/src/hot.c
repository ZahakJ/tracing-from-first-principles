/*
 * hot: burn CPU in three functions whose work is in the ratio 6:3:1.
 */
#include <stdio.h>

static volatile unsigned long sink;

/* Each function has its own loop, so a sample's instruction pointer names it. */
void __attribute__((noinline)) big(void)
{
	for (unsigned long i = 0; i < 1800000000UL; i++)
		sink += i;
}

void __attribute__((noinline)) medium(void)
{
	for (unsigned long i = 0; i < 900000000UL; i++)
		sink += i;
}

void __attribute__((noinline)) small(void)
{
	for (unsigned long i = 0; i < 300000000UL; i++)
		sink += i;
}

int main(void)
{
	big();
	medium();
	small();
	printf("%lu\n", sink);
	return 0;
}
