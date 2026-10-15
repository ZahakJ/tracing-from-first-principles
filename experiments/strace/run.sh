# strace: standing at the syscall boundary.
. ../_lib/lib.sh
env_snapshot strace gcc
set -u

# Build.
mkdir -p bin
for p in minitrace liar slowcat fastcat waits sysloop spin saver saver_checked; do
	gcc -O2 -Wall -o bin/$p src/$p.c || exit 1
done
B=$PWD/bin
T=/tmp/strace-exp; mkdir -p $T

# cmdfile FILE CMD-STRING: write "$ CMD" then the output (stdout+stderr) of CMD.
cmdfile() { _f=$1; shift; { echo "\$ $*"; sh -c "$*" 2>&1; echo "[exit status $?]"; } > "$_f"; }

# ---------------------------------------------------------------- 1. minitrace
cd $B
{
	echo '$ ./minitrace /bin/true 2>&1 | head -n 25'
	./minitrace /bin/true 2>&1 | head -n 25
	echo "[... $(./minitrace /bin/true 2>&1 | wc -l) lines in total; the last two:]"
	./minitrace /bin/true 2>&1 | tail -n 2; echo
	echo
	echo '$ ./minitrace -q /bin/true'
	./minitrace -q /bin/true 2>&1
	echo
	echo '$ strace /bin/true 2>&1 | head -n 25'
	strace /bin/true 2>&1 | head -n 25
	echo "[... $(strace /bin/true 2>&1 | wc -l) lines in total]"
	echo
	echo '$ strace -c /bin/true 2>&1 | tail -n 3'
	strace -c /bin/true 2>&1 | tail -n 3
} > $OUT/01-minitrace.txt 2>&1

# ---------------------------------------------------------------- 2. the liar
cmdfile $OUT/02-liar.txt "./liar"
{ echo; echo "\$ strace -e trace=openat ./liar"; strace -e trace=openat ./liar 2>&1
  echo; echo "\$ strace -y -e trace=openat,close ./liar"; strace -y -e trace=openat,close ./liar 2>&1
  echo; echo "\$ echo HOME=\$HOME; pwd"; echo HOME=$HOME; pwd; } >> $OUT/02-liar.txt

# ---------------------------------------------------------------- 3. one byte at a time
head -c 4194304 /dev/urandom > $T/in.4M
head -c 1048576 $T/in.4M > $T/in.1M
head -c 131072 $T/in.4M > $T/in.128K
{
	echo "# input: $T/in.4M (4 MiB of /dev/urandom); output: $T/out (a real file, not /dev/null)"
	echo "# filesystem of /tmp: $(stat -f -c %T /tmp)"
	for p in fastcat slowcat; do
		echo "\$ ./$p < in.4M > out    (wall ms, 5 runs: median min max n)"
		r=$(repeat_wall 5 sh -c "$B/$p < $T/in.4M > $T/out")
		echo "$r"
		cmp -s $T/in.4M $T/out && echo "(output identical to input)"
		[ $p = slowcat ] && echo "$r" | awk '{ n = 2*4194304; printf "  %d syscalls in the copy loop -> %.1f ns per read-or-write (%.2f ms * 1e6 / %d; process startup included, negligible)\n", n, $1*1e6/n, $1, n }'
		[ $p = fastcat ] && echo "  (fastcat: 64 reads + 64 writes + 1 EOF read = 129 syscalls in the copy loop)"
	done
} > $OUT/03-slowcat-wall.txt 2>&1
{
	echo "\$ strace -c ./fastcat < in.4M > out"
	strace -c ./fastcat < $T/in.4M 2>&1 > $T/out
	echo
	echo "# slowcat gets a 1 MiB input here (2,097,152 copy syscalls): at 4 MiB the traced run takes ~100 s."
	echo "\$ strace -c ./slowcat < in.1M > out"
	_s=$(now_ns); strace -c ./slowcat < $T/in.1M 2>&1 > $T/out; _e=$(now_ns)
	echo "[wall time of that traced run: $(( (_e-_s)/1000000 )) ms]"
} > $OUT/04-slowcat-strace-c.txt 2>&1

# ---------------------------------------------------------------- 4. waiting
cd $T
{
	echo "\$ strace -f -T -e trace=read,nanosleep,clock_nanosleep,fsync,write ./waits"
	strace -f -T -e trace=read,nanosleep,clock_nanosleep,fsync,write $B/waits 2>&1 | grep -v -e '^read(3, "\\177ELF' 
	echo "# (filtered out: the dynamic loader's read of libc's ELF header)"
	echo
	echo "\$ strace -c -w -f ./waits"
	strace -c -w -f $B/waits 2>&1
	echo
	echo "\$ strace -c -f ./waits      (default: system CPU time, not wall)"
	strace -c -f $B/waits 2>&1 | sed -n '1,6p;$p'
	echo "[... trimmed: the three most expensive rows and the total kept]"
	echo
	echo "\$ strace -T -e trace=read,clock_nanosleep,write ./waits     (no -f: the child is not followed)"
	strace -T -e trace=read,clock_nanosleep,write $B/waits 2>&1 | grep -v -e '^read(3, "\\177ELF' 
} > $OUT/05-waits.txt 2>&1
cd $B

# ---------------------------------------------------------------- 5. cost
NB=2000000; NS=100000
{
	echo "# sysloop N: N getppid() syscalls, prints ns/call (CLOCK_MONOTONIC around the loop)."
	echo "# 5 runs each. columns: config | N | ns/syscall median (min-max) | slowdown vs bare"
	bres=$(repeat 5 ./sysloop $NB); base=${bres%% *}
	row() { _lab=$1; _n=$2; shift 2; _r=$(repeat 5 "$@" ./sysloop $_n)
		echo "$_r" | awk -v l="$_lab" -v n=$_n -v b=$base '{printf "%-50s | %7d | %8.1f (%.1f-%.1f) | x%.1f\n", l, n, $1, $2, $3, $1/b}'; }
	echo "$bres" | awk -v n=$NB '{printf "%-50s | %7d | %8.1f (%.1f-%.1f) | x1.0\n", "bare", n, $1, $2, $3}'
	row "strace -o /dev/null" $NS strace -o /dev/null
	row "strace -c -o /dev/null" $NS strace -c -o /dev/null
	row "strace -o /dev/null -e trace=openat" $NS strace -o /dev/null -e trace=openat
	row "strace -o /dev/null --seccomp-bpf -e trace=openat" $NS strace -o /dev/null --seccomp-bpf -e trace=openat
	row "strace -f -o /dev/null --seccomp-bpf -e trace=openat" $NB strace -f -o /dev/null --seccomp-bpf -e trace=openat
	row "strace -f -o /dev/null -e trace=openat (no bpf)" $NS strace -f -o /dev/null -e trace=openat
	row "./minitrace -q" $NS ./minitrace -q
	echo "# slowdown = median / bare median ($base ns)"
	echo "# extra cost per traced syscall = traced median - bare median"
	echo
	echo "# what strace says on stderr for the --seccomp-bpf rows (hidden above):"
	echo "\$ strace -o /dev/null --seccomp-bpf -e trace=openat ./sysloop 1000"
	strace -o /dev/null --seccomp-bpf -e trace=openat ./sysloop 1000 2>&1
	echo "\$ strace -f -o /dev/null --seccomp-bpf -e trace=openat ./sysloop 1000"
	strace -f -o /dev/null --seccomp-bpf -e trace=openat ./sysloop 1000 2>&1
} > $OUT/06-cost-sysloop.txt 2>&1
{
	echo "# Same programs as part 3, wall ms, 5 runs each: median min max n. Output to $T/out."
	echo "# columns: input | bare median (min-max) | traced median (min-max) | extra ms | syscalls | extra us per syscall"
	for pf in fastcat:in.4M:129 slowcat:in.128K:262144; do
		p=${pf%%:*}; f=${pf#*:}; n=${f#*:}; f=${f%%:*}
		echo "\$ ./$p < $f > out    vs    strace -o /dev/null ./$p < $f > out"
		a=$(repeat_wall 5 sh -c "$B/$p < $T/$f > $T/out")
		b=$(repeat_wall 5 sh -c "strace -o /dev/null $B/$p < $T/$f > $T/out")
		echo "$a $b" | awk -v f=$f -v n=$n '{printf "%s | %.1f (%.1f-%.1f) ms | %.1f (%.1f-%.1f) ms | %.1f ms | %d | %.2f us\n", f, $1,$2,$3, $5,$6,$7, $5-$1, n, ($5-$1)*1000/n}'
	done
	echo "# slowcat uses a 128 KiB input (262,144 copy syscalls) to keep the traced runs short."
	echo "# extra us per syscall = (traced - bare) ms * 1000 / syscalls in the copy loop (fastcat: ~30 more startup syscalls, ignored)"
} > $OUT/07-cost-cat.txt 2>&1

# ---------------------------------------------------------------- 6. blind spot
{
	echo "\$ strace -c ./spin"
	strace -c ./spin 2>&1
	echo
	echo "\$ strace -tt ./spin 2>&1 | tail -n 8"
	strace -tt ./spin 2>&1 | tail -n 8
	echo
	echo "# wall ms, 5 runs: median min max n"
	echo "\$ ./spin";                 repeat_wall 5 ./spin
	echo "\$ strace -o /dev/null ./spin"; repeat_wall 5 strace -o /dev/null ./spin
} > $OUT/08-spin.txt 2>&1

# ---------------------------------------------------------------- 7. fault injection
cd $T
{
	echo "\$ strace -e trace=write -e inject=write:error=ENOSPC:when=3 ./saver"
	strace -e trace=write -e inject=write:error=ENOSPC:when=3 $B/saver 2>&1
	echo "[exit status $?]"
	echo "\$ wc -l saved.txt; cat saved.txt"; wc -l saved.txt; cat saved.txt
	echo
	echo "\$ strace -e trace=write -e inject=write:error=ENOSPC:when=3 ./saver_checked"
	strace -e trace=write -e inject=write:error=ENOSPC:when=3 $B/saver_checked 2>&1
	echo "[exit status $?]"
	echo "\$ wc -l saved.txt"; wc -l saved.txt
	echo
	echo "\$ ./saver_checked    (no injection)"; $B/saver_checked 2>&1; echo "[exit status $?]"
} > $OUT/09-inject.txt 2>&1
cd $B

# ---------------------------------------------------------------- 8. stack traces
{
	echo "\$ strace -k -e trace=openat ./liar"
	strace -k -e trace=openat ./liar > $T/k.txt 2>&1
	echo "[exit status $?]"
	echo "[first $(grep -n '/etc/liar' $T/k.txt | cut -d: -f1 | awk '{print $1-1}') lines omitted: the dynamic loader's two openat calls, each with an 11-12 frame stack inside ld-linux-x86-64.so.2]"
	sed -n '/\/etc\/liar/,$p' $T/k.txt
} > $OUT/10-stack-k.txt 2>&1

# ---------------------------------------------------------------- 9. ptrace permission
{
	echo "\$ cat /proc/sys/kernel/yama/ptrace_scope"; cat /proc/sys/kernel/yama/ptrace_scope 2>&1
	echo "\$ grep -E 'Seccomp|CapEff' /proc/self/status"; grep -E 'Seccomp|CapEff' /proc/self/status
	sleep 3 & SP=$!
	echo "\$ sleep 3 & strace -p \$!    (sleep is a sibling, not strace's child)"
	timeout 2 strace -p $SP 2>&1; echo "[exit status $?]"
	kill $SP 2>/dev/null; wait $SP 2>/dev/null
} > $OUT/11-ptrace-scope.txt 2>&1

echo done
