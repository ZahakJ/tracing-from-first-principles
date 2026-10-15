#!/bin/sh
# kprobes and uprobes: a breakpoint anywhere.
. ../_lib/lib.sh
env_snapshot perf bpftrace gdb objdump python3 lttng
T=/sys/kernel/tracing
K=/sys/kernel/debug/kprobes
KP=./src/kpeek

gcc -O2 -Wall -o sysloop src/sysloop.c
gcc -O2 -Wall -o bp src/bp.c
gcc -O2 -g -Wall -no-pie -o app src/app.c
gcc -O2 -Wall -no-pie -o app_nodbg src/app.c
gcc -O2 -Wall -no-pie -o app_usdt src/app_usdt.c
gcc -O2 -Wall -no-pie -I src -o app_lttng src/app_lttng.c src/tp.c -llttng-ust -ldl 2>lttng-build.err || true

c() { repeat 7 "$@"; }      # "median min max n" of ns per call
say() { echo "tracelab-step: $*" > /dev/kmsg; }
echo 8 > /proc/sys/kernel/printk
reset_tracing() {
	echo 0 > $T/tracing_on; echo > $T/kprobe_events; echo > $T/uprobe_events 2>/dev/null
	echo > $T/trace; echo 1 > $T/tracing_on
}
kopt() { echo $1 > /proc/sys/debug/kprobes-optimization; }
reset_tracing

# ---- 01: kpeek ------------------------------------------------------------------------------------
say 01
{
	echo '$ cat src/kpeek  (the tool)'; sed -n '2,6p' $KP
	echo; echo '$ ./src/kpeek vfs_read 16'; $KP vfs_read 16
} > $OUT/01-kpeek.txt 2>&1

# ---- 02: the kernel patches itself ----------------------------------------------------------------
say 02
FUNC=
for f in __x64_sys_getppid __do_sys_getppid do_sys_openat2; do
	grep -qx "$f" $T/available_filter_functions && ! grep -q " $f\$" $K/blacklist && { FUNC=$f; break; }
done
show() { echo "--- $1"; $KP $FUNC 32; echo "\$ cat $K/list"; cat $K/list; echo; }
{
	echo "# FUNC=$FUNC"
	echo "\$ grep -c . $T/available_filter_functions; grep getppid there and in $K/blacklist"
	grep -c . $T/available_filter_functions
	grep getppid $T/available_filter_functions; grep getppid $K/blacklist || echo "(getppid not in blacklist)"
	grep getppid /proc/kallsyms
	echo; show "(a) untouched"

	echo "\$ echo 'p:tl_entry $FUNC' >> $T/kprobe_events; echo 1 > $T/events/kprobes/tl_entry/enable"
	echo "p:tl_entry $FUNC" >> $T/kprobe_events; echo 1 > $T/events/kprobes/tl_entry/enable
	show "(b) kprobe at function entry"
	echo 0 > $T/events/kprobes/tl_entry/enable; echo "-:tl_entry" >> $T/kprobe_events

	# instruction boundaries from the disassembly, skipping the entry (endbr + fentry nop)
	$KP $FUNC 64 --raw > f.bin
	OFFS=$(objdump -D -b binary -m i386:x86-64 f.bin | grep -E '^ +[0-9a-f]+:' | sed 's/^ *\([0-9a-f]*\):.*/\1/' | while read h; do printf '%d\n' 0x$h; done | awk '$1 >= 9 && $1 < 48')
	echo "candidate offsets (instruction boundaries 9..47): $(echo $OFFS)"
	echo "\$ echo 'p:tl_bad $FUNC+1' >> kprobe_events   (middle of an instruction)"
	echo "p:tl_bad $FUNC+1" >> $T/kprobe_events || echo "  -> write failed, as expected"
	tail -n 3 $T/error_log
	echo
	OFF=; OPTOFF=
	echo "# search with debug.kprobes-optimization=1 (see 09: writing 0 while a probe is optimized hangs)"
	kopt 1
	for o in $OFFS; do
		say "02 try +$o"
		echo "p:tl_off $FUNC+$o" >> $T/kprobe_events 2>/dev/null || { echo "+$o: register failed"; continue; }
		echo 1 > $T/events/kprobes/tl_off/enable
		[ -z "$OFF" ] && OFF=$o
		say "02 wait +$o"; sleep 1.2
		if grep -q OPTIMIZED $K/list; then
			echo "+$o: optimized"; OPTOFF=$o
		else
			echo "+$o: not optimized: $(grep tl_off $K/list; grep "$FUNC+" $K/list)"
		fi
		say "02 remove +$o"
		echo 0 > $T/events/kprobes/tl_off/enable; echo "-:tl_off" >> $T/kprobe_events
		[ -n "$OPTOFF" ] && break
	done
	[ -n "$OPTOFF" ] && OFF=$OPTOFF
	echo "# chosen OFF=$OFF"; echo
	echo "\$ sysctl debug.kprobes-optimization=0   (no probes registered at this moment)"; kopt 0
	echo "\$ echo 'p:tl_off $FUNC+$OFF' >> $T/kprobe_events; echo 1 > .../tl_off/enable"
	echo "p:tl_off $FUNC+$OFF" >> $T/kprobe_events; echo 1 > $T/events/kprobes/tl_off/enable
	show "(c) kprobe at +$OFF, optimization off"
	echo "\$ sysctl debug.kprobes-optimization=1; sleep 1"; kopt 1; sleep 1
	show "(d) the same, optimization on"
	echo 0 > $T/events/kprobes/tl_off/enable; echo "-:tl_off" >> $T/kprobe_events
	say "02 removed"
	show "(e) removed (debug.kprobes-optimization still 1)"
} > $OUT/02-selfpatch.txt 2>&1
echo "$FUNC $OFF $OPTOFF" > func.txt

# ---- 03: using one: who opens what --------------------------------------------------------------
say 03
reset_tracing
{
	for a in 'dfd=%di filename=+0(%si):ustring' 'dfd=$arg1 filename=$arg2:ustring' 'dfd filename:ustring'; do
		echo "\$ echo 'p:tl_try do_sys_openat2 $a' >> kprobe_events"
		if echo "p:tl_try do_sys_openat2 $a" >> $T/kprobe_events; then echo "  accepted"; echo "-:tl_try" >> $T/kprobe_events
		else echo "  rejected:"; tail -n 3 $T/error_log; fi
	done
	echo
	echo "\$ echo 'p:tl_open do_sys_openat2 dfd=%di filename=+0(%si):ustring' >> kprobe_events"
	echo "\$ echo 'r:tl_open_ret do_sys_openat2 ret=\$retval' >> kprobe_events"
	echo 'p:tl_open do_sys_openat2 dfd=%di filename=+0(%si):ustring' >> $T/kprobe_events
	echo 'r:tl_open_ret do_sys_openat2 ret=$retval' >> $T/kprobe_events
	cat $T/kprobe_events
	echo 1 > $T/events/kprobes/tl_open/enable; echo 1 > $T/events/kprobes/tl_open_ret/enable
	echo '$ cat /etc/hostname; cat /etc/nonexistent.conf'
	cat /etc/hostname; cat /etc/nonexistent.conf
	echo 0 > $T/events/kprobes/enable
	echo '$ grep cat- trace'
	grep ' cat-' $T/trace | head -n 40
} > $OUT/03-openat.txt 2>&1

# ---- 04: price per hit (kernel) ---------------------------------------------------------------
say 04
reset_tracing
N=1000000
kev() { echo "$1" >> $T/kprobe_events && echo 1 > $T/events/kprobes/$2/enable; }
krm() { echo 0 > $T/events/kprobes/$1/enable; echo "-:$1" >> $T/kprobe_events; echo > $T/trace; }
{
	echo "ns per getppid() call (sysloop $N), 7 runs: median min max n;  added = median - bare median"
	B=$(c ./sysloop $N); echo "bare                         $B"
	row() { say "04 $1"; R=$(c ./sysloop $N); echo "$1  $R   added $(echo "$R $B" | awk '{printf "%.1f", $1-$5}')   [$(grep "$FUNC" $K/list | sed 's/^[0-9a-f]* *//' | tr '\n' ' ')]"; }
	kopt 1
	kev "p:tl_e $FUNC" tl_e; row "kprobe entry (ftrace)      "; krm tl_e
	kopt 0     # no probe registered now; 1->0 with an optimized probe hangs (09)
	kev "p:tl_o $FUNC+$OFF" tl_o; row "kprobe +$OFF, int3            "
	kopt 1; sleep 1.2; row "kprobe +$OFF, optimized (jmp)"; krm tl_o
	kev "r:tl_r $FUNC" tl_r; row "kretprobe                  "; krm tl_r
	echo; echo "ring buffer did take the events (one run, entry kprobe): "
	kev "p:tl_e $FUNC" tl_e; ./sysloop 100000 >/dev/null; echo "  events/kprobes/tl_e entries: $(grep -c tl_e $T/trace) (buffer overwrites; per-cpu size $(cat $T/buffer_size_kb) kb)"; krm tl_e
} > $OUT/04-kprobe-cost.txt 2>&1

# ---- 05: uprobes ---------------------------------------------------------------------------------
say 05
reset_tracing
ADDR=$(nm app | awk '$3 == "handle" {print $1}')
UOFF=$(readelf -lW app | grep LOAD | while read t off va pa fs ms rest; do
	[ $((0x$ADDR)) -ge $((va)) ] && [ $((0x$ADDR)) -lt $((va + fs)) ] && printf '0x%x\n' $((0x$ADDR - va + off)); done)
P=$(pwd)/app
{
	echo "\$ nm app | grep ' handle\$'"; nm app | grep ' handle$'
	echo "\$ readelf -lW app | grep LOAD"; readelf -lW app | grep LOAD
	echo "file offset of handle = $UOFF"
	echo "\$ objdump -d app --start-address=0x$ADDR --stop-address=\$((0x$ADDR+16))"
	objdump -d app --start-address=0x$ADDR --stop-address=$((0x$ADDR+16)) | grep -E '^ +[0-9a-f]+:'
	echo; echo "\$ echo 'p:tl_handle $P:$UOFF id=%di' >> uprobe_events"
	echo "p:tl_handle $P:$UOFF id=%di" >> $T/uprobe_events
	cat $T/uprobe_events
	echo "md5sum before: $(md5sum app)"
	./app watch > watch1.txt &
	W1=$!
	sleep 1.5; say 05 enable; echo 1 > $T/events/uprobes/tl_handle/enable; echo "[enabled at ~1.5 s]"
	sleep 0.5; ./app watch > watch2.txt & W2=$!
	sleep 1; echo "md5sum during: $(md5sum app)"
	echo "\$ cat uprobe_profile"; cat $T/uprobe_profile
	sleep 1; echo 0 > $T/events/uprobes/tl_handle/enable; echo "[disabled at ~4 s]"
	wait $W1; kill $W2 2>/dev/null; wait $W2
	echo "md5sum after:  $(md5sum app)"
	echo; echo "--- output of the first 'app watch':"; cat watch1.txt
	echo; echo "--- (b) second copy, started at ~2 s while the probe was on (killed when the first ends):"; cat watch2.txt
	echo; echo "--- trace:"; grep tl_handle $T/trace | head -n 6; echo "[$(grep -c tl_handle $T/trace) lines in all]"
	echo "\$ cat uprobe_profile"; cat $T/uprobe_profile
} > $OUT/05-uprobe.txt 2>&1
reset_tracing
UN=1000000
{
	echo "ns per handle() call (app bench), 7 runs: median min max n"
	B=$(c ./app bench 20000000); echo "bare (20M calls)        $B"
	echo "p:tl_handle $P:$UOFF id=%di" >> $T/uprobe_events; echo 1 > $T/events/uprobes/tl_handle/enable
	R=$(c ./app bench $UN); echo "uprobe ($UN calls)      $R   added $(echo "$R $B" | awk '{printf "%.1f", $1-$5}')"
	echo 0 > $T/events/uprobes/tl_handle/enable; echo > $T/uprobe_events; echo > $T/trace
	echo "r:tl_hret $P:$UOFF ret=\$retval" >> $T/uprobe_events; echo 1 > $T/events/uprobes/tl_hret/enable
	R=$(c ./app bench $UN); echo "uretprobe ($UN calls)   $R   added $(echo "$R $B" | awk '{printf "%.1f", $1-$5}')"
	echo 0 > $T/events/uprobes/tl_hret/enable; echo > $T/uprobe_events; echo > $T/trace
	R=$(c ./bp $ADDR ./app bench 20000); echo "ptrace bp.c (20000)     $R   added $(echo "$R $B" | awk '{printf "%.1f", $1-$5}')"
} > $OUT/05-uprobe-cost.txt 2>&1

# ---- 06: USDT ------------------------------------------------------------------------------------
say 06
reset_tracing
{
	echo '$ readelf -n app_usdt | grep -A4 stapsdt'; readelf -n app_usdt | grep -A4 stapsdt
	PC=$(readelf -n app_usdt | awk '/Location:/{print $2; exit}' | tr -d ,)
	echo; echo "\$ objdump -d app_usdt, function handle"
	objdump -d app_usdt | awk '/<handle>:/,/^$/'
	echo "(probe location $PC)"
	echo; echo "\$ bpftrace -l 'usdt:./app_usdt:*'"; bpftrace -l 'usdt:./app_usdt:*'
	echo; echo "\$ bpftrace -e 'usdt:./app_usdt:tracelab:request { @ = count(); }' -c './app_usdt bench 1000000'"
	bpftrace -e 'usdt:./app_usdt:tracelab:request { @ = count(); }' -c './app_usdt bench 1000000' 2>&1 | grep -v '^$'
	echo; echo "ns per call, 5 runs: median min max n"
	B=$(c ./app_usdt bench 20000000); echo "app_usdt, no tracer (20M)    $B"
	A=$(c ./app bench 20000000); echo "app (no probe at all) (20M)  $A"
	R=$(repeat 5 sh -c "bpftrace -q -e 'usdt:./app_usdt:tracelab:request { @ = count(); } END { clear(@); }' -c './app_usdt bench 1000000' | grep -E '^[0-9.]+\$'")
	echo "usdt under bpftrace (1M)     $R   added $(echo "$R $B" | awk '{printf "%.1f", $1-$5}')"
	echo; echo "same nop, same uprobe, but a tracefs event writing to the ring buffer; and the lea of app's handle under bpftrace:"
	UP=$(readelf -n app_usdt | awk '/Location:/{print $2; exit}' | tr -d ,)
	echo "p:tl_nop $(pwd)/app_usdt:$(printf '0x%x' $((UP - 0x400000)))" >> $T/uprobe_events; echo 1 > $T/events/uprobes/tl_nop/enable
	cat $T/uprobe_events
	R=$(c ./app_usdt bench 1000000); echo "tracefs uprobe on the nop (1M) $R   added $(echo "$R $B" | awk '{printf "%.1f", $1-$5}')"
	echo 0 > $T/events/uprobes/tl_nop/enable; echo > $T/uprobe_events; echo > $T/trace
	R=$(repeat 5 sh -c "bpftrace -q -e 'uprobe:./app:handle { @ = count(); } END { clear(@); }' -c './app bench 1000000' | grep -E '^[0-9.]+\$'")
	echo "bpftrace uprobe on app's handle (lea) (1M) $R   added $(echo "$R $A" | awk '{printf "%.1f", $1-$5}')"
} > $OUT/06-usdt.txt 2>&1

# ---- 07: perf probe --------------------------------------------------------------------------------
say 07
reset_tracing
{
	echo '$ perf probe -x ./app handle'; perf probe -x ./app handle
	echo "\$ perf probe -x ./app 'handle id'  (app built with -g)"; perf probe -x ./app 'handle_id=handle id'
	echo "\$ perf probe -x ./app_nodbg 'handle id'  (no -g)"; perf probe -x ./app_nodbg 'handle id'
	echo '$ cat uprobe_events'; cat $T/uprobe_events
	echo '$ perf stat -e probe_app:handle ./app bench 100000'; perf stat -e probe_app:handle ./app bench 100000 2>&1 | grep -E 'probe_app|^[0-9.]+$'
	echo '$ perf probe -d "probe_app:*"'; perf probe -d 'probe_app:*'
	echo '$ cat uprobe_events'; cat $T/uprobe_events; echo
	echo '$ perf probe do_sys_openat2'; perf probe do_sys_openat2
	echo "\$ perf probe 'do_sys_openat2 filename:string'"; perf probe 'do_sys_openat2 filename:string'
	echo '$ cat kprobe_events'; cat $T/kprobe_events
	echo '$ perf record -e probe:do_sys_openat2 -a -o p.data -- cat /etc/hostname'
	perf record -e probe:do_sys_openat2 -a -o p.data -- cat /etc/hostname 2>&1 | tail -n 3
	echo '$ perf script -i p.data | head'; perf script -i p.data | head
	echo '$ perf probe -d "probe:*"'; perf probe -d 'probe:*'
} > $OUT/07-perf-probe.txt 2>&1

# ---- 08: LTTng-UST ---------------------------------------------------------------------------------
say 08
reset_tracing
{
	echo '$ gcc ... app_lttng.c tp.c -llttng-ust -ldl'; cat lttng-build.err | head -n 10
	if [ -x app_lttng ]; then
		B=$(c ./app_lttng bench 20000000); echo "no session (20M)   $B"
		echo '$ lttng-sessiond --daemonize'; lttng-sessiond --daemonize 2>&1 | tail -n 3; sleep 1
		echo '$ lttng create tl --output=/tmp/tl-trace'; lttng create tl --output=/tmp/tl-trace
		echo "\$ lttng enable-event -u 'tracelab:*'"; lttng enable-event -u 'tracelab:*'
		echo '$ lttng start'; lttng start
		R=$(c ./app_lttng bench 1000000)
		echo '$ lttng stop'; lttng stop
		echo "traced (1M)        $R   added $(echo "$R $B" | awk '{printf "%.1f", $1-$5}')"
		echo '$ lttng view | head -n 5'; lttng view 2>&1 | head -n 5
		echo '$ lttng list tl'; lttng list tl 2>&1 | grep -v '^$' | head -n 30
		echo "\$ du -sh /tmp/tl-trace (7 runs x 1M events were emitted)"; du -sh /tmp/tl-trace
		lttng destroy -a >/dev/null 2>&1
	fi
} > $OUT/08-lttng.txt 2>&1
reset_tracing

# ---- 09: writing debug.kprobes-optimization=0 while a probe is optimized -------------------------
# Done last and in the background: on this kernel the write never returns.
{
	kopt 1
	echo "\$ echo 'p:tl_off $FUNC+$OFF' >> kprobe_events; enable; sleep 1.2"
	echo "p:tl_off $FUNC+$OFF" >> $T/kprobe_events; echo 1 > $T/events/kprobes/tl_off/enable; sleep 1.2
	grep tl_off $K/list; grep "$FUNC" $K/list
	echo "\$ echo 0 > /proc/sys/debug/kprobes-optimization &   (then wait 5 s)"
	sh -c 'echo 0 > /proc/sys/debug/kprobes-optimization; echo "write returned"' &
	W=$!; sleep 5
	echo "writer pid $W state: $(grep State /proc/$W/status 2>/dev/null || echo gone)"
	echo "\$ cat /proc/$W/stack"; cat /proc/$W/stack 2>&1 | head -n 8
	echo "\$ cat $K/list"; cat $K/list
	echo "\$ grep kprobe /proc/*/stack (other tasks waiting on the optimizer)"
	grep -l -e kprobe_optimizer -e optimize_kprobe /proc/[0-9]*/stack 2>/dev/null | while read f; do d=${f%/stack}; echo "$(cat $d/comm) $(grep State $d/status)"; grep kprobe $f; done | head -n 20
} > $OUT/09-sysctl-hang.txt 2>&1
say end
exit 0
