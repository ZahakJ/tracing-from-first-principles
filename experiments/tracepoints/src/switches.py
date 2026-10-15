#!/usr/bin/env python3
# switches: from a tracefs sched_switch/sched_wakeup trace, add up the time
# PID spent switched out (from its switch-out to its next switch-in).
#   switches.py PID < trace
import re, sys
pid = sys.argv[1]
out_t = out_state = woke = None
total = {}
print("%-12s %-5s %10s %12s" % ("switched out", "state", "off-CPU ms", "wake->run us"))
for line in sys.stdin:
	m = re.search(r" (\d+\.\d+): (sched_\w+): (.*)", line)
	if not m:
		continue
	t, ev, rest = float(m.group(1)), m.group(2), m.group(3)
	if ev == "sched_switch":
		if re.search(r"prev_pid=%s " % pid, rest):
			out_t = t
			out_state = re.search(r"prev_state=(\S+)", rest).group(1)
			woke = None
		elif rest.rstrip().endswith("next_pid=%s" % pid) or re.search(r"next_pid=%s( |$)" % pid, rest):
			if out_t is not None:
				d = t - out_t
				total[out_state] = total.get(out_state, 0) + d
				lat = "%.1f" % ((t - woke) * 1e6) if woke else "-"
				print("%-12.6f %-5s %10.3f %12s" % (out_t, out_state, d * 1e3, lat))
				out_t = None
	elif ev in ("sched_wakeup", "sched_waking") and re.search(r"pid=%s " % pid, rest):
		if ev == "sched_wakeup" and out_t is not None:
			woke = t
for s, d in total.items():
	print("total off-CPU with prev_state=%s: %.6f s" % (s, d))
print("total off-CPU: %.6f s" % sum(total.values()))
