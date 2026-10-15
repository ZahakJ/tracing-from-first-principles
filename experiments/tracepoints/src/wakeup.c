/* wakeup: an "interactive" task. Sleeps 10 ms, N times (default 200),
 * and measures how late each wake-up really was: the time from when the
 * sleep should have ended until this process is running again. */
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

static long ns(struct timespec t)
{
	return t.tv_sec * 1000000000L + t.tv_nsec;
}

int main(int argc, char **argv)
{
	int i, n = argc > 1 ? atoi(argv[1]) : 200;
	struct timespec t, now;
	long late, max = 0, sum = 0;

	clock_gettime(CLOCK_MONOTONIC, &t);
	for (i = 0; i < n; i++) {
		t.tv_nsec += 10000000;			/* next deadline: +10 ms */
		if (t.tv_nsec >= 1000000000) {
			t.tv_nsec -= 1000000000;
			t.tv_sec++;
		}
		clock_nanosleep(CLOCK_MONOTONIC, TIMER_ABSTIME, &t, NULL);
		clock_gettime(CLOCK_MONOTONIC, &now);
		late = ns(now) - ns(t);
		sum += late;
		if (late > max)
			max = late;
	}
	printf("wakeup: %d wake-ups, lateness avg %.3f ms, max %.3f ms\n",
	       n, sum / 1e6 / n, max / 1e6);
	return 0;
}
