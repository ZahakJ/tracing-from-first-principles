# gprof and uftrace: making the compiler tell you.
# -pg puts a call to mcount/__fentry__ at the top of every function.
# gprof counts arcs with it and samples the PC with a 100 Hz timer;
# uftrace records every entry and exit.
. ../_lib/lib.sh
env_snapshot gprof uftrace strace objdump
O=-O2
W=$(pwd)/work; mkdir -p "$W"

# trim N : keep the first N lines of stdin, say how many were dropped
trim() { awk -v n="$1" 'NR<=n{print} END{if(NR>n) printf "[... %d more lines]\n", NR-n}'; }
# sh_out FILE CMD : write "$ CMD" and its output (stdout+stderr) to $OUT/FILE
sh_out() { _f=$1; shift; { echo "\$ $*"; sh -c "$*" 2>&1; } > "$OUT/$_f"; }

cd "$W"
cp ../src/*.c .

echo "== 1. builds"
gcc $O -o paths-plain paths.c
gcc $O -pg -o paths-pg paths.c                 # default (PIE on Debian)
gcc $O -pg -no-pie -o paths-pg-nopie paths.c
gcc $O -o paths-truth paths_truth.c
gcc $O -fpatchable-function-entry=5 -o paths-patch paths.c

# ---- 01: the truth
{
	echo "\$ ./paths-truth   (5 runs)"
	for i in 1 2 3 4 5; do ./paths-truth; done
	echo
	echo "\$ wall time of ./paths-plain, ms (median min max n):"
	repeat_wall 5 ./paths-plain
} > "$OUT/01-truth.txt" 2>&1

# ---- 02: what the compiler inserts
dis() {	# dis LABEL FLAGS... : first 8 instructions of spin()
	gcc $O -c "$@" -o d.o paths.c
	echo "=== gcc $O $* -c paths.c ; objdump -dr --no-show-raw-insn d.o, <spin> first 8 lines"
	objdump -dr --no-show-raw-insn d.o | awk '/<spin>:/{p=1} p&&/^$/{exit} p' | sed -n '2,11p' | grep -v '^$' | head -10
	echo
}
{
	echo "\$ (see each block's header; relocations shown with -r)"
	dis
	dis -pg
	dis -pg -mfentry
	dis -pg -mfentry -mrecord-mcount -mnop-mcount -fno-pie
	dis -finstrument-functions
	echo "=== the same, every call in spin() (enter and exit):"
	objdump -dr --no-show-raw-insn d.o | awk '/<spin>:/{p=1} p&&/^$/{exit} p' | grep -B1 'R_X86_64' | grep -v '^--'
	echo
	dis -fpatchable-function-entry=5
} > "$OUT/02-inserted.txt" 2>&1

# ---- 03: gprof
for v in pg pg-nopie; do
	rm -f gmon.out
	s=$(now_ns); ./paths-$v; e=$(now_ns)
	echo "paths-$v ran in $(( (e - s) / 1000000 )) ms, gmon.out $(stat -c %s gmon.out 2>/dev/null) bytes"
	mv gmon.out gmon-$v.out 2>/dev/null
done > "$OUT/03-gprof-runs.txt" 2>&1
{
	echo "\$ ./paths-pg && gprof -b ./paths-pg gmon.out   (default gcc: PIE)"
	cp gmon-pg.out gmon.out
	gprof -b ./paths-pg gmon.out 2>&1 | trim 40
	echo
	echo "\$ file ./paths-pg"; file ./paths-pg 2>&1 | cut -c1-120
} > "$OUT/03-gprof-pie.txt" 2>&1
{
	echo "\$ ./paths-pg-nopie && gprof -b ./paths-pg-nopie gmon.out   (gcc -O2 -pg -no-pie)"
	cp gmon-pg-nopie.out gmon.out
	gprof -b -p ./paths-pg-nopie gmon.out 2>&1 | trim 10
} > "$OUT/03-gprof-nopie.txt" 2>&1
{
	echo "\$ gprof -b -q ./paths-pg-nopie gmon.out   (call graph only)"
	gprof -b -q ./paths-pg-nopie gmon.out 2>&1 | trim 26
	echo
	echo "truth (a fresh run of ./paths-truth): $(./paths-truth)"
} > "$OUT/03-gprof-callgraph.txt" 2>&1

# ---- 04: where gprof's time comes from
{
	echo "\$ strace -f -e trace=setitimer,timer_create,timer_settime,rt_sigaction,profil ./paths-pg 2>&1 | grep -E 'ITIMER_PROF|SIGPROF|timer'"
	strace -f -e trace=setitimer,timer_create,timer_settime,rt_sigaction,profil ./paths-pg 2>&1 | grep -E 'ITIMER_PROF|SIGPROF|timer'
	echo
	echo "\$ strace -c -e signal=SIGPROF ... (count of SIGPROF deliveries)"
	strace -f -e trace=none -e signal=SIGPROF ./paths-pg 2>&1 | grep -c SIGPROF
} > "$OUT/04-timer.txt" 2>&1
rm -f gmon.out

# ---- 05: what gprof cannot see
gcc $O -pg -no-pie -o blind-pg blind.c
{
	echo "\$ ./blind-pg && gprof -b -p ./blind-pg gmon.out"
	s=$(now_ns); ./blind-pg 2>&1; e=$(now_ns)
	echo "(total wall $(( (e - s) / 1000000 )) ms)"
	gprof -b -p ./blind-pg gmon.out 2>&1 | trim 20
	echo
	echo "\$ gprof -b -q ./blind-pg gmon.out | head -25"
	gprof -b -q ./blind-pg gmon.out 2>&1 | trim 25
} > "$OUT/05-blind-gprof.txt" 2>&1
rm -f gmon.out

# ---- 06: uftrace on paths
rm -rf uftrace.data
{
	echo "\$ uftrace record ./paths-pg"
	s=$(now_ns); uftrace record ./paths-pg 2>&1; e=$(now_ns)
	echo "(wall $(( (e - s) / 1000000 )) ms; uftrace.data $(du -sb uftrace.data | cut -f1) bytes)"
	ls -l uftrace.data | trim 12
	echo
	echo "wall ms, 5 runs each (median min max n):"
	echo "./paths-pg                  $(repeat_wall 5 ./paths-pg)"
	echo "uftrace record ./paths-pg   $(repeat_wall 5 uftrace record -d /tmp/uft.tmp ./paths-pg)"
} > "$OUT/06-uftrace-record.txt" 2>&1
sh_out 06-uftrace-report.txt "uftrace report | head -15"
sh_out 06-uftrace-graph.txt "uftrace graph | head -30"
sh_out 06-uftrace-replay.txt "uftrace replay | head -20"
{
	echo "\$ uftrace record -t 1ms ./paths-pg && uftrace report"
	rm -rf uftrace.data
	s=$(now_ns); uftrace record -t 1ms ./paths-pg 2>&1; e=$(now_ns)
	echo "(wall $(( (e - s) / 1000000 )) ms; uftrace.data $(du -sb uftrace.data | cut -f1) bytes)"
	uftrace report 2>&1 | head -12
} > "$OUT/06-uftrace-filter.txt" 2>&1
rm -rf uftrace.data
{
	echo "\$ uftrace record ./blind-pg && uftrace report && uftrace replay"
	uftrace record ./blind-pg 2>&1
	uftrace report 2>&1 | head -15
	echo
	echo "\$ uftrace replay | head -30"
	uftrace replay 2>&1 | trim 30
} > "$OUT/06-uftrace-blind.txt" 2>&1
rm -rf uftrace.data

# ---- 07: uftrace without recompiling
{
	echo "\$ uftrace record ./paths-plain        (no -pg)"
	uftrace record ./paths-plain 2>&1 | head -5
	echo
	echo "\$ uftrace record -P . ./paths-plain   (dynamic patching, plain -O2)"
	rm -rf uftrace.data
	uftrace record -P . ./paths-plain 2>&1 | head -10
	echo "\$ uftrace record -v -P . ./paths-plain 2>&1 | grep -E 'dynamic|perf'   (why is main missing?)"
	rm -rf uftrace.data
	uftrace record -v -P . ./paths-plain 2>&1 | grep -E 'dynamic|perf' | head -8
	echo "\$ objdump -d paths-plain, <main>:"
	objdump -d --no-show-raw-insn paths-plain | awk '/<main>:/{p=1} p&&/^$/{exit} p' | head -6
	echo "\$ uftrace report"; uftrace report 2>&1 | head -10
	echo
	echo "\$ uftrace record -P . ./paths-patch   (-fpatchable-function-entry=5)"
	rm -rf uftrace.data
	uftrace record -v -P . ./paths-patch 2>&1 | grep -E 'dynamic' | head -6
	echo "\$ uftrace report"; uftrace report 2>&1 | head -10
	echo
	echo "\$ uftrace record ./paths-patch   (no -P)"
	rm -rf uftrace.data
	uftrace record ./paths-patch 2>&1 | head -5
	echo "\$ uftrace report"; uftrace report 2>&1 | head -10
} 2>&1 | sed 's/\x1b\[[0-9;]*m//g' > "$OUT/07-uftrace-dynamic.txt"
rm -rf uftrace.data

# ---- 08: cost per call
N=200000000; NU=2000000
gcc $O -o calls-plain calls.c
gcc $O -pg -o calls-pg calls.c
gcc $O -pg -mfentry -o calls-fentry calls.c
gcc $O -c -o cyg_hooks.o cyg_hooks.c
gcc $O -finstrument-functions -o calls-cyg calls.c cyg_hooks.o
gcc $O -fpatchable-function-entry=5 -o calls-patch calls.c
uft() { rm -rf uftrace.data; uftrace record "$@" > ur.out 2>/dev/null; tail -n 1 ur.out; }
{
	echo "\$ ./calls N   -> ns per call of add(); 5 runs each; median (min-max)"
	echo "N = $N except under uftrace record: N = $NU"
	echo
	base=$(repeat 5 ./calls-plain $N)
	b=${base%% *}
	row() {	# row LABEL "median min max n"
		echo "$2" | awk -v l="$1" -v b="$b" '{printf "%-44s %8.2f (%.2f-%.2f)  +%7.2f  x%.1f\n", l, $1, $2, $3, $1-b, $1/b}'
	}
	printf "%-44s %s\n" "build / run" "ns/call median (min-max)   added   slowdown"
	row "plain -O2" "$base"
	row "-fpatchable-function-entry=5, run plain" "$(repeat 5 ./calls-patch $N)"
	row "-pg, run plain (mcount + gprof)" "$(repeat 5 ./calls-pg $N)"
	row "-pg -mfentry, run plain" "$(repeat 5 ./calls-fentry $N)"
	row "-finstrument-functions, empty hooks" "$(repeat 5 ./calls-cyg $N)"
	row "-pg under uftrace record" "$(repeat 5 uft ./calls-pg $NU)"
	row "-pg under uftrace record -t 100us" "$(repeat 5 uft -t 100us ./calls-pg $NU)"
	echo
	rm -rf uftrace.data; uftrace record ./calls-pg $NU >/dev/null 2>&1
	sz=$(du -sb uftrace.data | cut -f1)
	echo "uftrace record ./calls-pg $NU: uftrace.data = $sz bytes = $(echo "$sz $NU" | awk '{printf "%.1f", $1/$2}') bytes per call (each call = 1 entry + 1 exit record)"
	rm -rf uftrace.data; uftrace record -t 100us ./calls-pg $NU >/dev/null 2>&1
	echo "uftrace record -t 100us ./calls-pg $NU: uftrace.data = $(du -sb uftrace.data | cut -f1) bytes"
	rm -rf uftrace.data; rm -f gmon.out
} > "$OUT/08-cost.txt" 2>&1

# ---- 09: threads
gcc $O -pg -no-pie -pthread -o threads-pg threads.c
{
	echo "\$ ./threads-pg && gprof -b -p ./threads-pg gmon.out"
	./threads-pg
	gprof -b -p ./threads-pg gmon.out 2>&1 | trim 12
	echo
	echo "\$ uftrace record ./threads-pg && uftrace report"
	rm -rf uftrace.data
	uftrace record ./threads-pg 2>&1
	uftrace report 2>&1 | head -12
	rm -rf uftrace.data
} > "$OUT/09-threads.txt" 2>&1
rm -f gmon.out
echo done
