#!/bin/sh
# eBPF and bpftrace: a program at the hook.
. ../_lib/lib.sh
exec </dev/null
env_snapshot bpftrace bpftool perf python3
T=/sys/kernel/tracing
LIBC=/lib/x86_64-linux-gnu/libc.so.6

for p in reader sysloop churn rawbpf; do gcc -O2 -Wall -o $p src/$p.c; done
gcc -O2 -g -fno-omit-frame-pointer -no-pie -Wall -o hot src/hot.c
gcc -O2 -g -fno-omit-frame-pointer -no-pie -Wall -o sleepy src/sleepy.c

mkdir -p /tmp/ram && mount -t tmpfs -o size=128m none /tmp/ram
head -c 64M /dev/urandom > /tmp/ram/data64
R="./reader /tmp/ram/data64"
rms() { grep elapsed_ms | awk '{print $2}'; }     # the reader's own elapsed ms
# wait_for FILE PATTERN: until a background tool says it is attached (max 20 s)
wait_for() { i=0; while ! grep -q "$2" "$1" </dev/null 2>/dev/null && [ $i -lt 200 ]; do sleep 0.1; i=$((i+1)); done; sleep 0.3; }
trim() { awk -v n="$1" 'NR<=n{print} END{if(NR>n) printf "[... %d more lines]\n", NR-n}'; }
newfiles() { find / /tmp -xdev -type f -newer /tmp/marker 2>/dev/null | grep -v -e '^/proc' -e '^/sys' -e "^$OUT"; }

# ---- 01: the firehose versus the answer ----------------------------------------------------------
{
	echo "\$ $R   (bare, 5 runs; reader's own elapsed ms)"
	$R
	echo "elapsed ms median min max n: $(for i in 1 2 3 4 5; do $R | rms; done | stats)"
} > $OUT/01a-bare.txt 2>&1

{
	echo "\$ perf record -e syscalls:sys_enter_read,syscalls:sys_exit_read -o /tmp/a.data $R"
	for i in 1 2 3 4; do perf record -q -e syscalls:sys_enter_read,syscalls:sys_exit_read -o /tmp/a.data $R | rms >> /tmp/a.ms 2>/dev/null; done
	touch /tmp/marker; sleep 0.01
	s=$(now_ns)
	perf record -e syscalls:sys_enter_read,syscalls:sys_exit_read -o /tmp/a.data $R > /tmp/a.out 2>/tmp/a.err
	e=$(now_ns)
	cat /tmp/a.out /tmp/a.err
	rms < /tmp/a.out >> /tmp/a.ms
	echo "whole perf record command (last run): $(( (e-s)/1000000 )) ms"
	echo "reader elapsed ms under perf record, median min max n: $(stats < /tmp/a.ms)"
	echo "files written during the last run:"; newfiles | xargs -r ls -l
	echo; echo "\$ perf report -i /tmp/a.data --stats | grep -E 'SAMPLE|LOST|TOTAL'"
	perf report -i /tmp/a.data --stats 2>/dev/null | grep -E 'SAMPLE|LOST|TOTAL' | head
	echo; echo "\$ perf script -i /tmp/a.data -F tid,time,event --ns | python3 src/hist.py"
	s=$(now_ns)
	perf script -i /tmp/a.data -F tid,time,event --ns 2>/dev/null | python3 src/hist.py > /tmp/a.hist
	e=$(now_ns)
	cat /tmp/a.hist
	echo "post-processing took $(( (e-s)/1000000 )) ms"
} > $OUT/01b-perf-record.txt 2>&1
rm -f /tmp/a.data

BT1='tracepoint:syscalls:sys_enter_read /pid == cpid/ { @start[tid] = nsecs; } tracepoint:syscalls:sys_exit_read /@start[tid]/ { @ns = hist(nsecs - @start[tid]); delete(@start[tid]); }'
{
	echo "\$ bpftrace -e '$BT1' -c '$R'"
	for i in 1 2 3 4; do bpftrace -e "$BT1" -c "$R" 2>/dev/null | rms >> /tmp/b.ms; done
	touch /tmp/marker; sleep 0.01
	s=$(now_ns)
	bpftrace -e "$BT1" -c "$R" > /tmp/b.out 2>&1
	e=$(now_ns)
	cat /tmp/b.out
	rms < /tmp/b.out >> /tmp/b.ms
	echo "whole bpftrace command (last run, includes compiling and loading): $(( (e-s)/1000000 )) ms"
	echo "reader elapsed ms under bpftrace, median min max n: $(stats < /tmp/b.ms)"
	echo "files written to disk during the last run: $(newfiles | wc -l)"; newfiles | head -5
} > $OUT/01c-bpftrace.txt 2>&1
{
	echo "# left: perf record + python (src/hist.py);  right: bpftrace hist()"
	grep '^\[' /tmp/a.hist > /tmp/l; grep '^\[' /tmp/b.out > /tmp/r
	paste -d'#' /tmp/l /tmp/r | awk -F'#' '{printf "%-82s  %s\n", $1, $2}'
} > $OUT/01d-side-by-side.txt 2>&1

# ---- 02: a BPF program by hand -------------------------------------------------------------------
{ echo '$ ./rawbpf count'; ./rawbpf count; } > $OUT/02-rawbpf.txt 2>&1

# ---- 03: the verifier says no --------------------------------------------------------------------
{ echo '$ ./rawbpf bad'; ./rawbpf bad; } > /tmp/bad.txt 2>&1
# keep each verifier log to its last 12 lines
python3 - /tmp/bad.txt > $OUT/03-verifier.txt <<'PY'
import sys, re
txt = open(sys.argv[1]).read()
parts = re.split(r'(?m)^(?=-- verifier log:)', txt)
out = [parts[0]]
for p in parts[1:]:
	head, rest = p.split('\n', 1)
	log, sep, tail = rest.partition('\n==== ')
	lines = log.rstrip('\n').split('\n')
	if len(lines) > 12:
		lines = ['[... %d earlier lines]' % (len(lines) - 12)] + lines[-12:]
	out.append(head + '\n' + '\n'.join(lines) + '\n' + (sep.lstrip('\n') + tail if sep else ''))
print(''.join(out), end='')
PY

# ---- 04: it becomes machine code -----------------------------------------------------------------
./rawbpf hold 6 > /tmp/hold.out 2>&1 &
wait_for /tmp/hold.out attached
ID=$(sed -n 's/.*prog id \([0-9]*\).*/\1/p' /tmp/hold.out)
{
	echo '$ cat /proc/sys/net/core/bpf_jit_enable'; cat /proc/sys/net/core/bpf_jit_enable
	echo; echo '$ ./rawbpf hold 6 &'; cat /tmp/hold.out
	echo; echo "\$ bpftool prog show id $ID"; bpftool prog show id $ID
	echo; echo "\$ bpftool prog dump xlated id $ID"; bpftool prog dump xlated id $ID
	echo; echo "\$ bpftool prog dump jited id $ID"; bpftool prog dump jited id $ID > /tmp/jit 2>&1; cat /tmp/jit | trim 60
	echo; echo "\$ bpftool prog dump jited id $ID opcodes"; bpftool prog dump jited id $ID opcodes 2>&1 | trim 10
	echo; echo '$ objdump -D -b binary -m i386:x86-64 /tmp/jit.bin   (bytes from BPF_OBJ_GET_INFO_BY_FD, jited_prog_insns)'
	objdump -D -b binary -m i386:x86-64 /tmp/jit.bin | sed -n '/<.data>:/,$p' | trim 60
} > $OUT/04-jit.txt 2>&1
wait

# ---- 05: one language for every hook -------------------------------------------------------------
B5='profile:hz:999 /pid == cpid/ { @[usym(reg("ip"))] = count(); }'
{
	echo "\$ bpftrace -e '$B5' -c ./hot"; bpftrace -e "$B5" -c ./hot > /tmp/hot.txt 2>&1; trim 20 < /tmp/hot.txt
	echo; echo "\$ (each address through addr2line -f -e hot, samples summed by function)"
	sed -n 's/^@\[\(0x[0-9a-f]*\)\]: \([0-9]*\)/\1 \2/p' /tmp/hot.txt | while read a n; do echo "$(addr2line -f -e hot $a | head -1) $n"; done |
		awk '{s[$1]+=$2; t+=$2} END{for(f in s) printf "%-8s %5d  %4.1f%%\n", f, s[f], 100*s[f]/t}' | sort -k2 -rn
} > $OUT/05a-profile.txt
B5='kprobe:vfs_read { @[comm] = count(); } interval:s:1 { exit(); }'
{ echo "\$ bpftrace -e '$B5'   (while reader runs)"; ( sleep 0.5; $R >/dev/null ) & bpftrace -e "$B5" 2>&1 | trim 20; wait; } > $OUT/05b-kprobe.txt
B5='kretprobe:vfs_read /pid == cpid/ { @bytes = hist(retval); }'
{ echo "\$ bpftrace -e '$B5' -c '$R'"; bpftrace -e "$B5" -c "$R" 2>&1 | trim 32; } > $OUT/05c-kretprobe.txt
B5='tracepoint:sched:sched_switch /args.prev_pid == (int32)cpid/ { @t = nsecs; @ks = kstack(5); @us = ustack(5); }
tracepoint:sched:sched_switch /args.next_pid == (int32)cpid && @t/ { @offcpu_ns[@ks, @us] = sum(nsecs - @t); @t = 0; }
END { clear(@ks); clear(@us); clear(@t); }'
{ echo "\$ bpftrace -e '$B5' -c ./sleepy"; bpftrace -e "$B5" -c ./sleepy 2>&1 | trim 60; } > $OUT/05d-offcpu.txt
B5="uprobe:$LIBC:malloc /pid == cpid/ { @ = hist(arg0); }"
{ echo "\$ bpftrace -e '$B5' -c ./churn"; bpftrace -e "$B5" -c ./churn 2>&1 | trim 30; } > $OUT/05e-uprobe.txt
{
	echo '$ bpftrace -l | wc -l'; bpftrace -l > /tmp/l.txt 2>&1; wc -l < /tmp/l.txt
	echo; echo "\$ bpftrace -l | cut -d: -f1 | sort | uniq -c | sort -rn"; cut -d: -f1 /tmp/l.txt | sort | uniq -c | sort -rn
} > $OUT/05f-list.txt 2>&1

# ---- 06: price per event -------------------------------------------------------------------------
N=1000000
S="./sysloop $N"
bg() {  # bg OUTFILE CMD... : start a tracer, wait until it is attached
	f=$1; shift; "$@" > $f 2>&1 & BGPID=$!; wait_for $f "Attach\\|attached"; }
row() { r=$(repeat 7 $S); echo "$1|$r"; }
bpftrace -l 'fentry:*getppid*' > /tmp/fe.txt 2>&1
FE=$(grep -m1 'sys_getppid' /tmp/fe.txt); FE=${FE:-fentry:__x64_sys_getppid}
{
	row "bare"
	echo > $T/trace; echo 1 > $T/events/raw_syscalls/sys_enter/enable
	row "tracefs raw_syscalls:sys_enter -> ring buffer"
	echo 0 > $T/events/raw_syscalls/sys_enter/enable; echo > $T/trace
	for P in 'tracepoint:raw_syscalls:sys_enter { @ = count(); }' \
		 'tracepoint:raw_syscalls:sys_enter { @[comm] = count(); }' \
		 'kprobe:__x64_sys_getppid { @ = count(); }' \
		 "$FE { @ = count(); }"; do
		bg /tmp/bg.out bpftrace -e "$P"
		if kill -0 $BGPID 2>/dev/null; then row "bpftrace $P"; kill -INT $BGPID; wait $BGPID
		else echo "bpftrace $P|FAILED: $(head -3 /tmp/bg.out | tr '\n' ' ')"; fi
	done
	bg /tmp/bg.out ./rawbpf hold 60
	row "rawbpf (hand-made counter, all CPUs)"; kill $BGPID; wait $BGPID 2>/dev/null
} > /tmp/price.txt 2>&1
{
	echo "\$ ./sysloop $N   (7 runs per row; ns per getppid() call)"
	printf '%-62s %8s %18s %10s\n' "tracing" "median" "(min-max)" "added ns"
	base=$(head -1 /tmp/price.txt | cut -d'|' -f2 | cut -d' ' -f1)
	awk -F'|' -v b=$base '{ split($2, a, " "); if (a[1] ~ /^[0-9.]+$/) printf "%-62s %8.1f %18s %10.1f\n", $1, a[1], "(" a[2] "-" a[3] ")", a[1]-b; else printf "%-62s %s\n", $1, $2 }' /tmp/price.txt
	echo "added ns = median - bare median ($base); one event per syscall"
	echo; echo "\$ bpftrace -l 'fentry:*getppid*'"; cat /tmp/fe.txt
} > $OUT/06a-price.txt
{
	echo "\$ ./churn 1000000   (1,000,000 malloc/free pairs; ns per pair; 5 runs)"
	echo "bare: median min max n: $(repeat 5 ./churn 1000000)"
	P="uprobe:$LIBC:malloc { @ = hist(arg0); }"
	echo "\$ bpftrace -e '$P' &   (all processes)"
	bg /tmp/bg.out bpftrace -e "$P"
	echo "traced: median min max n: $(repeat 5 ./churn 1000000)"
	kill -INT $BGPID; wait $BGPID
} > $OUT/06b-uprobe-price.txt 2>&1

# ---- 07: what bpftrace generated -----------------------------------------------------------------
P='tracepoint:raw_syscalls:sys_enter { @ = count(); }'
{
	echo "\$ bpftrace --dry-run -d all -e '$P'   (trimmed)"
	bpftrace --dry-run -d all -e "$P" > /tmp/d.txt 2>&1
	echo "stages printed: $(grep -E '^(AST after|LLVM IR)' /tmp/d.txt | tr '\n' ';')"
	echo; echo "[LLVM IR after optimization, the probe function only]"
	sed -n '/^LLVM IR after optimization/,$p' /tmp/d.txt | sed -n '/^define/,/^}/p' | trim 60
} > $OUT/07a-codegen.txt
bg /tmp/bg.out bpftrace -e "$P"
{
	echo "\$ bpftrace -e '$P' &"
	echo; echo '$ bpftool prog show   (programs loaded now)'; bpftool prog show
	MID=$(bpftool map show | awk -F: '/array|hash/ {id=$1} END{print id}')
	echo; echo '$ bpftool map show'; bpftool map show
	echo; echo "\$ bpftool map dump name AT_"; bpftool map dump name AT_ | trim 20
	PID=$(bpftool prog show | awk -F: '/tracepoint/ {id=$1} END{print id}')
	echo; echo "\$ bpftool prog dump xlated id $PID"; bpftool prog dump xlated id $PID | trim 40
} > $OUT/07b-bpftool.txt 2>&1
kill -INT $BGPID; wait $BGPID

# ---- 08: limits ----------------------------------------------------------------------------------
{
	P='BEGIN { while (1) { } }'
	echo "\$ bpftrace -v -e '$P'   (last 12 lines)"; timeout 30 bpftrace -v -e "$P" 2>&1 | tail -n 12
	P='BEGIN { $i = 0; while ($i >= 0) { $i = $i + 1; } exit(); }'
	echo; echo "\$ bpftrace -v -e '$P'   (last 15 lines)"; s=$(now_ns); timeout 30 bpftrace -v -e "$P" > /tmp/w.txt 2>&1; st=$?; e=$(now_ns)
	tail -n 15 /tmp/w.txt; echo "exit status $st after $(( (e-s)/1000000 )) ms"
	P='kprobe:vfs_read { @[str(arg1, 100000)] = count(); }'
	echo; echo "\$ bpftrace -e '$P'"; timeout 10 bpftrace -e "$P" 2>&1 | tail -n 15
} > $OUT/08a-unbounded.txt 2>&1
{
	P='tracepoint:raw_syscalls:sys_enter { printf("%d\n", pid); }'
	printf '%s\n' "\$ bpftrace -e '$P' > /tmp/pf.txt &   then ./sysloop $N x5, then 3 sysloops at once"
	bpftrace -e "$P" > /tmp/pf.txt 2>&1 & BGPID=$!; wait_for /tmp/pf.txt Attach
	echo "printf: ns/call median min max n: $(repeat 5 $S)"
	echo "3 at once, ns/call each: $( ($S & $S & $S & wait) | tr '\n' ' ')"
	kill -INT $BGPID; wait $BGPID
	echo "output: $(wc -c < /tmp/pf.txt) bytes, $(wc -l < /tmp/pf.txt) lines; non-numeric lines:"
	grep -av '^[0-9]*$' /tmp/pf.txt | sort | uniq -c | sort -rn | head -8; rm -f /tmp/pf.txt
	echo "(compare 06a: the count() version)"
	grep -e '^bare' -e 'sys_enter { @ = count' /tmp/price.txt
} > $OUT/08b-lost.txt 2>&1
{
	for f in __vfs_read blk_account_io_start; do
		echo "\$ grep -cw $f /proc/kallsyms"; grep -cw $f /proc/kallsyms
		echo "\$ bpftrace -e 'kprobe:$f { @ = count(); }'"; timeout 10 bpftrace -e "kprobe:$f { @ = count(); } interval:s:1 { exit(); }" 2>&1 | trim 6
	done
} > $OUT/08c-missing.txt 2>&1
echo done
