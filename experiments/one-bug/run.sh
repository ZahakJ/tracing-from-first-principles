# one-bug: one program, one bug, several tracers.
# ingest spends ~1 ms of CPU per record in checksum() (the red herring)
# and then waits for fdatasync() of an audit log on /dev/vdd (the bug).
. ../_lib/lib.sh
env_snapshot strace ltrace perf bpftrace blktrace valgrind heaptrack uftrace gprof
EXP=$(pwd)
W=$EXP/work; mkdir -p "$W"

# trim N : keep the first N lines of stdin, say how many were dropped
trim() { awk -v n="$1" 'NR<=n{print} END{if(NR>n) printf "[... %d more lines]\n", NR-n}'; }
# tm5 N CMD... : run CMD N times under /usr/bin/time; print each run, then
#   median/min/max of real, user, sys (seconds) and real/(user+sys)
tmN() {
	_n=$1; shift; : > "$W/tm"
	_i=0; while [ $_i -lt $_n ]; do
		/usr/bin/time -a -o "$W/tm" -f "%e %U %S" "$@" >/dev/null 2>&1
		_i=$((_i+1))
	done
	awk '{printf "  run %d: real %.2f  user %.2f  sys %.2f\n", NR, $1, $2, $3}' "$W/tm"
	for c in 1 2 3; do awk -v c=$c '{print $c}' "$W/tm" | stats; done | {
		read rm rmin rmax n; read um umin umax n; read sm smin smax n
		echo "  real  median $rm  min $rmin  max $rmax  (n=$n)"
		echo "  user  median $um  min $umin  max $umax"
		echo "  sys   median $sm  min $smin  max $smax"
		echo "$rm $um $sm" | awk '{printf "  real / (user+sys) = %.2f / %.2f = %.1fx  (medians)\n", $1, $2+$3, $1/($2+$3)}'
		echo "$rm $um $sm" > "$W/last"
	}
}

# annotate FILE BIN : bpftrace prints user stacks as bare addresses here
#   (the process has exited before bpftrace resolves them). With ASLR off
#   the PIE loads at 0x555555554000; libc's base comes from LD_DEBUG=files.
#   Append "<- symbol" to each address line.
annotate() {
	_lb=$(LD_DEBUG=files ./ingest -n 1 2>&1 | awk '/file=libc.so.6.*generating link map/{f=1; next} f&&/base:/{for(i=1;i<NF;i++) if($i=="base:") print $(i+1); exit}')
	while IFS= read -r _l; do
		_a=$(echo "$_l" | sed -n 's/^ *\(0x[0-9a-f]*\)$/\1/p')
		if [ -n "$_a" ] && [ $((_a)) -ge $((0x555555554000)) ] && [ $((_a)) -lt $((0x555555654000)) ]; then
			_o=$(printf '0x%x' $((_a - 0x555555554000)))
			echo "$_l    <- $2+$_o $(addr2line -f -e "$2" "$_o" | head -1)"
		elif [ -n "$_a" ] && [ -n "$_lb" ] && [ $((_a)) -ge $((_lb)) ]; then
			echo "$_l    <- libc.so.6+$(printf '0x%x' $((_a - _lb)))"
		else
			echo "$_l"
		fi
	done < "$1"
}

echo "tracelab: setup"
mkfs.ext4 -q -F -L onebug /dev/vdd && mount -t ext4 /dev/vdd /mnt || exit 1
mount | grep vdd > "$OUT/00-setup.txt"
echo "vdd scheduler: $(cat /sys/block/vdd/queue/scheduler)" >> "$OUT/00-setup.txt"
cd "$W"
CF="-O2 -g -fno-omit-frame-pointer"
gcc $CF -o ingest ../src/ingest.c
gcc $CF -DFASTSUM -o ingest_fastsum ../src/ingest.c
gcc $CF -pg -o ingest_pg ../src/ingest.c
echo "builds: gcc $CF [-DFASTSUM | -pg] ../src/ingest.c" >> "$OUT/00-setup.txt"

echo "tracelab: $(date +%T) 01 time"
{
	echo '$ /usr/bin/time -f "%e %U %S" ./ingest     (5 runs; real user sys in seconds)'
	tmN 5 ./ingest
} > "$OUT/01-time.txt"
cp "$W/last" "$W/base"	# median real user sys of ./ingest

echo "tracelab: $(date +%T) 02 perf"
{
	echo '$ perf record -g ./ingest ; perf report --stdio --no-children | head -40'
	perf record -g -o perf.data ./ingest 2>&1 | grep -v '^$'
	perf report -i perf.data --stdio --no-children 2>/dev/null | head -40
	echo "[trimmed to 40 lines]"
	echo
	echo "--- is checksum the problem? make it ~10x cheaper (-DFASTSUM) and time both"
	echo '$ /usr/bin/time -f "%e %U %S" ./ingest_fastsum     (5 runs)'
	tmN 5 ./ingest_fastsum
	echo
	read br bu bs < base; read fr fu fs < last
	echo "             real     user    sys"
	echo "ingest       $br     $bu    $bs     (medians from 01-time.txt)"
	echo "ingest_fast  $fr     $fu    $fs"
	echo "$br $fr $bu $fu" | awk '{printf "user time cut by %.2f s (%.0f%%); wall time cut by %.2f s (%.0f%%)\n", $3-$4, 100*($3-$4)/$3, $1-$2, 100*($1-$2)/$1}'
} > "$OUT/02-perf-wrong-lead.txt" 2>&1

echo "tracelab: $(date +%T) 03 strace"
{
	echo '$ strace -c -w ./ingest'
	strace -c -w ./ingest 2>&1
	echo
	echo '$ strace -c ./ingest'
	strace -c ./ingest 2>&1
	echo
	echo "\$ strace -T -e trace=write,fdatasync ./ingest 2>&1 | sed -n '20,30p'"
	strace -T -e trace=write,fdatasync ./ingest 2>&1 | sed -n '20,30p'
} > "$OUT/03-strace.txt"

echo "tracelab: $(date +%T) 04 who calls"
{
	echo '$ strace -k -e trace=fdatasync ./ingest 2>&1 | head -20'
	strace -k -e trace=fdatasync ./ingest 2>&1 | head -20
	echo
	echo "\$ bpftrace -e 'tracepoint:syscalls:sys_enter_fdatasync /pid == cpid/ { @[ustack] = count(); }' -c ./ingest"
	echo 0 > /proc/sys/kernel/randomize_va_space
	bpftrace -e 'tracepoint:syscalls:sys_enter_fdatasync /pid == cpid/ { @[ustack] = count(); }' -c ./ingest 2>&1 | grep -v '^$' > us.txt
	echo "[run with ASLR off (randomize_va_space=0) so the addresses can be resolved afterwards; '<-' annotations added by run.sh, not bpftrace]"
	annotate us.txt ./ingest
	echo 2 > /proc/sys/kernel/randomize_va_space
	echo
	echo '$ ltrace -c ./ingest'
	ltrace -c ./ingest 2>&1
} > "$OUT/04-who-calls.txt"

echo "tracelab: $(date +%T) 05 off-cpu"
{
	echo '$ bpftrace offcpu.bt -c ./ingest     (top 3 stacks by off-CPU microseconds)'
	sed -n '/^tracepoint/,$p' ../offcpu.bt | sed 's/^/    /'
	echo
	echo 0 > /proc/sys/kernel/randomize_va_space
	bpftrace ../offcpu.bt -c ./ingest > off.txt 2>&1
	echo "[ASLR off for this run; '<-' annotations added by run.sh, not bpftrace]"
	grep -v '^$' off.txt > off2.txt; annotate off2.txt ./ingest | trim 80
	echo 2 > /proc/sys/kernel/randomize_va_space
	echo
	read br bu bs < base
	tot=$(awk '/^@total_off_us/{print $2}' off.txt)
	echo "$tot $br $bu $bs" | awk '{printf "total off-CPU (bpftrace): %.2f s;  real - user - sys (01 medians): %.2f - %.2f - %.2f = %.2f s\n", $1/1e6, $2, $3, $4, $2-$3-$4}'
} > "$OUT/05-offcpu.txt"

echo "tracelab: $(date +%T) 06 perf trace"
{
	echo '$ perf trace -s ./ingest'
	perf trace -s ./ingest 2>&1 | grep -v '^$'
	echo
	echo "wall time of one run each (ms):"
	echo "  perf trace -s -o /dev/null ./ingest : $(wall_ms perf trace -s -o /dev/null ./ingest)"
	echo "  strace -c -w ./ingest               : $(wall_ms strace -c -w ./ingest)"
	echo "  ./ingest                            : $(wall_ms ./ingest)"
} > "$OUT/06-perf-trace.txt"

echo "tracelab: $(date +%T) 07 blktrace"
{
	echo '$ blktrace -d /dev/vdd -o bt -D bt &  ./ingest -n 100 ; kill -INT blktrace'
	echo '$ blkparse -i bt -D bt -d bt.bin -O ; btt -i bt.bin'
	mkdir -p bt; sync; echo 3 > /proc/sys/vm/drop_caches
	blktrace -d /dev/vdd -o bt -D bt > bt.log 2>&1 &
	BP=$!; sleep 1
	/usr/bin/time -f "  traced run: real %e s  user %U  sys %S  (-n 100)" ./ingest -n 100
	sync; sleep 1; kill -INT $BP; wait $BP
	cat bt.log | trim 5
	blkparse -i bt -D bt -d bt.bin -O > /dev/null 2>&1
	btt -i bt.bin > btt.txt 2>&1
	echo "--- btt, first table (ALL rows):"
	awk '/^==================== All Devices/{p=1} p' btt.txt | sed -n '1,12p'
	echo
	echo '--- requests by process, from $ blkparse -i bt -D bt -f "%a %C %d\n"'
	echo "    (Q = queued by that process; RWBS F=flush/preflush, W=write, S=sync, M=meta, FUA)"
	blkparse -i bt -D bt -f "%a|%C|%d\n" 2>/dev/null | awk -F'|' '$1=="Q"{c[$2" "$3]++} END{for(k in c) printf "  %6d  Q  %s\n", c[k], k}' | sort -rn
	blkparse -i bt -D bt -f "%a|%C|%d\n" 2>/dev/null | awk -F'|' '$1=="Q"{q++} $1=="D"{d++} $1=="C"{c++} END{printf "  totals: Q %d  D %d  C %d  -> Q per fdatasync (100 calls) = %.2f\n", q, d, c, q/100}'
	echo
	echo
	echo "--- one fdatasync, from the middle of the run: \$ blkparse -i bt -D bt -f '%T.%t %a %C %d %S+%n\\n' (lines for one cycle)"
	blkparse -i bt -D bt -f "%T.%9t %a %C %d %S+%n\n" 2>/dev/null | grep -E ' [QDC] ' | awk '$3=="ingest" && $2=="Q" {n++} n==50' | head -12
	echo
	echo "--- cache flushes (RWBS FN: no Q event, so btt's Q2C/D2C above leave them out); D->C paired in order"
	blkparse -i bt -D bt -f "%T.%9t %a %C %d\n" 2>/dev/null | awk '$4=="FN" && $2=="D"{d=$1} $4=="FN" && $2=="C" && d{t=$1-d; s+=t; n++; if(t>mx)mx=t; if(!mn||t<mn)mn=t; d=0} END{printf "  flushes: %d (%.2f per fdatasync)  D2C avg %.3f ms  min %.3f  max %.3f  total %.3f s\n", n, n/100, 1000*s/n, 1000*mn, 1000*mx, s}'
	echo "vdd write_cache: $(cat /sys/block/vdd/queue/write_cache)   fua: $(cat /sys/block/vdd/queue/fua 2>/dev/null)"
	echo
	echo '$ bpftrace jbd2off.bt -c "./ingest -n 100"     (where the journal thread waits; top 3)'
	bpftrace ../jbd2off.bt -c "./ingest -n 100" 2>&1 | grep -v -e '^$' -e WARN -e '^/args'
	echo
	echo '$ strace -c -w -e trace=fdatasync ./ingest -n 100     (no blktrace; for the per-call time)'
	strace -c -w -e trace=fdatasync ./ingest -n 100 2>&1
} > "$OUT/07-blktrace.txt" 2>&1

echo "tracelab: $(date +%T) 08 fix"
{
	echo '$ /usr/bin/time -f "%e %U %S" ./ingest --batch     (5 runs)'
	tmN 5 ./ingest --batch
	read br bu bs < base; read fr fu fs < last
	echo "$br $fr" | awk '{printf "  ./ingest median real %.2f s  ->  ./ingest --batch %.2f s  (%.0fx faster)\n", $1, $2, $1/$2}'
	echo
	echo '$ strace -c -w ./ingest --batch'
	strace -c -w ./ingest --batch 2>&1
} > "$OUT/08-fix.txt"

echo "tracelab: $(date +%T) 09 overhead"
ov() {	# ov LABEL CMD... : 3 runs, median wall ms
	_lab=$1; shift
	_r=$(repeat_wall 3 "$@")
	echo "$_lab|$_r" >> ov.txt
}
: > ov.txt
ov "./ingest (bare)" ./ingest
ov "strace -o /dev/null" strace -o /dev/null ./ingest
ov "strace -c" strace -c -o /dev/null ./ingest
ov "perf record -g" perf record -g -o perf2.data ./ingest
ov "perf trace -s -o /dev/null" perf trace -s -o /dev/null ./ingest
ov "bpftrace offcpu.bt" bpftrace ../offcpu.bt -c ./ingest
ov "ltrace -c -o /dev/null" ltrace -c -o /dev/null ./ingest
ov "./ingest_pg (bare, -pg build)" ./ingest_pg
ov "uftrace record ./ingest_pg" uftrace record -d uft.data ./ingest_pg
ov "./ingest -n 30 (bare)" ./ingest -n 30
ov "valgrind --tool=callgrind, -n 30" valgrind --tool=callgrind --callgrind-out-file=/dev/null ./ingest -n 30
{
	echo "wall time of each command, 3 runs, median (min max) in ms; slowdown = median / bare median"
	echo "(N=300 default; callgrind at N=30 against a bare N=30 run)"
	echo
	awk -F'|' '
		{ split($2, a, " "); lab[NR]=$1; med[NR]=a[1]; mn[NR]=a[2]; mx[NR]=a[3] }
		END {
			printf "%-36s %10s %10s %10s %8s\n", "command", "median", "min", "max", "slowdown"
			for (i = 1; i <= NR; i++) {
				base = (lab[i] ~ /-n 30/) ? med[10] : med[1]
				printf "%-36s %10.1f %10.1f %10.1f %7.2fx\n", lab[i], med[i], mn[i], mx[i], med[i]/base
			}
		}' ov.txt
} > "$OUT/09-overhead.txt"

echo "tracelab: $(date +%T) 10 wrong kind"
{
	echo '$ heaptrack ./ingest   (summary lines)'
	heaptrack -o ht ./ingest > ht.log 2>&1
	grep -v '^$' ht.log | grep -i -E 'alloc|leak|peak|total|heaptrack stats' | trim 12
	_ht=$(ls ht*.zst ht*.gz 2>/dev/null | head -1)
	echo "\$ heaptrack_print $_ht | grep -E '^(total runtime|calls to allocation|temporary|peak heap|peak RSS|total memory leaked)'"
	heaptrack_print "$_ht" 2>&1 | grep -E "^(total runtime|calls to allocation|temporary|peak heap|peak RSS|total memory leaked)"
	echo
	echo '$ ./ingest_pg ; gprof -b -p ingest_pg gmon.out | head -10'
	rm -f gmon.out; ./ingest_pg
	gprof -b -p ingest_pg gmon.out 2>&1 | head -10
	echo
	echo "--- the same, built with -fno-ipa-cp (so checksum is not renamed checksum.constprop.0)"
	gcc $CF -pg -fno-ipa-cp -o ingest_pg2 ../src/ingest.c
	echo '$ nm ingest_pg | grep checksum ; nm ingest_pg2 | grep checksum'
	nm ingest_pg | grep checksum; nm ingest_pg2 | grep checksum
	echo '$ ./ingest_pg2 ; gprof -b -p ingest_pg2 gmon.out | head -10'
	rm -f gmon.out; ./ingest_pg2
	gprof -b -p ingest_pg2 gmon.out 2>&1 | head -10
} > "$OUT/10-wrong-kind.txt" 2>&1

umount /mnt
echo "tracelab: $(date +%T) done"
