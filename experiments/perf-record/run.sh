# perf record: interrupt the program and ask where it is.
. ../_lib/lib.sh
env_snapshot perf
MAXRATE0=$(cat /proc/sys/kernel/perf_event_max_sample_rate)
D=$(pwd); T=/tmp/pr; mkdir -p $T
CF="-O2 -g -Wall"
gcc $CF -o $T/hot src/hot.c
gcc $CF -o $T/sum2d src/sum2d.c
gcc $CF -o $T/skid src/skid.c
gcc $CF -o $T/callers-nofp src/callers.c
gcc $CF -fno-omit-frame-pointer -o $T/callers-fp src/callers.c
gcc $CF -fno-omit-frame-pointer -mno-omit-leaf-frame-pointer -o $T/callers-fpleaf src/callers.c
gcc $CF -o $T/sleepy src/sleepy.c
cd $T

# show FILE CMD... : append "$ CMD" and its stdout+stderr to $OUT/FILE
show() { _f=$1; shift; { echo "\$ $*"; "$@" 2>&1; echo; } >> "$OUT/$_f"; }
# showsh FILE 'PIPELINE' : same, for a shell pipeline
showsh() { _f=$1; shift; { echo "\$ $*"; sh -c "$*" 2>&1; echo; } >> "$OUT/$_f"; }
# trim N : keep N lines of stdin, say how many were dropped
trim() { awk -v n=$1 'NR<=n{print} END{if(NR>n) printf "[... %d more lines]\n", NR-n}'; }
size() { stat -c %s "$1" | awk '{printf "%.2f MB (%d bytes)", $1/1048576, $1}'; }
# span FILE : ms between the first and last sample (how long the workload ran under perf)
span() { perf script -F time -i "$1" 2>/dev/null | awk 'NR==1{a=$1+0} {b=$1+0} END{printf "%.1f\n", (b-a)*1000}'; }
# spanrun ARGS... : perf record ARGS into junk.data, print the span
spanrun() { perf record -o junk.data "$@" >/dev/null 2>&1; span junk.data; }
# rec FILE ARGS... : perf record, keep only perf's own messages
rec() { _o=$1; shift; perf record -o "$_o" "$@" >/dev/null 2>$T/rec.err; _s=$?; grep -v '^$' $T/rec.err; return $_s; }

echo "tracelab: 1 hot"
F=01-hot-report.txt
{
	echo "\$ perf record -o hot.data ./hot"; rec hot.data ./hot
	echo "perf.data size: $(size hot.data)"; echo
	echo "\$ perf report --stdio -i hot.data   (blank lines dropped)"
	perf report --stdio -i hot.data 2>&1 | grep -v '^$' | trim 20
	echo; echo "expected from the source: six 60%, three 30%, one 10%"
} > $OUT/$F

echo "tracelab: 2 sample"
F=02-what-a-sample-is.txt
show $F perf evlist -v -i hot.data
showsh $F "perf script -i hot.data -F comm,pid,tid,time,ip,sym,period | head -15"
showsh $F "perf script -i hot.data -F period,ip,sym | head -12"
showsh $F "perf report -D -i hot.data | grep -m1 -B7 -A2 PERF_RECORD_SAMPLE"

echo "tracelab: 3 sum2d"
F=03-any-event.txt
show $F perf stat -e cycles,instructions,L1-dcache-loads,L1-dcache-load-misses,LLC-load-misses,cache-misses ./sum2d
MISS=L1-dcache-load-misses
perf stat -e $MISS ./sum2d 2>&1 | grep -q 'not supported\|not counted' && MISS=cache-misses
for e in cycles $MISS; do
	{ echo "\$ perf record -e $e -o sum2d-$e.data ./sum2d"; rec sum2d-$e.data -e $e ./sum2d; echo; } >> $OUT/$F
	showsh $F "perf report --stdio -i sum2d-$e.data --sort sym 2>&1 | grep -v '^\$' | grep -v '^#' | head -6"
done

echo "tracelab: 4 skid"
F=04-skid.txt
for ev in cycles cycles:P cycles cycles:P cycles:p cycles:pp cycles:ppp; do
	{ echo "\$ perf record -e $ev -o skid.data ./skid"; rec skid.data -e $ev ./skid; echo "exit status: $?"; } >> $OUT/$F
	if [ -s skid.data ]; then
		show $F perf evlist -v -i skid.data
		showsh $F "perf annotate --stdio --no-source -i skid.data -s divloop 2>/dev/null | awk '/or +\\\$0x1,/,/jne/'"
	fi
	rm -f skid.data
done

echo "tracelab: 5 callers"
F=05-callers.txt; Q=05-stack-quality.txt
{ echo "bare wall ms (median min max n):"
  echo "  callers-nofp $(repeat_wall 3 ./callers-nofp)"
  echo "  callers-fp   $(repeat_wall 3 ./callers-fp)"
  echo "  perf record -o junk.data true (perf's own start/stop cost) $(repeat_wall 3 perf record -o junk.data true)"
  echo "gcc's defaults for frame pointers (gcc -Q --help=target -O2 | grep frame-pointer):"
  gcc -Q --help=target -O2 | grep frame-pointer
  echo "and with -fno-omit-frame-pointer, does checksum() (a leaf) set up a frame?"
  for b in callers-fp callers-fpleaf; do echo "  $b: $(objdump -d $b | awk '/<checksum>:/,/^$/' | grep -c 'push.*%rbp') 'push %rbp' in checksum, $(objdump -d $b | awk '/<render>:/,/^$/' | grep -c 'push.*%rbp') in render"; done
  echo; } > $OUT/$F
for cfg in "nofp -g" "fp --call-graph=fp" "fpleaf --call-graph=fp" "nofp --call-graph=dwarf" "fp --call-graph=lbr"; do
	set -- $cfg; b=callers-$1; shift; n=$(echo "$b$*" | tr -c 'a-z\n' '_')
	{
		echo "=== ./$b under perf record $*"
		echo "\$ perf record $* -o $n.data ./$b"; rec $n.data "$@" ./$b; echo "exit status: $?"
	} >> $OUT/$F
	[ -s $n.data ] || { echo >> $OUT/$F; continue; }
	{
		echo "perf.data size: $(size $n.data)"
		echo "recorded wall ms (median min max n): $(repeat_wall 3 perf record $* -o junk.data ./$b)"
		echo "first-to-last sample ms (median min max n): $(repeat 3 spanrun $* ./$b)"
		echo "\$ perf report --stdio --no-children -S checksum,cmp -i $n.data   (comments and blank lines dropped)"
		perf report --stdio --no-children -S checksum,cmp -i $n.data 2>/dev/null | grep -v '^#' | grep -v '^$' | trim 45
		echo
	} >> $OUT/$F
	{ echo "=== $b, perf record $*"; perf script -F comm,ip,sym -i $n.data 2>/dev/null | awk -v mode=quality -f $D/stacks.awk; echo; } >> $OUT/$Q
	rm -f junk.data
done
{
	echo "offline unwinding cost for the dwarf file (wall ms, median min max n):"
	echo "  perf report --stdio > /dev/null : $(repeat_wall 3 perf report --stdio -i callers_nofp__call_graph_dwarf.data)"
	echo "  perf script > /dev/null         : $(repeat_wall 3 perf script -i callers_nofp__call_graph_dwarf.data)"
	echo "  same for the fp file (fp binary): $(repeat_wall 3 perf report --stdio -i callers_fp__call_graph_fp.data) / $(repeat_wall 3 perf script -i callers_fp__call_graph_fp.data)"
} >> $OUT/$Q

echo "tracelab: 6 folded"
BEST=callers_nofp__call_graph_dwarf.data
{ echo "\$ perf script -F comm,ip,sym -i $BEST | head -40"; perf script -F comm,ip,sym -i $BEST 2>/dev/null | head -40; } > $OUT/06-perf-script-head.txt
perf script -F comm,ip,sym -i $BEST 2>/dev/null | awk -v mode=fold -f $D/stacks.awk | sort -k2 -rn > $OUT/callers.folded
{ echo "\$ awk -v mode=fold -f stacks.awk < perf script output | sort -k2 -rn | head -15   (from $BEST)"
  echo "$(wc -l < $OUT/callers.folded) unique stacks; full list in callers.folded"; head -15 $OUT/callers.folded; } > $OUT/06-folded-head.txt

echo "tracelab: 7 rates"
F=07-rates.txt
{
	echo "perf_event_max_sample_rate at boot of run.sh: $MAXRATE0"
	echo "perf_event_max_sample_rate now: $(cat /proc/sys/kernel/perf_event_max_sample_rate)"
	echo "perf_cpu_time_max_percent: $(cat /proc/sys/kernel/perf_cpu_time_max_percent)"
	echo "default (no -F), from perf evlist -v: $(perf evlist -v -i hot.data | tr ',' '\n' | grep -E 'sample_freq|freq:' | tr '\n' ' ')"
	echo "bare ./hot wall ms (median min max n): $(repeat_wall 5 ./hot)"
	echo "perf record -o junk.data true, wall ms (median min max n): $(repeat_wall 5 perf record -o junk.data true)"
	echo "perf record --no-buildid -o junk.data true, wall ms: $(repeat_wall 5 perf record --no-buildid -o junk.data true)"; echo
	for f in 99 999 4000 9999 49999; do
		echo "\$ perf record -F $f -o f$f.data ./hot"; rec f$f.data -F $f ./hot
		echo "  size $(size f$f.data); throttle records: $(perf report -D -i f$f.data 2>/dev/null | grep -c 'PERF_RECORD_THROTTLE')"
		echo "  recorded wall ms (median min max n): $(repeat_wall 5 perf record -F $f -o junk.data ./hot)"
		echo "  first-to-last sample ms (median min max n): $(repeat 5 spanrun -F $f ./hot)"
		rm -f junk.data
	done
	echo "perf_event_max_sample_rate afterwards: $(cat /proc/sys/kernel/perf_event_max_sample_rate)"
	dmesg | grep -i 'perf' | tail -5
} > $OUT/$F

echo "tracelab: 8 kernel"
F=08-kernel.txt
{ echo "\$ perf record -g -o dd.data dd if=/dev/zero of=/dev/null bs=1 count=2000000"; perf record -g -o dd.data dd if=/dev/zero of=/dev/null bs=1 count=2000000 2>&1 | grep -v '^$'; echo; } > $OUT/$F
showsh $F "perf report --stdio --no-children --sort dso,sym -i dd.data 2>/dev/null | head -40"
showsh $F "perf report --stdio --no-children --sort dso,sym -g none -i dd.data 2>/dev/null | grep -v '^#' | grep -v '^\$' | head -20"

echo "tracelab: 9 sleepy"
F=09-blind-spot.txt
showsh $F "bash -c 'time ./sleepy'"
{ echo "\$ perf record -o sleepy.data ./sleepy"; rec sleepy.data ./sleepy; echo; } >> $OUT/$F
showsh $F "perf report --stdio -i sleepy.data 2>/dev/null | grep -v '^\$' | head -25"
{ echo "\$ perf record -e sched:sched_switch -g -o sw.data ./sleepy"; rec sw.data -e sched:sched_switch -g ./sleepy; echo; } > $OUT/09-sched-switch.txt
echo "(only the switches where the task blocked, state S or D; R means it was preempted while runnable)" >> $OUT/09-sched-switch.txt
showsh 09-sched-switch.txt "perf script -i sw.data 2>/dev/null | awk 'BEGIN{RS=\"\"; ORS=\"\\n\\n\"} /\\] [SD] ==>/' | head -50"

echo "tracelab: 10 system-wide"
F=10-system-wide.txt
{ echo "\$ perf record -a -g -o sys.data -- sleep 1"; rec sys.data -a -g -- sleep 1; echo; } > $OUT/$F
showsh $F "perf report --stdio --sort comm,dso -i sys.data 2>/dev/null | head -25"
echo "tracelab: done"
