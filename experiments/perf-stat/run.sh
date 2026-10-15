# perf stat: the counters inside the CPU.
. ../_lib/lib.sh
env_snapshot perf
T=/tmp/ps; mkdir -p $T
CF="-O1 -Wall"				# plain code, no vectorisation at -O1
BF="-O1 -fno-if-conversion -fno-tree-vectorize"	# keep "if" a real branch
gcc $CF -o $T/sum2d src/sum2d.c
gcc $BF -o $T/branchy src/branchy.c
gcc $BF -o $T/phases src/phases.c
gcc $CF -o $T/ministat src/ministat.c
gcc $CF -o $T/sysloop src/sysloop.c
gcc -O1 -static -o $T/count ../_lib/count.c
cd $T

# show FILE CMD... : append "$ CMD" and its stdout+stderr to $OUT/FILE
show() { _f=$1; shift; { echo "\$ $*"; "$@" 2>&1; echo; } >> "$OUT/$_f"; }
# csv EVENTS CMD... : perf stat in CSV mode; prints the CSV lines
csv() { _e=$1; shift; perf stat -x, -e "$_e" -o $T/csv.out -- "$@" >/dev/null 2>&1; grep -v '^#' $T/csv.out | grep -v '^$'; }

echo "tracelab: 1 sum2d"
F=01-sum2d.txt
{
	echo "THP: $(cat /sys/kernel/mm/transparent_hugepage/enabled)"
	echo "compiler flags: gcc $CF"
	echo "N = 8192 ints = 256 MiB matrix (L2 = 1 MiB, L3 = 96 MiB); sum done 4 times"
	echo
	echo "instructions:u of the whole run (perf stat -x, -e instructions:u ./sum2d X):"
	for m in rows cols; do echo "  $m $(csv instructions:u ./sum2d $m | cut -d, -f1)"; done
	echo
	echo "wall ms, median min max n (whole process, 5 runs):"
	for m in rows cols; do echo "  $m $(repeat_wall 5 ./sum2d $m)"; done
	echo
} > $OUT/$F
for m in rows cols; do
	show $F perf stat -e cycles,instructions,branches,branch-misses ./sum2d $m
	show $F perf stat -e cycles,L1-dcache-loads,L1-dcache-load-misses,dTLB-load-misses ./sum2d $m
done
objdump -d --no-show-raw-insn sum2d | awk '/<sum_(rows|cols)>:/,/ret/' > $OUT/01-sum2d-disasm.txt

echo "tracelab: 2 branchy"
F=02-branchy.txt
echo "compiler flags: gcc $BF" > $OUT/$F
echo "instructions:u: sorted $(csv instructions:u ./branchy sorted | cut -d, -f1); shuffled $(csv instructions:u ./branchy shuffled | cut -d, -f1)" >> $OUT/$F
echo "wall ms, median min max n: sorted $(repeat_wall 5 ./branchy sorted); shuffled $(repeat_wall 5 ./branchy shuffled)" >> $OUT/$F
echo >> $OUT/$F
for m in sorted shuffled; do show $F perf stat -e cycles,instructions,branches,branch-misses ./branchy $m; done
{ echo "\$ objdump -d branchy | sum_big   (gcc $BF)"; objdump -d --no-show-raw-insn branchy | awk '/<sum_big>:/,/ret/'; } > $OUT/02-branchy-disasm.txt

echo "tracelab: 3 what the guest has"
F=03-guest-pmu.txt
show $F sh -c 'dmesg | grep -i -E "Performance Events|PMU|perfctr|ibs|NMI watchdog"'
show $F ls /sys/bus/event_source/devices/ /sys/bus/event_source/devices/cpu/events /sys/bus/event_source/devices/cpu/format /sys/bus/event_source/devices/cpu/caps
show $F cat /sys/bus/event_source/devices/cpu/rdpmc /sys/bus/event_source/devices/cpu/perf_event_mux_interval_ms /proc/sys/kernel/nmi_watchdog /proc/sys/kernel/perf_event_paranoid
show $F sh -c "grep -m1 '^flags' /proc/cpuinfo | tr ' ' '\n' | grep -E 'perfctr|perfmon|ibs|lbr|pmu|hypervisor' | tr '\n' ' '"
show $F sh -c "grep -m4 -E 'cpu family|model|stepping' /proc/cpuinfo"
perf list hw cache > $OUT/03-perf-list-hw-cache.txt 2>&1
perf list 2>/dev/null > $T/list.txt
{ echo "\$ perf list | wc -l; perf list | grep -E 'l2_|l3_|ls_dmnd|ls_any|ls_refills|ls_dc_access|ls_l1_d_tlb|ls_mab' (names only)"; wc -l < $T/list.txt;
  grep -o -E '^ +(l2_|l3_|ls_dmnd|ls_any|ls_refills|ls_dc_access|ls_l1_d_tlb|ls_mab)[a-z0-9_.]*' $T/list.txt | sed 's/^ *//'; } > $OUT/03-perf-list-amd.txt
# How many counters? A group goes on the PMU all at once or not at all.
# The same event may be opened several times; each copy needs its own counter.
F=03-counter-count.txt
for n in 5 6 7; do
	ev=$(yes instructions:u | head -$n | paste -sd,)
	show $F perf stat -e "{$ev}" ./branchy sorted
done
G="cycles instructions branches branch-misses L1-dcache-loads L1-dcache-load-misses dTLB-load-misses"
show $F perf stat -e "{$(echo $G | tr ' ' '\n' | head -6 | paste -sd,)}" ./branchy sorted
show $F perf stat -e "{L1-dcache-load-misses,cycles,instructions,branches,branch-misses,L1-dcache-loads}" ./branchy sorted
show $F perf stat -e "$(echo $G | tr ' ' '\n' | head -6 | paste -sd,)" ./branchy sorted
show $F perf stat -e "{$(echo $G | tr ' ' '\n' | paste -sd,)}" ./branchy sorted
# generic and AMD Zen 4 named events under sum2d cols (4 per run: no multiplexing)
F=03-cache-events.txt
{ echo "\$ perf list --details: how perf lists the names tried below (event or metric?)"
  for e in l2_cache_req_stat.dc_access_in_l2 ls_dmnd_fills_from_sys.dram_io_near l2_cache_misses_from_l1_dc_miss l3_misses l2_dtlb_misses; do
	grep -n -E "^ +$e" $T/list.txt | head -1
  done
  echo "the [section] headers before them:"; grep -n -E '^[A-Za-z].*:$|^List of|metric' $T/list.txt | head -20
  echo; } > $OUT/$F
show $F perf stat -e cache-references,cache-misses ./sum2d rows
show $F perf stat -e cache-references,cache-misses ./sum2d cols
show $F perf stat -e l2_cache_req_stat.dc_access_in_l2,l2_cache_req_stat.dc_hit_in_l2,l2_cache_req_stat.ls_rd_blk_c ./sum2d cols
show $F perf stat -M l2_cache_misses_from_l1_dc_miss ./sum2d cols
show $F perf stat -e ls_dmnd_fills_from_sys.local_l2,ls_dmnd_fills_from_sys.local_ccx,ls_dmnd_fills_from_sys.dram_io_near,ls_any_fills_from_sys.dram_io_all ./sum2d cols
show $F perf stat -e l3_misses ./sum2d cols
show $F perf stat -M l3_misses ./sum2d cols
show $F perf stat -e ls_l1_d_tlb_miss.all,ls_l1_d_tlb_miss.tlb_reload_4k_l2_miss,ls_l1_d_tlb_miss.tlb_reload_2m_l2_miss ./sum2d cols
show $F perf stat -e amd_l3/event=0x04,umask=0xff/ ./sum2d cols

echo "tracelab: 4 ministat"
F=04-ministat.txt
show $F ./ministat
show $F perf stat -e instructions:u,cycles:u ./count
show $F perf stat -e instructions:u,cycles:u ./ministat

echo "tracelab: 5 overhead"
F=05-overhead.txt
{
	echo "workload: ./branchy shuffled; wall ms, median min max n (7 runs each)"
	echo "bare:                                   $(repeat_wall 7 ./branchy shuffled)"
	echo "perf stat -e cycles,instructions:       $(repeat_wall 7 perf stat -e cycles,instructions ./branchy shuffled)"
	echo "bare (again):                           $(repeat_wall 7 ./branchy shuffled)"
	echo
} > $OUT/$F
show $F perf stat -r 5 -e cycles,instructions ./branchy shuffled

echo "tracelab: 6 multiplexing"
F=06-multiplex.txt
M="cycles instructions branches branch-misses L1-dcache-loads L1-dcache-load-misses dTLB-loads dTLB-load-misses iTLB-loads iTLB-load-misses L1-icache-loads L1-icache-load-misses"
for n in 8 10 12; do show $F perf stat -e "$(echo $M | tr ' ' '\n' | head -$n | paste -sd,)" ./sum2d cols; done
F=06-phases.txt
X="cycles,instructions,branches,L1-dcache-loads,dTLB-loads,dTLB-load-misses,iTLB-loads,iTLB-load-misses,L1-icache-loads,L1-icache-load-misses"
{
	echo "phases K: phase A (branch misses) and phase B (cache misses), each ~0.5 s total, cut into K slices and alternated."
	echo "truth = perf stat -x, -e branch-misses,L1-dcache-load-misses ./phases K"
	echo "mux   = same two events plus: $X  (12 events, more than the counters)"
	echo "mux interval: $(cat /sys/bus/event_source/devices/cpu/perf_event_mux_interval_ms) ms"
	echo "columns: K kind run branch-misses (running%) L1-dcache-load-misses (running%) wall_ms"
} > $OUT/$F
for k in 1 10 100 250 1000; do
	for r in 1 2; do
		s=$(now_ns); csv branch-misses,L1-dcache-load-misses ./phases $k > $T/c; e=$(now_ns)
		echo "$k truth $r $(awk -F, '{printf "%s (%s%%) ", $1, $5}' $T/c) $(( (e-s)/1000000 ))" >> $OUT/$F
	done
	for r in 1 2 3; do
		s=$(now_ns); csv branch-misses,L1-dcache-load-misses,$X ./phases $k | head -2 > $T/c; e=$(now_ns)
		echo "$k mux $r $(awk -F, '{printf "%s (%s%%) ", $1, $5}' $T/c) $(( (e-s)/1000000 ))" >> $OUT/$F
	done
done
# Is the error from the program changing, or from the rotation itself?
# branchy shuffled is uniform and its instruction count is fixed. Vary the rotation period.
F=06-mux-interval.txt
MI=/sys/bus/event_source/devices/cpu/perf_event_mux_interval_ms
{
	echo "workload ./branchy shuffled; 12 events (no groups) vs instructions alone; scaled value as printed by perf"
	echo "truth: instructions $(csv instructions:u ./branchy shuffled | cut -d, -f1), cycles $(csv cycles:u ./branchy shuffled | cut -d, -f1) (both :u, alone)"
	echo "columns: mux_interval_ms  instructions:u (running%)  cycles:u (running%)"
} > $OUT/$F
for iv in 1 4 16 100 1 4 16 100; do
	echo $iv > $MI
	csv instructions:u,cycles:u,branches:u,branch-misses:u,L1-dcache-loads:u,L1-dcache-load-misses:u,dTLB-loads:u,dTLB-load-misses:u,iTLB-loads:u,iTLB-load-misses:u,L1-icache-loads:u,L1-icache-load-misses:u ./branchy shuffled | head -2 > $T/c
	echo "$iv $(awk -F, '{printf "%s (%s%%) ", $1, $5}' $T/c)" >> $OUT/$F
done
echo 1 > $MI
show 06-phases-example.txt perf stat -e branch-misses,L1-dcache-load-misses,$X ./phases 1

echo "tracelab: 7 sysloop"
show 07-user-kernel.txt perf stat -e instructions:u,instructions:k,cycles:u,cycles:k ./sysloop

echo "tracelab: 8 count"
F=08-count.txt
echo "\$ perf stat -x, -e instructions:u ./count   (5 times; gcc -O1 -static)" > $OUT/$F
for r in 1 2 3 4 5; do csv instructions:u ./count | cut -d, -f1; done >> $OUT/$F
show $F perf stat -e instructions:u ./count

echo "tracelab: 9 system-wide"
show 09-system-wide.txt perf stat -a -e cycles,instructions sleep 1
show 09-system-wide.txt perf stat -a -A -e cycles,instructions sleep 1
echo "tracelab: done"
