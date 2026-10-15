#!/bin/sh
# mtrace: who forgot to free?  Counting shim -> glibc mtrace -> heaptrack
# -> what interposers cannot see (ASan, Valgrind memcheck).
. ../_lib/lib.sh
env_snapshot mtrace heaptrack valgrind ltrace
DBG=$(find /usr/lib /lib -name 'libc_malloc_debug.so.0' 2>/dev/null | head -1)
echo "libc_malloc_debug: $DBG" >> "$OUT/env.txt"
B=/tmp/b; mkdir -p $B
set -x
gcc -g -O0 -Wall -o $B/leaky src/leaky.c
gcc -g -O0 -Wall -no-pie -o $B/leaky-nopie src/leaky.c
gcc -g -O0 -Wall -fsanitize=address -o $B/leaky-asan src/leaky.c
gcc -shared -fPIC -O2 -Wall -o $B/count.so src/count.c -ldl
gcc -O2 -Wall -o $B/churn src/churn.c
gcc -O2 -g -Wall -fsanitize=address -o $B/churn-asan src/churn.c
gcc -g -O0 -Wall -o $B/uaf src/uaf.c
gcc -g -O0 -Wall -fsanitize=address -o $B/uaf-asan src/uaf.c
set +x
cd $B

# trim N FILE: first N lines, then a note of how many were cut
trim() { head -n "$1" "$2"; _t=$(wc -l < "$2"); [ "$_t" -gt "$1" ] && echo "[... $((_t - $1)) more lines]"; true; }

# 1. the leaky program, plain
{ echo '$ ./leaky'; ./leaky 2>&1; echo "exit status: $?"; } > $OUT/01-leaky.txt

# 2. the dumbest detector
{ echo '$ LD_PRELOAD=./count.so ./leaky'; LD_PRELOAD=./count.so ./leaky 2>&1; } > $OUT/02-count.txt

# 3a. MALLOC_TRACE alone
{ echo '$ MALLOC_TRACE=/tmp/x.log ./leaky; ls -l /tmp/x.log'
  MALLOC_TRACE=/tmp/x.log ./leaky 2>&1; ls -l /tmp/x.log 2>&1; } > $OUT/03a-mtrace-plain.txt

# 3b. with the debug library preloaded
LD_PRELOAD=$DBG MALLOC_TRACE=/tmp/m.log ./leaky > /dev/null
{ echo "\$ LD_PRELOAD=$DBG MALLOC_TRACE=/tmp/m.log ./leaky"
  echo "\$ head -12 /tmp/m.log; tail -2 /tmp/m.log; wc -l"
  head -12 /tmp/m.log; echo "[...]"; tail -2 /tmp/m.log
  echo "total lines: $(wc -l < /tmp/m.log)  (+ lines: $(grep -c ' + ' /tmp/m.log), - lines: $(grep -c ' - ' /tmp/m.log))"
  echo "size: $(wc -c < /tmp/m.log) bytes"; } > $OUT/03b-mtrace-log.txt

# 3c. the mtrace perl script
mtrace ./leaky /tmp/m.log > /tmp/r.txt 2>&1
{ echo '$ mtrace ./leaky /tmp/m.log'; trim 12 /tmp/r.txt
  echo; echo '$ mtrace ./leaky /tmp/m.log | awk "/ at /{print \$NF}" | sort | uniq -c'
  awk '/ at /{print $NF}' /tmp/r.txt | sort | uniq -c
  echo; echo '$ ... and the sizes: awk "/ at /{print \$2, \$NF}" | sort | uniq -c'
  awk '/ at /{print $2, $NF}' /tmp/r.txt | sort | uniq -c; } > $OUT/03c-mtrace-report.txt

LD_PRELOAD=$DBG MALLOC_TRACE=/tmp/n.log ./leaky-nopie > /dev/null
mtrace ./leaky-nopie /tmp/n.log > /tmp/rn.txt 2>&1
{ echo '$ gcc -g -O0 -no-pie ...; LD_PRELOAD=... MALLOC_TRACE=/tmp/n.log ./leaky-nopie; head -4 /tmp/n.log'
  head -4 /tmp/n.log
  echo; echo '$ mtrace ./leaky-nopie /tmp/n.log'; trim 8 /tmp/rn.txt
  echo; echo '$ ... | awk "/ at /{print \$NF}" | sort | uniq -c'
  awk '/ at /{print $NF}' /tmp/rn.txt | sort | uniq -c
  echo; echo '$ LD_TRACE_LOADED_OBJECTS=2 ./leaky-nopie | head -1   # the base mtrace(1) adds (ld.so l_addr)'
  LD_TRACE_LOADED_OBJECTS=2 ./leaky-nopie | head -1
  echo '$ LD_TRACE_LOADED_OBJECTS=2 ./leaky | head -1'
  LD_TRACE_LOADED_OBJECTS=2 ./leaky | head -1
  echo; echo '$ readelf -lW ./leaky-nopie | grep -m1 LOAD   # where the non-PIE image really starts'
  readelf -lW ./leaky-nopie | grep -m1 LOAD
  for a in $(awk '/ at /{print $NF}' /tmp/rn.txt | sort -u); do
	_a=$(printf '0x%x' $(($a + 0x400000)))
	echo "\$ addr2line -e ./leaky-nopie $a  -> $(addr2line -e ./leaky-nopie $a)"
	echo "\$ addr2line -e ./leaky-nopie $_a  -> $(addr2line -e ./leaky-nopie $_a)   (by hand, + 0x400000)"
  done
  echo; echo '$ file ./leaky ./leaky-nopie'; file ./leaky ./leaky-nopie | cut -c1-110; } > $OUT/03d-mtrace-nopie.txt

# 4. the wrapper problem
{ echo '$ sed -n 21,28p leaky.c   # the line every name leak is blamed on'
  awk 'NR>=21 && NR<=28 {printf "%3d  %s\n", NR, $0}' "$OLDPWD/src/leaky.c"
  echo; echo '$ grep -n "xstrdup(" leaky.c   # who calls it'
  grep -n 'xstrdup(' "$OLDPWD/src/leaky.c"
  echo; echo "mtrace rows blamed on leaky.c:23 (inside xmalloc): $(grep -c 'leaky.c:23$' /tmp/r.txt)"
  echo "rows blamed on leaky.c:42 (handle calling xstrdup) or :32 (xstrdup calling xmalloc): $(grep -c 'leaky.c:42$\|leaky.c:32$' /tmp/r.txt)"; } > $OUT/04-wrapper.txt

# 5. heaptrack: full backtrace at each allocation
heaptrack -o /tmp/ht ./leaky > /tmp/ht-run.txt 2>&1
HT=$(ls /tmp/ht.* 2>/dev/null | head -1)
heaptrack_print --print-leaks -f "$HT" > /tmp/htp.txt 2>&1
{ echo '$ heaptrack -o /tmp/ht ./leaky'; trim 10 /tmp/ht-run.txt
  echo; echo "data file: $HT  $(wc -c < "$HT") bytes (compressed)"
  echo; echo "\$ heaptrack_print --print-leaks -f $HT   # leak section and summary only"
  awk '/^MEMORY LEAKS/{f=1} /^MOST TEMPORARY/{f=0} f' /tmp/htp.txt > /tmp/htleak.txt
  echo "[trimmed: the entry for libc's stdout buffer (_IO_file_doallocate, 4.10K, $(awk -v RS= '/doallocate/' /tmp/htleak.txt | wc -l) lines) is dropped]"
  awk -v RS= -v ORS='\n\n' '!/doallocate/' /tmp/htleak.txt
  echo; echo '[summary]'; awk '/^total runtime/{f=1} f' /tmp/htp.txt | head -12; } > $OUT/05-heaptrack.txt

# 6. cost: churn under each tool
R=5; N=5000000
nsrun() { "$@" 2>&1 | awk '/ns per malloc/{print $3}'; }
row() {  # row LABEL N CMD...   -> median/min/max of churn's ns/pair, and wall ms
	_l=$1; _n=$2; shift 2
	_ns=$(repeat $R nsrun "$@" $_n)
	_w=$(repeat_wall $R "$@" $_n)
	echo "$_l|$_n|$_ns|$_w" >> /tmp/cost.raw
}
: > /tmp/cost.raw
row bare $N ./churn
row count-shim $N env LD_PRELOAD=./count.so ./churn
dbg() { LD_PRELOAD=$DBG "$@"; }
row malloc_debug-idle $N dbg ./churn
mt() { LD_PRELOAD=$DBG MALLOC_TRACE=/tmp/churn.log "$@"; }
row mtrace $N mt ./churn
mtnull() { LD_PRELOAD=$DBG MALLOC_TRACE=/dev/null "$@"; }      # same work, nothing kept
row mtrace-to-dev-null $N mtnull ./churn
row heaptrack $N heaptrack -o /tmp/htc ./churn
VN=500000
row valgrind-memcheck $VN valgrind -q --leak-check=full ./churn
row asan $N ./churn-asan
aq0() { ASAN_OPTIONS=quarantine_size_mb=0 "$@"; }
row asan-no-quarantine $N aq0 ./churn-asan
aq0s0() { ASAN_OPTIONS=quarantine_size_mb=0:malloc_context_size=0 "$@"; }
row asan-no-quar-no-stacks $N aq0s0 ./churn-asan
LN=20000
row ltrace $LN ltrace -e malloc+free ./churn
mt ./churn $N > /dev/null
ls -l /tmp/htc.* > /tmp/htc-ls.txt 2>&1
{ echo "# churn: N malloc+free pairs, 1000 live blocks, sizes 16..4096. $R runs each."
  echo "# ns/pair is churn's own clock around the loop (excludes tool start-up and teardown)."
  echo "# wall is the whole process (includes start-up, heaptrack's post-processing, valgrind's JIT, etc.)."
  echo "# slowdown = median ns/pair / bare median ns/pair.  wall/pair = wall ms * 1e6 / N."
  echo "# commands: ./churn N; LD_PRELOAD=./count.so ./churn N;\n#   LD_PRELOAD=$DBG ./churn N (malloc_debug-idle: library loaded, MALLOC_TRACE unset); LD_PRELOAD=$DBG MALLOC_TRACE=/tmp/churn.log ./churn N;"
  echo "#   heaptrack -o /tmp/htc ./churn N; valgrind -q --leak-check=full ./churn $VN; ./churn-asan N (-fsanitize=address -O2);\n#   ASAN_OPTIONS=quarantine_size_mb=0 ./churn-asan N; ASAN_OPTIONS=quarantine_size_mb=0:malloc_context_size=0 ./churn-asan N;"
  echo "#   ltrace -e malloc+free ./churn $LN"
  awk -F'|' '
	{ split($3, a, " "); split($4, w, " ")
	  if (NR == 1) base = a[1]
	  printf "%-22s N=%-8s ns/pair median %9.1f (min %9.1f max %9.1f)  x%-8.1f wall ms median %9.1f (min %9.1f max %9.1f)  wall/pair %8.1f ns\n",
		$1, $2, a[1], a[2], a[3], a[1]/base, w[1], w[2], w[3], w[1]*1e6/$2 }' /tmp/cost.raw
  echo; echo "mtrace log for one N=$N run: $(wc -c < /tmp/churn.log) bytes = $(awk "BEGIN{printf \"%.0f\", $(wc -c < /tmp/churn.log)/1048576}") MB, $(wc -l < /tmp/churn.log) lines"
  echo "heaptrack data files:"; cat /tmp/htc-ls.txt | awk '{print "  " $5, $9}' | tail -3
} > $OUT/06-cost.txt
rm -f /tmp/churn.log /tmp/htc.*

# 7. what interposers cannot see
{ echo '$ ./uaf'; ./uaf 2>&1; echo "exit status: $?"; } > $OUT/07a-uaf-plain.txt
LD_PRELOAD=$DBG MALLOC_TRACE=/tmp/u.log ./uaf > /tmp/uo.txt 2>&1; _st=$?
{ echo "\$ LD_PRELOAD=$DBG MALLOC_TRACE=/tmp/u.log ./uaf"; cat /tmp/uo.txt; echo "exit status: $_st"
  echo; echo '$ cat /tmp/u.log'; trim 10 /tmp/u.log
  echo; echo '$ mtrace ./uaf /tmp/u.log'; mtrace ./uaf /tmp/u.log 2>&1; echo "exit status: $?"; } > $OUT/07b-uaf-mtrace.txt
./uaf-asan > /tmp/ua.txt 2>&1; _st=$?
grep -v '^  0x' /tmp/ua.txt | sed '/^Shadow byte legend/,$d' > /tmp/ua3.txt
{ echo '$ gcc -g -O0 -fsanitize=address -o uaf-asan uaf.c && ./uaf-asan'
  echo "[shadow-byte dump cut to the => row, legend removed; full report was $(wc -l < /tmp/ua.txt) lines]"; trim 25 /tmp/ua3.txt; echo "exit status: $_st"; } > $OUT/07c-uaf-asan.txt
ASAN_OPTIONS=halt_on_error=0 ./uaf-asan > /tmp/ua2.txt 2>&1
gcc -g -O0 -fsanitize=address -fsanitize-recover=address -o uaf-asan-recover "$OLDPWD/src/uaf.c"
ASAN_OPTIONS=halt_on_error=0 ./uaf-asan-recover > /tmp/ua2.txt 2>&1; _st=$?
{ echo '$ gcc ... -fsanitize=address -fsanitize-recover=address; ASAN_OPTIONS=halt_on_error=0 ./uaf-asan-recover | grep ERROR/first frame'
  grep -E 'ERROR|^    #0|^    #1|SUMMARY|^buf|^after' /tmp/ua2.txt; echo "exit status: $_st"; } > $OUT/07d-uaf-asan-both.txt
valgrind ./uaf > /tmp/uv.txt 2>&1; _st=$?
grep -v '^==[0-9]*== *$' /tmp/uv.txt > /tmp/uv2.txt
{ echo '$ valgrind ./uaf   # blank ==pid== lines removed'; trim 40 /tmp/uv2.txt; echo "exit status: $_st"; } > $OUT/07e-uaf-valgrind.txt

valgrind --leak-check=full ./leaky > /tmp/lv.txt 2>&1; _st=$?
grep -v '^==[0-9]*== *$' /tmp/lv.txt > /tmp/lv2.txt
{ echo '$ valgrind --leak-check=full ./leaky   # blank ==pid== lines removed'; trim 45 /tmp/lv2.txt; echo "exit status: $_st"; } > $OUT/07f-leaky-valgrind.txt
./leaky-asan > /tmp/la.txt 2>&1; _st=$?
{ echo '$ gcc -g -O0 -fsanitize=address -o leaky-asan leaky.c && ./leaky-asan'; trim 30 /tmp/la.txt; echo "exit status: $_st"
  echo; echo '$ ./leaky-asan 2>&1 | grep SUMMARY'; grep SUMMARY /tmp/la.txt; } > $OUT/07g-leaky-lsan.txt

# 8. not a leak, but how big is the heap?
{ echo '$ MALLINFO=1 ./leaky'; MALLINFO=1 ./leaky 2>&1 | head -30; } > $OUT/08-mallinfo.txt

# 9. ltrace as a counter
ltrace -c -e malloc+free ./leaky > /tmp/lt.txt 2>&1
{ echo '$ ltrace -c -e malloc+free ./leaky'; trim 15 /tmp/lt.txt; } > $OUT/09-ltrace.txt
echo done
