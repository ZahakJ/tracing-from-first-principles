# hist.py: pair sys_enter_read / sys_exit_read lines from `perf script -F tid,time,event --ns`
# per thread and print a power-of-two histogram of the latency in ns, like bpftrace's hist().
import sys
start, buckets, pairs = {}, {}, 0
for line in sys.stdin:
	f = line.split()
	if len(f) < 3:
		continue
	tid, t = f[0], float(f[1].rstrip(':'))
	if 'sys_enter_read' in f[2]:
		start[tid] = t
	elif tid in start:
		ns = int(round((t - start.pop(tid)) * 1e9))
		b = 0 if ns <= 0 else 1 << (ns.bit_length() - 1)
		buckets[b] = buckets.get(b, 0) + 1
		pairs += 1
def h(n):
	for u, s in ((1 << 30, 'G'), (1 << 20, 'M'), (1 << 10, 'K')):
		if n >= u:
			return '%d%s' % (n // u, s)
	return str(n)
top = max(buckets.values())
print('%d enter/exit pairs' % pairs)
for b in sorted(buckets):
	lo, hi = ('0', '1') if b == 0 else (h(b), h(2 * b))
	print('[%s, %s)%s %8d |%-52s|' % (lo, hi, ' ' * (12 - len(lo) - len(hi)), buckets[b], '@' * (buckets[b] * 52 // top)))
