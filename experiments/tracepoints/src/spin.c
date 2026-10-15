/* spin: burn CPU for N seconds (default 3) without ever sleeping. */
#include <stdlib.h>
#include <time.h>

static volatile unsigned long x;

int main(int argc, char **argv)
{
	time_t end = time(NULL) + (argc > 1 ? atoi(argv[1]) : 3);


	while (time(NULL) < end)
		for (int i = 0; i < 1000000; i++)
			x++;
	return 0;
}
