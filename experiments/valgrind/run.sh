# valgrind: running the program on a CPU made of software.
. ../_lib/lib.sh
env_snapshot valgrind gcc
set -u

# Build.
mkdir -p bin
B=$PWD/bin
gcc -O1 -static -o bin/count ../_lib/count.c || exit 1
gcc -O1 -g -o bin/paths src/paths.c || exit 1
gcc -O1 -g -o bin/sum2d src/sum2d.c || exit 1
gcc -O1 -o bin/mallocs src/mallocs.c || exit 1
gcc -O1 -pthread -o bin/threads src/threads.c || exit 1
for p in uaf over uninit; do gcc -O0 -g -o bin/$p src/$p.c || exit 1; done
T=/tmp/vg; mkdir -p $T
cd $B

# trim N: keep the first N lines of stdin, then say how many were dropped.
trim() { awk -v n="$1" 'NR<=n {print} END {if (NR>n) printf "[... %d more lines]\n", NR-n}'; }
# vgclean: drop valgrind's banner lines (copyright, "Command:", blank ==pid== lines).
vgclean() { grep -v -e 'Copyright' -e 'Using Valgrind' -e 'rerun with -h' -e '^==[0-9]*== *$'; }
# wall_s CMD...: wall seconds of CMD, 3 decimals.
wall_s() { wall_ms "$@" | awk '{printf "%.3f\n", $1/1000}'; }
# timeit CMD...: one line "wall_s user_s sys_s" for CMD.
timeit() { /usr/bin/time -f '%e %U %S' -o $T/time "$@" >/dev/null 2>&1; cat $T/time; }

# ---------------------------------------------------------------- 1. the bare machine
echo "part 1 start $(date +%T)"
{
	echo '$ ./count'; ./count; echo
	echo '$ valgrind --tool=none ./count'
	valgrind --tool=none ./count 2>&1 | vgclean; echo
	echo '$ valgrind --tool=lackey ./count'
	valgrind --tool=lackey ./count 2>&1 | vgclean; echo
	echo '$ valgrind --tool=callgrind --callgrind-out-file=cg.N ./count   (3 times)'
	for i in 1 2 3; do
		valgrind --tool=callgrind --callgrind-out-file=$T/cg.$i ./count 2>&1 | grep -e Collected -e 'refs'
		echo "  cg.$i: $(grep -e '^summary:' -e '^totals:' $T/cg.$i | tr '\n' ' ')"
	done
	echo
	echo '$ callgrind_annotate cg.1 | head (the program total and top functions)'
	callgrind_annotate $T/cg.1 2>&1 | grep -v '^ *$' | sed -n '/^Ir/,$p' | head -n 12
	echo
	echo '# the same binary, the same argument, a different environment (startup code walks envp):'
	echo '$ env -i valgrind --tool=callgrind ./count'
	env -i /usr/bin/valgrind --tool=callgrind --callgrind-out-file=$T/cg.e ./count 2>&1 | grep Collected
	echo '$ env -i A=<3000 x characters> valgrind --tool=callgrind ./count'
	env -i A=$(head -c 3000 /dev/zero | tr '\0' x) /usr/bin/valgrind --tool=callgrind --callgrind-out-file=$T/cg.f ./count 2>&1 | grep Collected
	echo "# main alone (callgrind_annotate): $(callgrind_annotate $T/cg.e | grep ':main ' | awk '{print $1}') with env -i, $(callgrind_annotate $T/cg.1 | grep ':main ' | awk '{print $1}') with the normal environment"
	echo
	echo '# native wall time of ./count, 5 runs (ms):'
	for i in 1 2 3 4 5; do wall_ms ./count; done > $T/nat
	tr '\n' ' ' < $T/nat; echo
	stats < $T/nat | awk '{print "# median " $1 " ms, min " $2 ", max " $3 ", n " $4}'
} > $OUT/01-bare-machine.txt 2>&1

# ---------------------------------------------------------------- 2. one translated block
echo "part 2 start $(date +%T)"
# The inner loop of collatz_steps (inlined into main at -O1) starts at the
# instruction just before the first 'shr' in main. Find that address, find which
# superblock number each tool gives it, and print just that superblock.
A=$(objdump -d count --no-show-raw-insn | awk '/<main>:/,/^$/' | awk '/shr/ {print prev; exit} {sub(":", "", $1); prev = $1}')
sbnum() { valgrind --tool=$1 --trace-flags=10000000 --trace-notbelow=0 ./count 10 2>&1 | grep "^==== SB .* 0x$A " | head -n 1 | awk '{print $3}'; }
# blk TOOL FLAGS: the trace of that one superblock, without blank lines, IR-NoOps
# and the temporaries' type declarations.
blk() {
	_n=$(sbnum $1)
	valgrind --tool=$1 --trace-flags=$2 --trace-notbelow=$_n --trace-notabove=$_n ./count 10 2>&1 |
		awk -v n="$_n" '$0 ~ "^==== SB " n " " {p=1} $0 ~ "^==== SB " && $3 != n {p=0} p' |
		awk '/^IRSB \{/ {print; decl=1; next} decl && /IMark/ {decl=0} !decl' |
		grep -v -e '^ *$' -e 'IR-NoOp'
}
{
	echo "# The block: main+0x60 (0x$A), the n/2 branch of the collatz loop, as objdump shows it:"
	echo "\$ objdump -d count | (lines from 0x$A to the je)"
	objdump -d count --no-show-raw-insn | awk -v a="$A:" '$1 == a {p=1} p {print} p && /je/ {exit}'
	echo
	echo "\$ valgrind --tool=none --trace-flags=10000000 --trace-notbelow=N --trace-notabove=N ./count 10"
	echo "# (N = this block's superblock number; 10000000 = 'show conversion into IR'; blank lines removed)"
	blk none 10000000 | sed -n '1,/^IRSB {/p' | grep -v '^IRSB {' | trim 60
	for t in none lackey memcheck; do
		echo
		echo "\$ valgrind --tool=$t --trace-flags=00100000 ... ./count 10    # 'show after instrumentation'"
		echo "# (IR-NoOp lines and temporary type declarations removed)"
		blk $t 00100000 > $T/instr.$t
		echo "# $(grep -c -e ' = ' -e 'PUT' -e 'STle' -e 'DIRTY' -e 'if (' $T/instr.$t) IR statements (lines containing '=', PUT, STle, DIRTY or 'if (')"
		trim 45 < $T/instr.$t
	done
	echo
	echo "\$ valgrind --tool=none --trace-flags=00000001 ... ./count 10    # 'show final assembly' (host code)"
	blk none 00000001 | trim 45
	for t in lackey memcheck; do
		echo "# final host code, --tool=$t: $(blk $t 00000001 | wc -l) lines (vs $(blk none 00000001 | wc -l) for none)"
	done
} > $OUT/02-translated-block.txt 2>&1

# ---------------------------------------------------------------- 3. callgrind attribution
echo "part 3 start $(date +%T)"
{
	echo "# native: ./paths wall ms, 5 runs (median min max n): $(repeat_wall 5 ./paths)"
	echo '$ valgrind --tool=callgrind --callgrind-out-file=paths.cg ./paths'
	valgrind --tool=callgrind --callgrind-out-file=$T/paths.cg ./paths 2>&1 | vgclean
	echo
	echo '$ callgrind_annotate --inclusive=yes paths.cg   (functions from paths.c only)'
	callgrind_annotate --inclusive=yes $T/paths.cg 2>&1 | grep -e '^Ir' -e 'PROGRAM TOTALS' -e 'paths.c:'
	echo
	echo '$ callgrind_annotate --tree=caller paths.cg   (the entry for spin)'
	callgrind_annotate --tree=caller $T/paths.cg 2>&1 | grep -B3 '\*  .*paths.c:spin'
	echo
	echo '$ callgrind_annotate --tree=both --inclusive=yes paths.cg   (fast_path, slow_path, spin)'
	callgrind_annotate --tree=both --inclusive=yes $T/paths.cg 2>&1 | awk '/^ *$/ {if (keep) print "--"; keep=0; buf=""; next} {buf = buf $0 "\n"} /\* .*paths.c:(spin|fast_path|slow_path)/ {keep=1} keep && buf {printf "%s", buf; buf=""}'
	echo
	echo '$ callgrind_annotate --auto=yes paths.cg   (the source lines of spin)'
	callgrind_annotate --auto=yes $T/paths.cg 2>&1 | grep -A8 'static __attribute__((noinline)) void spin'
} > $OUT/03-callgrind-paths.txt 2>&1

# ---------------------------------------------------------------- 4. cachegrind
echo "part 4 start $(date +%T)"
{
	for o in rows cols; do
		echo "\$ ./sum2d $o"; ./sum2d $o
		echo "# native wall ms, 5 runs (median min max n): $(repeat_wall 5 ./sum2d $o)"
		echo "\$ valgrind --tool=cachegrind --cache-sim=yes --cachegrind-out-file=cg.$o ./sum2d $o"
		valgrind --tool=cachegrind --cache-sim=yes --cachegrind-out-file=$T/cg.$o ./sum2d $o 2>&1 | vgclean
		echo
	done
	echo '# the simulated cache geometry, from the output file header:'
	echo '$ grep ^desc: cg.rows'
	grep '^desc:' $T/cg.rows
	echo
	echo '# and what valgrind -v says about where the sizes came from:'
	echo '$ valgrind -v --tool=cachegrind --cache-sim=yes ./sum2d rows 2>&1 | grep -i -e cache -e LL'
	valgrind -v --tool=cachegrind --cache-sim=yes --cachegrind-out-file=/dev/null ./sum2d rows 2>&1 | grep -i -e 'cache' -e 'LL' | grep -v -e 'refs' -e 'misses' -e 'miss rate' | head -n 8
	echo
	echo '$ getconf -a | grep CACHE   (the real CPU)'
	getconf -a | grep -e LEVEL1_DCACHE -e LEVEL2_CACHE -e LEVEL3_CACHE | grep -v ' 0$'
	echo
	echo '# the same, but simulating a 1 MB 8-way LL (the size of this CPU L2) instead of the 96 MB L3:'
	for o in rows cols; do
		echo "\$ valgrind --tool=cachegrind --cache-sim=yes --LL=1048576,8,64 ./sum2d $o 2>&1 | grep -e 'D1  miss' -e 'LLd miss'"
		valgrind --tool=cachegrind --cache-sim=yes --LL=1048576,8,64 --cachegrind-out-file=/dev/null ./sum2d $o 2>&1 | grep -e 'D1  miss' -e 'LLd miss'
	done
	for o in rows cols; do
		echo
		echo "\$ cg_annotate cg.$o   (the summing loops of sum_rows and sum_cols)"
		cg_annotate $T/cg.$o 2>&1 | grep -e '^Ir' -e 's += m\[i\]\[j\]' -e 'for (int [ij] = 0; i\{0,1\}j\{0,1\} < N' | head -n 12
	done
} > $OUT/04-cachegrind.txt 2>&1

# ---------------------------------------------------------------- 5. memcheck
echo "part 5 start $(date +%T)"
for p in uaf over uninit; do
	{
		echo "\$ ./$p"; ./$p; echo "[exit status $?]"
		echo
		echo "\$ valgrind --track-origins=yes ./$p"
		valgrind --track-origins=yes ./$p 2>&1 | vgclean | grep -v -e 'Memcheck, a memory error' -e 'HEAP SUMMARY' -e 'in use at exit' -e 'total heap usage' -e 'All heap blocks' -e 'list of detected' -e 'For counts of' -e 'Use --track-origins' | trim 30
	} > $OUT/05-memcheck-$p.txt 2>&1
done
{
	echo '$ gcc -fsanitize=address -g -O0 -o uninit-asan uninit.c && ./uninit-asan'
	gcc -fsanitize=address -g -O0 -o uninit-asan ../src/uninit.c 2>&1 && ./uninit-asan; echo "[exit status $?]"
	echo
	echo '$ gcc -fsanitize=address -g -O0 -o uaf-asan uaf.c && ./uaf-asan   (for contrast: ASan does catch this one)'
	gcc -fsanitize=address -g -O0 -o uaf-asan ../src/uaf.c 2>&1 && ./uaf-asan 2>&1 | head -n 4; echo
	echo '$ gcc -Wall -O2 -c uninit.c'
	gcc -Wall -O2 -c -o /dev/null ../src/uninit.c 2>&1; echo "[gcc exit status $?, output above if any]"
	echo '$ gcc -Wall -Wextra -O2 -c uninit.c'
	gcc -Wall -Wextra -O2 -c -o /dev/null ../src/uninit.c 2>&1; echo "[gcc exit status $?, output above if any]"
	echo '$ gcc -Wall -O0 -c uninit.c'
	gcc -Wall -O0 -c -o /dev/null ../src/uninit.c 2>&1; echo "[gcc exit status $?, output above if any]"
	echo '$ gcc -Wall -O2 -fanalyzer -c uninit.c'
	gcc -Wall -O2 -fanalyzer -c -o /dev/null ../src/uninit.c 2>&1 | head -n 20; echo "[output above if any]"
} > $OUT/05-uninit-other-tools.txt 2>&1

# ---------------------------------------------------------------- 6. price list
echo "part 6 start $(date +%T)"
NC=4000000
{
	echo "# workload: ./count $NC (a tight integer loop, no syscalls, no malloc)"
	echo "# wall seconds; native 5 runs, valgrind tools 3 runs except lackey and callgrind (1 run each: they are slow)"
	echo "# runner allows a neighbouring experiment, so look at min as well as median"
	echo "# tool                           median   min     max     n   slowdown(median/native median)"
	for i in 1 2 3 4 5; do wall_s ./count $NC; done | stats > $T/native
	read nat natmin natmax nn < $T/native
	printf "%-34s %-8s %-7s %-7s %-3s %s\n" native $nat $natmin $natmax $nn 1.0
	row() { _name=$1; _n=$2; shift 2
		_i=0; while [ $_i -lt $_n ]; do wall_s "$@"; _i=$((_i+1)); done | stats > $T/r
		read m mi ma n < $T/r
		printf "%-34s %-8s %-7s %-7s %-3s %s\n" "$_name" $m $mi $ma $n "$(echo "$m $nat" | awk '{if ($2 > 0.02) printf "%.1f", $1/$2; else printf "(+%.0f ms)", ($1-$2)*1000}')"
	}
	row "--tool=none" 3 valgrind --tool=none ./count $NC
	row "--tool=lackey" 1 valgrind --tool=lackey ./count $NC
	row "--tool=callgrind" 1 valgrind --tool=callgrind --callgrind-out-file=/dev/null ./count $NC
	row "--tool=cachegrind --cache-sim=yes" 3 valgrind --tool=cachegrind --cache-sim=yes --cachegrind-out-file=/dev/null ./count $NC
	row "--tool=cachegrind (no cache sim)" 3 valgrind --tool=cachegrind --cachegrind-out-file=/dev/null ./count $NC
	row "--tool=memcheck" 3 valgrind --tool=memcheck ./count $NC
	echo
	echo "# workload 2: ./mallocs 3000000 (3M malloc+free pairs of 16..215 bytes), dynamically linked"
	for i in 1 2 3 4 5; do wall_s ./mallocs 3000000; done | stats > $T/native
	read nat natmin natmax nn < $T/native
	printf "%-34s %-8s %-7s %-7s %-3s %s\n" native $nat $natmin $natmax $nn 1.0
	row "--tool=none" 3 valgrind --tool=none ./mallocs 3000000
	row "--tool=callgrind" 3 valgrind --tool=callgrind --callgrind-out-file=/dev/null ./mallocs 3000000
	row "--tool=memcheck" 3 valgrind --tool=memcheck ./mallocs 3000000
	echo
	echo "# workload 3: /bin/true (nothing but process startup: the fixed cost)"
	for i in 1 2 3 4 5; do wall_s /bin/true; done | stats > $T/native
	read nat natmin natmax nn < $T/native
	printf "%-34s %-8s %-7s %-7s %-3s %s\n" native $nat $natmin $natmax $nn "(too small to divide)"
	row "--tool=none" 3 valgrind --tool=none /bin/true
	row "--tool=memcheck" 3 valgrind --tool=memcheck /bin/true
} > $OUT/06-price-list.txt 2>&1

# ---------------------------------------------------------------- 7. threads
echo "part 7 start $(date +%T)"
{
	echo "# nproc: $(nproc)"
	echo '$ /usr/bin/time ./threads   (4 threads, each a CPU-bound loop)   wall_s user_s sys_s'
	timeit ./threads
	echo '$ /usr/bin/time valgrind --tool=none ./threads                    wall_s user_s sys_s'
	timeit valgrind --tool=none ./threads
	echo '$ /usr/bin/time valgrind --tool=none --fair-sched=yes ./threads   wall_s user_s sys_s'
	timeit valgrind --tool=none --fair-sched=yes ./threads
} > $OUT/07-threads.txt 2>&1
echo done
