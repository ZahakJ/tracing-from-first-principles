# Six ways to watch a program, each built by hand in a page of C.
. ../_lib/lib.sh
env_snapshot valgrind
set -e
CC="gcc -O2 -g -no-pie -Wall"
S=src

$CC -o work $S/work.c
$CC -DTELL -o work_tell $S/work.c
$CC -finstrument-functions -o work_hooked $S/work.c $S/hooks.c
gcc -O2 -shared -fPIC -o sampler.so $S/sampler.c
gcc -O2 -shared -fPIC -o shim.so $S/shim.c
gcc -O2 -Wall -o bp $S/bp.c
gcc -O2 -Wall -o step $S/step.c
$CC -o cost $S/cost.c
$CC -finstrument-functions -o cost_hooked $S/cost.c $S/hooks.c

addr() { nm "$1" | awk -v s="$2" '$3==s {print $1}'; }               # address of a function
end_of() { set -- $(nm -S "$1" | awk -v s="$2" '$4==s {print $1, $2}'); printf '%x\n' $((0x$1 + 0x$2)); }
ms() { repeat_wall 5 "$@"; }

# ---- 01: the program, unobserved -----------------------------------------------------------
{
	echo '$ ./work'; ./work
	echo; echo "wall time of ./work, ms: median min max runs"; ms ./work
	echo "wall time of ./work 200000, ms:"; ms ./work 200000
} > $OUT/01-plain.txt

# ---- 02: ask the program to tell you ----------------------------------------------------------
{
	echo '$ ./work_tell 200000 2> tell.log'
	./work_tell 200000 2> /tmp/tell.log
	echo '$ head -6 tell.log'; head -6 /tmp/tell.log
	echo '$ wc -l -c tell.log'; wc -l -c < /tmp/tell.log
	echo "$ awk '{print \$2}' tell.log | sort | uniq -c"; awk '{print $2}' /tmp/tell.log | sort | uniq -c
	echo; echo "wall time, ms (median min max runs):"
	echo "work 200000                      $(ms ./work 200000)"
	echo "work_tell 200000 2>/tmp/tell.log $(ms sh -c './work_tell 200000 2>/tmp/tell.log')"
} > $OUT/02-tell.txt

# ---- 03: have the compiler make it tell you ---------------------------------------------------
{
	echo '$ gcc -O2 -g -no-pie -finstrument-functions work.c hooks.c -o work_hooked'
	echo '$ objdump -d work_hooked --disassemble=store      (work.c is unchanged)'
	objdump -d --no-show-raw-insn --disassemble=store work_hooked | sed -n '/<store>:/,$p' | grep -v -e '^$' -e '^Disassembly'
	echo; echo '$ ./work_hooked        (raw: address, calls, total ns)'
	./work_hooked 2> /tmp/hooks.raw; cat /tmp/hooks.raw
	echo; echo "the same, with addresses turned into names by addr2line:"
	printf '%-14s %10s %12s %10s\n' function calls total_ms ns/call
	while read a c ns; do
		printf '%-14s %10d %12.1f %10.0f\n' "$(addr2line -f -e work_hooked $a | head -1)" $c $(echo "$ns/1000000" | bc -l) $(echo "$ns/$c" | bc -l)
	done < /tmp/hooks.raw
	echo; echo "wall time, ms (median min max runs):"
	echo "work         $(ms ./work)"
	echo "work_hooked  $(ms ./work_hooked)"
} > $OUT/03-compiler.txt 2>&1

# ---- 04: interrupt it and look ---------------------------------------------------------------
{
	echo '$ LD_PRELOAD=./sampler.so SAMPLES=samples.txt ./work'
	LD_PRELOAD=./sampler.so SAMPLES=/tmp/samples.txt ./work
	echo '$ head -4 samples.txt'; head -4 /tmp/samples.txt
	echo '$ wc -l < samples.txt'; wc -l < /tmp/samples.txt
	echo; echo "samples per function (addresses inside ./work resolved with addr2line -f; others named by file):"
	while read a f; do
		case $f in *work) addr2line -f -e work $a | head -1;; *) echo "($(basename $f))";; esac
	done < /tmp/samples.txt | sort | uniq -c | sort -rn | awk -v n=$(wc -l < /tmp/samples.txt) '{printf "%6d  %5.1f%%  %s\n", $1, 100*$1/n, $2}'
	echo; echo "the hottest source lines inside ./work:"
	grep 'work$' /tmp/samples.txt | cut -d' ' -f1 | addr2line -e work | sed 's|.*/||' | sort | uniq -c | sort -rn | head -4
	echo; echo "wall time, ms (median min max runs):"
	echo "work                 $(ms ./work)"
	echo "work with sampler.so $(ms env LD_PRELOAD=./sampler.so SAMPLES=/tmp/s3.txt ./work)"
} > $OUT/04-sampler.txt 2>&1

# ---- 05: trap it at a chosen instruction -------------------------------------------------------
{
	echo '$ nm work | grep " store$"'; nm work | grep ' store$'
	echo '$ objdump -d work --disassemble=store | head'
	objdump -d --disassemble=store work | sed -n '/<store>:/,$p' | head -6
	echo "\$ ./bp $(addr work store) ./work"
	./bp $(addr work store) ./work
	echo; echo "wall time, ms (median min max runs):"
	echo "work                  $(ms ./work)"
	echo "bp <store> work       $(ms ./bp $(addr work store) ./work)"
} > $OUT/05-breakpoint.txt 2>&1

# ---- 06: stand between it and what it calls ----------------------------------------------------
{
	echo '$ LD_PRELOAD=./shim.so ./work'
	LD_PRELOAD=./shim.so ./work
	echo; echo "wall time, ms (median min max runs):"
	echo "work               $(ms ./work)"
	echo "work with shim.so  $(ms env LD_PRELOAD=./shim.so ./work)"
} > $OUT/06-shim.txt 2>&1

# ---- 07: one instruction at a time ---------------------------------------------------------------
{
	LO=$(addr work checksum); HI=$(end_of work checksum)
	echo "\$ ./step $LO $HI ./work 1000        (the range is the checksum function)"
	./step $LO $HI ./work 1000
	echo "\$ ./step $LO $HI ./work 1000        (again: is the count the same?)"
	./step $LO $HI ./work 1000 2>&1 | head -2 | tail -1
	echo; echo "wall time of the unobserved ./work 1000, ms: $(ms ./work 1000)"
	echo; echo "the same question put to Valgrind, which simulates the CPU instead of stopping it:"
	echo '$ valgrind --tool=lackey ./work 1000'
	/usr/bin/time -f "%e s wall" valgrind --tool=lackey ./work 1000 2>&1 | grep -E 'guest instrs:|wall|^[0-9]' | sed 's/^==[0-9]*== //'
} > $OUT/07-step.txt 2>&1

# ---- 08: the price list ------------------------------------------------------------------------
c() { repeat 5 "$@"; }      # median min max n of "ns per call"
{
	echo "ns per call: median min max runs"
	BASE=$(c ./cost none)
	echo "none (just the call)             $BASE"
	echo "flag (test a variable, off)      $(c ./cost flag)"
	echo "ring (rdtsc -> memory)           $(c ./cost ring)"
	echo "clock (clock_gettime -> memory)  $(c ./cost clock)"
	echo "printf (text -> stdio -> file)   $(c ./cost printf 2000000)"
	echo "write (text -> write() each)     $(c ./cost write 2000000)"
	echo "compiler hooks (enter+exit)      $(c ./cost_hooked none)"
	echo "breakpoint via ptrace            $(c ./bp $(addr cost tick_none) ./cost none 200000)"
	echo "malloc+free, no shim             $(c ./cost malloc)"
	echo "malloc+free, with shim.so        $(c env LD_PRELOAD=./shim.so ./cost malloc)"
} > $OUT/08-cost.txt 2>&1
