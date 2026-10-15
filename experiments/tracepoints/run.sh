# tracepoints: the kernel's own printf.
. ../_lib/lib.sh
env_snapshot perf strace bpftrace trace-cmd
T=/tmp/tp; mkdir -p $T
for p in sysloop sleepy spin wakeup; do gcc -O1 -Wall -o $T/$p src/$p.c; done
cp src/kpeek src/bdiff.py src/switches.py $T/
TR=/sys/kernel/tracing
cd $T

# show FILE CMD... : append "$ CMD" and its stdout+stderr to $OUT/FILE
show() { _f=$1; shift; { echo "\$ $*"; "$@" 2>&1; echo; } >> "$OUT/$_f"; }
# sh_show FILE 'shell text' : same, for a shell command line
sh_show() { { echo "\$ $2"; sh -c "$2" 2>&1; echo; } >> "$OUT/$1"; }
# reset tracefs to quiet
tr_reset() {
	echo 0 > $TR/tracing_on; echo 0 > $TR/events/enable
	echo > $TR/set_event_pid; echo > $TR/trace
	for f in $TR/events/sched/sched_switch/filter $TR/events/sched/sched_wakeup/filter; do echo 0 > $f; done
	echo 1 > $TR/tracing_on
}
tr_reset

echo "tracelab: 1 what exists"
F=01-what-exists.txt
sh_show $F "wc -l < $TR/available_events"
sh_show $F "cut -d: -f1 $TR/available_events | sort | uniq -c | sort -rn | head -15"
sh_show $F "ls $TR/events | wc -l   # subsystems (plus enable, header_* files)"
sh_show $F "ls $TR/events/sched/sched_switch/"
sh_show $F "cat $TR/events/syscalls/sys_enter_openat/format"
sh_show $F "cat $TR/events/sched/sched_switch/format"

echo "tracelab: 2 by hand"
F=02-by-hand.txt
cd $TR
for path in /etc/hostname /etc/no-such-file; do
	tr_reset
	{
	echo "# in $TR"
	echo "# 99999 is no process: until the sh below puts its own pid there, nothing is recorded"
	for c in "echo 99999 > set_event_pid" \
		 "echo 1 > events/syscalls/sys_enter_openat/enable" \
		 "echo 1 > events/syscalls/sys_exit_openat/enable" \
		 "echo > trace" \
		 "sh -c 'echo \$\$ > set_event_pid; exec cat $path'" \
		 "echo 0 > events/syscalls/sys_enter_openat/enable" \
		 "echo 0 > events/syscalls/sys_exit_openat/enable" \
		 "cat trace" \
		 "echo > set_event_pid"; do
		echo "\$ $c"; sh -c "$c" 2>&1
	done
	echo
	} >> $OUT/$F
done
tr_reset
cd $T

echo "tracelab: 3 five bytes of nothing"
F=03-static-key.txt
: > $OUT/$F
for pair in __schedule:sched/sched_switch kfree:kmem/kfree try_to_wake_up:sched/sched_waking kmem_cache_free:kmem/kmem_cache_free; do
	fn=${pair%%:*}; ev=${pair#*:}
	{
	echo "=== function $fn, event $ev"
	echo "\$ ./kpeek $fn $fn.0      # event off"
	./kpeek $fn $fn.0
	echo "\$ echo 1 > $TR/events/$ev/enable"; echo 1 > $TR/events/$ev/enable
	echo "\$ ./kpeek $fn $fn.1      # event on"
	./kpeek $fn $fn.1
	echo "\$ echo 0 > $TR/events/$ev/enable"; echo 0 > $TR/events/$ev/enable
	echo "\$ ./kpeek $fn $fn.2      # event off again"
	./kpeek $fn $fn.2
	A=0x$(awk -v f=$fn '$3==f{print $1; exit}' /proc/kallsyms)
	for st in 0 1 2; do
		objdump -D -b binary -m i386:x86-64 --adjust-vma=$A $fn.$st | grep '^ *[0-9a-f]*:' > $fn.$st.s
	done
	echo "\$ ./bdiff.py $A $fn.0 $fn.1 $fn.0.s $fn.1.s     # off -> on, with objdump of each"
	./bdiff.py $A $fn.0 $fn.1 $fn.0.s $fn.1.s | tee $fn.d
	echo "\$ # the call targets in the changed instructions, looked up in /proc/kallsyms"
	for a in $(grep -o 'call  *0x[0-9a-f]*' $fn.d | awk '{print $2}' | sort -u); do
		echo "  $a = $(grep "^${a#0x} " /proc/kallsyms | awk '{print $3}' | head -1)"
	done
	echo "\$ ./bdiff.py $A $fn.1 $fn.2     # on -> off"
	./bdiff.py $A $fn.1 $fn.2
	echo "\$ cmp $fn.0 $fn.2 && echo identical"
	cmp $fn.0 $fn.2 && echo identical
	echo
	} >> $OUT/$F 2>&1
done
tr_reset

echo "tracelab: 4 why did it wait"
F=04-sleepy.txt
tr_reset
E=$TR/events/sched
{
echo "\$ sh -c 'P=\$\$; echo \"prev_pid==\$P || next_pid==\$P\" > $E/sched_switch/filter; echo \"pid==\$P\" > $E/sched_wakeup/filter; echo \"pid==\$P\" > $E/sched_waking/filter; echo 1 > $E/sched_switch/enable; echo 1 > $E/sched_wakeup/enable; echo 1 > $E/sched_waking/enable; exec ./sleepy'"
sh -c 'P=$$; echo $P > /tmp/tp/sleepy.pid; echo "prev_pid==$P || next_pid==$P" > '$E'/sched_switch/filter; echo "pid==$P" > '$E'/sched_wakeup/filter; echo "pid==$P" > '$E'/sched_waking/filter; echo 1 > '$E'/sched_switch/enable; echo 1 > '$E'/sched_wakeup/enable; echo 1 > '$E'/sched_waking/enable; exec ./sleepy'
} > $OUT/$F 2>&1
echo 0 > $E/enable
for f in sched_switch sched_wakeup sched_waking; do echo 0 > $E/$f/filter; done
grep -v '^#' $TR/trace > sleepy.trace
P=$(cat sleepy.pid)
{
echo
echo "\$ grep -v '^#' trace     # pid $P, $(wc -l < sleepy.trace) lines"
cat sleepy.trace | head -40
[ $(wc -l < sleepy.trace) -gt 40 ] && echo "[... $(($(wc -l < sleepy.trace) - 40)) more lines]"
echo
echo "\$ ./switches.py $P < trace"
./switches.py $P < sleepy.trace | awk 'NR<=31 || /^total/' 
echo "  (one row per switch-out; rows after the first 30 are omitted, totals are over all)"
} >> $OUT/$F 2>&1
tr_reset

echo "tracelab: 5 price per event"
F=05-price.txt
NB=2000000; NP=200000; NS=20000
row() { # label N cmd...
	_l=$1; _n=$2; shift 2
	r=$(repeat 5 "$@" ./sysloop $_n)
	echo "$_l|$_n|$r" >> price.raw
}
: > price.raw
row "bare" $NB env
echo 1 > $TR/events/raw_syscalls/sys_enter/enable; echo 1 > $TR/events/raw_syscalls/sys_exit/enable
row "tracefs raw_syscalls:sys_enter+sys_exit on" $NB env
echo 0 > $TR/events/raw_syscalls/enable; echo > $TR/trace
echo 1 > $TR/events/syscalls/sys_enter_getppid/enable
row "tracefs syscalls:sys_enter_getppid only" $NB env
echo 0 > $TR/events/syscalls/sys_enter_getppid/enable; echo > $TR/trace
echo 1 > $TR/events/syscalls/sys_enter_openat/enable
row "tracefs sys_enter_openat on (not getppid)" $NB env
echo 0 > $TR/events/syscalls/sys_enter_openat/enable; echo > $TR/trace
row "perf stat -e raw_syscalls:sys_enter" $NB perf stat -e raw_syscalls:sys_enter -o /dev/null --
row "perf record -e raw_syscalls:sys_enter" $NB perf record -q -e raw_syscalls:sys_enter -o $T/x --
row "perf trace -o /dev/null" $NP perf trace -o /dev/null --
row "perf trace -s -o /dev/null" $NP perf trace -s -o /dev/null --
row "strace -o /dev/null" $NS strace -o /dev/null
row "strace -c -o /dev/null" $NS strace -c -o /dev/null
{
echo "ns per getppid() from ./sysloop N (it times its own loop); 5 runs each"
echo "added = median - bare median; factor = median / bare median"
echo
awk -F'|' 'NR==1{split($3,b," "); base=b[1]} {split($3,s," "); printf "%-44s N=%-8s %9.1f (%s-%s)  added %9.1f  x%.1f\n", $1, $2, s[1], s[2], s[3], s[1]-base, s[1]/base}' price.raw
echo
echo "\$ perf record -e raw_syscalls:sys_enter -o x ./sysloop $NB"
perf record -e raw_syscalls:sys_enter -o $T/x ./sysloop $NB 2>&1
echo "\$ ls -l x"; ls -l $T/x | awk '{print $5, "bytes"}'
echo "\$ perf report -i x --stats | grep -i -e 'sample' -e lost"
perf report -i $T/x --stats 2>&1 | grep -i -e sample -e lost | head
echo "\$ perf stat -e context-switches -- perf trace -o /dev/null ./sysloop $NP    # switches of perf trace AND sysloop together"
perf stat -e context-switches -- perf trace -o /dev/null ./sysloop $NP 2>&1 | grep -e context -e elapsed
echo "\$ perf stat -e context-switches -- strace -o /dev/null ./sysloop $NS"
perf stat -e context-switches -- strace -o /dev/null ./sysloop $NS 2>&1 | grep -e context -e elapsed
echo "\$ perf trace -v -o /dev/null ./sysloop 1000 2>&1 | grep -i -e bpf -e augment | head -5"
perf trace -v -o /dev/null ./sysloop 1000 2>&1 | grep -i -e bpf -e augment | head -5
echo "\$ perf stat -e raw_syscalls:sys_enter ./sysloop $NB"
perf stat -e raw_syscalls:sys_enter ./sysloop $NB 2>&1 | grep -v '^$'
} > $OUT/$F 2>&1
rm -f $T/x

echo "tracelab: 6 perf trace as strace"
F=06-perf-trace.txt
sh_show $F "perf trace cat /etc/hostname 2>&1 | tail -25"
sh_show $F "strace cat /etc/hostname 2>&1 | tail -25"
sh_show $F "perf trace -s cat /etc/hostname 2>&1 | grep -v '^$'"
( sleep 0.5; dd if=/dev/vdd of=/dev/null bs=1M count=200 iflag=direct 2>/dev/null; sleep 0.3; sleep 0.2 ) &
sh_show $F "perf trace -a --duration 50 -- sleep 2 2>&1 | head -30   # meanwhile in the background: dd from /dev/vdd, sleep 0.3, sleep 0.2"
wait

echo "tracelab: 7 perf sched"
F=07-perf-sched.txt
{
echo "\$ perf sched record -o sched.data -- sh -c 'taskset -c 0 ./spin 3 & taskset -c 0 ./spin 3 & taskset -c 0 ./wakeup 200; wait'"
perf sched record -o sched.data -- sh -c 'taskset -c 0 ./spin 3 & taskset -c 0 ./spin 3 & taskset -c 0 ./wakeup 200; wait' 2>&1
echo
echo "for comparison, wakeup alone without the spinners:"
echo "\$ taskset -c 0 ./wakeup 200"; taskset -c 0 ./wakeup 200
echo
echo "\$ perf sched latency -i sched.data | head -20"
perf sched latency -i sched.data 2>&1 | grep -v '^$' | head -20
echo
echo "\$ perf sched timehist -i sched.data | grep -e wakeup -e spin -e 'wait time' -e '\[ms\]' -e '\-\-\-' | head -30"
perf sched timehist -i sched.data 2>&1 | grep -e wakeup -e spin -e 'wait time' -e '\[ms\]' -e '\-\-\-\-' | head -30
} > $OUT/$F 2>&1
rm -f sched.data

echo "tracelab: 8 everything on"
F=08-firehose.txt
tr_reset
{
echo "\$ cat buffer_size_kb; nproc"; cat $TR/buffer_size_kb; nproc
echo "\$ echo 1 > events/enable    # $(grep -c . $TR/available_events) events"
echo 1 > $TR/events/enable
s=$(now_ns)
timeout 2 sh -c 'while :; do find / -xdev >/dev/null 2>&1; done' &
timeout 2 dd if=/dev/zero of=/dev/null bs=1 2>/dev/null &
wait
e=$(now_ns)
echo 0 > $TR/events/enable
echo "  (workload: find / -xdev in a loop + dd bs=1 from /dev/zero, both for 2 s, run in parallel)"
for c in $TR/per_cpu/cpu*; do echo "\$ cat per_cpu/$(basename $c)/stats"; cat $c/stats; done | head -60
echo
for c in $TR/per_cpu/cpu*; do cat $c/stats; done | awk -v ns=$((e - s)) '
	/^entries/{en+=$2} /^overrun/{ov+=$2} /^bytes/{by+=$2} /^dropped/{dr+=$3}
	END{ sec=ns/1e9; tot=en+ov;
	printf "elapsed %.3f s\nentries still in buffer %d, overwritten (overrun) %d, total recorded %d (%.0f%% lost to overwriting)\n", sec, en, ov, tot, 100*ov/tot;
	printf "events per second: %.0f\n", tot/sec;
	printf "bytes in buffer %d = %.1f bytes/event; estimated bytes per second %.0f (%.1f MB/s)\n", by, by/en, tot/sec*by/en, tot/sec*by/en/1e6 }'
echo
echo "\$ the 10 most frequent events still in the buffer"
grep -v '^#' $TR/trace | awk '{for(i=1;i<=NF;i++) if ($i ~ /:$/ && $(i-1) ~ /^[0-9]+\.[0-9]+:$/) {print $i; break}}' | sort | uniq -c | sort -rn | head -10
} > $OUT/$F 2>&1
tr_reset

echo "tracelab: 9 how perf attaches"
F=09-perf-attach.txt
{
echo "\$ strace -f -e trace=perf_event_open -o st.txt perf stat -e sched:sched_switch true"
strace -f -e trace=perf_event_open -o st.txt perf stat -e sched:sched_switch true 2>&1 | grep -v '^$'
echo "\$ grep PERF_TYPE_TRACEPOINT st.txt | head -3   # $(grep -c perf_event_open st.txt) perf_event_open calls in all"
grep PERF_TYPE_TRACEPOINT st.txt | head -3 | cut -c1-400
echo "\$ # what perf trace and perf record ask for: wake the reader after how many events?"
for c in "perf trace -o /dev/null true" "perf record -e raw_syscalls:sys_enter -o $T/y true"; do
	echo "\$ strace -f -e trace=perf_event_open -o st2.txt $c; grep -o -e 'wakeup_events=[0-9]*' -e 'wakeup_watermark=[0-9]*' -e 'watermark=[0-9]' -e 'type=[A-Z_]*' st2.txt | sort | uniq -c"
	strace -f -e trace=perf_event_open -o st2.txt $c >/dev/null 2>&1
	grep -o -e 'wakeup_events=[0-9]*' -e 'wakeup_watermark=[0-9]*' -e 'watermark=[0-9]' -e 'type=[A-Z_]*' st2.txt | sort | uniq -c
done
echo "\$ cat $TR/events/sched/sched_switch/id"
cat $TR/events/sched/sched_switch/id
} > $OUT/$F 2>&1
echo "tracelab: done"
