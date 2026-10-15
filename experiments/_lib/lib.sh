# Helpers shared by every experiment. Source it:  . ../_lib/lib.sh
# $OUT is the results directory (set by the runner).

# env TOOL...  -> $OUT/env.txt : kernel, CPU, compiler, libc, and each tool's version line.
env_snapshot() {
	{
		echo "kernel:   $(uname -r)"
		echo "cpu:      $(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2 | sed 's/^ //')"
		echo "where:    $( [ "$(cat /proc/1/comm)" = tracelab-init ] && echo "KVM guest, $(nproc) vCPUs, $(awk '/MemTotal/{print int($2/1024)}' /proc/meminfo) MB" || echo "Docker container (unprivileged)")"
		echo "gcc:      $(gcc --version | head -1)"
		echo "glibc:    $(ldd --version | head -1)"
		for t in "$@"; do echo "$t:  $( ($t --version 2>&1 || $t -V 2>&1) | grep -v '^$' | head -1)"; done
	} > "$OUT/env.txt"
}

# now_ns -> monotonic-ish wall clock in ns
now_ns() { date +%s%N; }

# wall_ms CMD...  -> prints elapsed wall milliseconds (3 decimals) of CMD; CMD's stdout/stderr discarded
wall_ms() { _s=$(now_ns); "$@" >/dev/null 2>&1; _e=$(now_ns); echo "$_s $_e" | awk '{printf "%.3f\n", ($2-$1)/1e6}'; }

# stats  (numbers on stdin, one per line) -> "median min max n"
stats() { sort -g | awk '{a[NR]=$1} END{ if(NR==0){print "nan nan nan 0"; exit} m=(NR%2)?a[(NR+1)/2]:(a[NR/2]+a[NR/2+1])/2; printf "%g %g %g %d\n", m, a[1], a[NR], NR}'; }

# repeat N CMD...  -> runs CMD N times; CMD must print ONE number on stdout; prints "median min max n"
repeat() { _n=$1; shift; _i=0; while [ $_i -lt $_n ]; do "$@" 2>/dev/null | tail -n 1; _i=$((_i+1)); done | stats; }

# repeat_wall N CMD... -> wall-clock ms of CMD, N times; prints "median min max n"
repeat_wall() { _n=$1; shift; _i=0; while [ $_i -lt $_n ]; do wall_ms "$@"; _i=$((_i+1)); done | stats; }
