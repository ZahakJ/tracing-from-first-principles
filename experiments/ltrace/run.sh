#!/bin/sh
# ltrace: standing at the library boundary.
. ../_lib/lib.sh
env_snapshot strace ltrace gcc ld
set -u
B=$PWD/build; mkdir -p "$B"; cd "$B"
S=../src

# cmdout FILE CMD...  : "$ CMD" then CMD's stdout+stderr into $OUT/FILE
cmdout() { _f=$OUT/$1; shift; echo "\$ $*" > "$_f"; "$@" >> "$_f" 2>&1; }
# trim N : keep first N lines of stdin, say how many were dropped
trim() { awk -v n="$1" 'NR<=n{print} END{if(NR>n) printf "[... %d more lines]\n", NR-n}'; }

echo "== building"
gcc -O0 -fno-builtin $S/shout.c -o shout
gcc -O0 -fno-builtin -fno-pie -no-pie $S/selfpeek.c -o selfpeek
gcc -O0 -fno-builtin $S/callloop.c -o callloop
gcc -O2 -shared -fPIC $S/shim.c -o shim.so -ldl
gcc -O0 -fno-builtin -fPIC -shared $S/greet.c -o libgreet.so
gcc -O0 $S/usegreet.c -o usegreet -L. -lgreet -Wl,-rpath,"$B"
gcc -O0 $S/readline.c -o readline

#### 1. the problem program
F=$OUT/01-shout-objdump.txt
echo '$ objdump -d shout | grep -E "call.*(strlen|toupper)"' > $F
objdump -d shout | grep -E 'call.*(strlen|toupper)' >> $F
F=$OUT/01-shout-wall.txt
echo '$ ./shout    (200000 bytes; wall ms over 5 runs: median min max n)' > $F
./shout >> $F
repeat_wall 5 ./shout >> $F
for n in 50000 100000; do echo "\$ ./shout $n -> $(repeat_wall 5 ./shout $n)" >> $F; done
cmdout 01-shout-strace-c.txt strace -c ./shout
F=$OUT/01-shout-ltrace-c.txt
echo '$ ltrace -c ./shout 2000    (2000 bytes instead of 200000, to keep it short: 200000 bytes means 400001 traced calls)' > $F
ltrace -c ./shout 2000 >> $F 2>&1
echo "wall ms, 5 runs (median min max n): ./shout 2000 = $(repeat_wall 5 ./shout 2000); ltrace -c ./shout 2000 = $(repeat_wall 5 ltrace -c ./shout 2000)" >> $F
F=$OUT/01-shout-ltrace-head.txt
echo '$ ltrace ./shout 20 2>&1 | head -15' > $F
ltrace ./shout 20 2>&1 | trim 15 >> $F

#### 2. what the PLT is
F=$OUT/02-plt.txt
{
echo '$ readelf -S shout | grep plt'
readelf -S shout | grep plt
echo
echo '$ objdump -d -j .plt -j .plt.sec shout   (trimmed: first stub PLT0 and strlen@plt)'
objdump -d -j .plt -j .plt.sec shout 2>/dev/null | awk '
	/^[0-9a-f]+ <.*>:$/ { show = (++blk == 1) || /strlen@plt/ ; if (show) print ""}
	show && /^ /' 
echo
echo '$ objdump -d shout | grep -B3 -A1 "call.*strlen@plt"   (the call sites in main)'
objdump -d shout | grep -B3 -A1 'call.*strlen@plt'
echo
echo '$ readelf -r shout | grep -E "Offset|strlen"'
readelf -r shout | grep -E 'Offset|strlen'
} > $F 2>&1

#### 3. the breakpoint, seen from inside
F=$OUT/03-selfpeek.txt
{
echo '$ objdump -d -j .plt selfpeek | grep -A3 "<puts@plt>:"'
objdump -d -j .plt selfpeek | grep -A3 '<puts@plt>:'
echo
echo '$ ./selfpeek'
./selfpeek
echo
echo '$ ltrace ./selfpeek    (ltrace writes to stderr, the program to stdout)'
ltrace ./selfpeek 2>&1
echo
echo '$ ltrace -o /dev/null ./selfpeek'
ltrace -o /dev/null ./selfpeek
} > $F 2>&1
# variant: -fPIE code linked -no-pie (taking &puts goes through the GOT)
gcc -O0 -fno-builtin -no-pie $S/selfpeek.c -o selfpeek-fpie
# variant: IBT PLT (.plt.sec): where does the breakpoint go?
gcc -O0 -fno-builtin -fno-pie -no-pie -fcf-protection=full -Wl,-z,ibtplt $S/selfpeek.c -o selfpeek-ibt
F=$OUT/03b-selfpeek-variants.txt
{
echo '### built with -no-pie only (Debian gcc still emits -fPIE code)'
echo '$ readelf -r selfpeek-fpie | grep puts'
readelf -r selfpeek-fpie | grep puts
echo '$ ltrace ./selfpeek-fpie'
ltrace ./selfpeek-fpie 2>&1
echo
echo '### built -fno-pie -no-pie -fcf-protection=full -Wl,-z,ibtplt (.plt.sec)'
echo '$ objdump -d -j .plt.sec selfpeek-ibt | grep -A4 "<puts@plt>:"'
objdump -d -j .plt.sec selfpeek-ibt | grep -A4 '<puts@plt>:'
echo '$ ltrace ./selfpeek-ibt'
ltrace ./selfpeek-ibt 2>&1
} > $F 2>&1

#### 4. cost per call
F=$OUT/04-callloop-objdump.txt
echo '$ objdump -d callloop | grep "call.*labs"' > $F
objdump -d callloop | grep 'call.*labs' >> $F
NB=10000000; NL=20000
r_bare=$(repeat 7 ./callloop $NB)
r_strace=$(repeat 7 strace -o /dev/null ./callloop $NB)
r_shim=$(repeat 7 env LD_PRELOAD=$B/shim.so ./callloop $NB)
r_lt=$(repeat 5 ltrace -o /dev/null ./callloop $NL)
r_ltc=$(repeat 5 ltrace -c -o /dev/null ./callloop $NL)
r_lte=$(repeat 5 ltrace -e malloc -o /dev/null ./callloop $NB)   # a filter that does not match labs
LD_PRELOAD=./shim.so ./callloop 1000 > /dev/null 2> $OUT/04-shim-check.txt
F=$OUT/04-overhead.txt
{
echo "# ns per labs() call (callloop prints total ns / N, timed inside the program)"
echo "# median (min-max) of n runs; slowdown = median / bare median"
echo "# commands: ./callloop N ; strace -o /dev/null ./callloop N ;"
echo "#           LD_PRELOAD=./shim.so ./callloop N ; ltrace -o /dev/null ./callloop N ; ltrace -c -o /dev/null ./callloop N"
echo "#           ltrace -e malloc -o /dev/null ./callloop N   (a filter that does not match labs)"
printf '%-28s %10s %8s  %s\n' setup N runs "ns/call median (min-max)   slowdown"
base=$(echo $r_bare | cut -d' ' -f1)
row() { set -- "$1" "$2" $3; printf '%-28s %10s %8s  %s (%s-%s)   %sx\n' "$1" "$2" "$6" "$3" "$4" "$5" "$(echo "$3 $base" | awk '{printf "%.1f", $1/$2}')"; }
row "bare" $NB "$r_bare"
row "strace -o /dev/null" $NB "$r_strace"
row "LD_PRELOAD shim (dlsym)" $NB "$r_shim"
row "ltrace -o /dev/null" $NL "$r_lt"
row "ltrace -c -o /dev/null" $NL "$r_ltc"
row "ltrace -e malloc -o /dev/null" $NB "$r_lte"
} > $F
# what ltrace itself does per traced call: count its syscalls
F=$OUT/04-ltrace-syscalls.txt
echo '$ strace -c -o tmp ltrace -o /dev/null ./callloop 10000   (strace tracing ltrace; top of the table)' > $F
strace -c -o lt-sc.txt ltrace -o /dev/null ./callloop 10000 > /dev/null 2>&1
head -12 lt-sc.txt >> $F
echo '$ strace -c -o tmp ltrace -o /dev/null ./callloop 20000' >> $F
strace -c -o lt-sc2.txt ltrace -o /dev/null ./callloop 20000 > /dev/null 2>&1
head -12 lt-sc2.txt >> $F
awk '$4 ~ /^[0-9]+$/ && $NF != "total" {print $NF, $4}' lt-sc.txt | sort > a.txt
awk '$4 ~ /^[0-9]+$/ && $NF != "total" {print $NF, $4}' lt-sc2.txt | sort > b.txt
echo "# per extra labs() call = (count at N=20000 - count at N=10000) / 10000:" >> $F
join a.txt b.txt | awk '$3 > $2 {printf "%-18s %8d %8d  -> %.2f per call\n", $1, $2, $3, ($3-$2)/10000}' >> $F
echo '# which files ltrace opens and reads during the run:' >> $F
echo '$ strace -e trace=openat -o tmp ltrace -o /dev/null ./callloop 3 ; grep -o "\"[^\"]*\"" tmp | sort | uniq -c | sort -rn | head' >> $F
strace -e trace=openat -o lt-open.txt ltrace -o /dev/null ./callloop 3 > /dev/null 2>&1
grep -o '"[^"]*"' lt-open.txt | sort | uniq -c | sort -rn | head -8 >> $F

#### 5. when ltrace sees nothing
F=$OUT/05-truth-table.txt
: > $F
variant() {
	_tag=$1; _src=$2; shift 2
	echo "=== ($_tag) gcc $* $_src -o v" >> $F
	if ! gcc "$@" $S/$_src -o v >> $F 2>&1; then echo "build failed" >> $F; return; fi
	echo "-- readelf -d v | grep -E 'BIND_NOW|FLAGS'" >> $F
	readelf -d v 2>&1 | grep -E 'BIND_NOW|FLAGS|no dynamic' >> $F
	echo "-- readelf -S v | grep plt" >> $F
	readelf -S v | grep plt | awk '{print $2, $3}' >> $F
	echo "-- call instructions in main (objdump -d v)" >> $F
	objdump -d v | awk '/<main>:/,/^$/' | grep -E 'call' | sed 's/^ *[0-9a-f]*:\t\([0-9a-f][0-9a-f] \)*\t*//' | sed 's/^[ \t]*//' | trim 8 >> $F
	if [ "$_src" = hello.c ]; then
		echo "-- ltrace ./v 2>&1 | head -5" >> $F
		ltrace ./v 2>&1 | trim 5 >> $F
	else
		echo "-- ltrace -c ./v 2000 2>&1 | head -8" >> $F
		ltrace -c ./v 2000 2>&1 | trim 8 >> $F
	fi
	echo >> $F
}
variant a hello.c
variant b hello.c -no-pie
variant c hello.c -Wl,-z,now
variant d hello.c -Wl,-z,now -fcf-protection=full
variant d2 hello.c -Wl,-z,now -fcf-protection=full -Wl,-z,ibtplt
variant e hello.c -fno-plt
variant f hello.c -static
variant g hello.c -O2
variant g-shout shout.c -O2
variant a-shout shout.c -O0
echo '=== why (d) has no .plt.sec: GNU property notes of the input crt files' >> $F
echo "-- readelf -n v (d build) | grep -iE 'feature|x86'" >> $F
gcc -Wl,-z,now -fcf-protection=full $S/hello.c -o v; readelf -n v | grep -iE 'feature|x86' >> $F
for c in crt1.o crti.o crtn.o; do p=$(gcc -print-file-name=$c); echo "-- $c: $(readelf -n $p 2>/dev/null | grep -iE 'feature' | tr -s ' ' || true)" >> $F; done

#### 6. calls between libraries
F=$OUT/06-between-libs.txt
set -f   # "-e *" must reach ltrace unexpanded
: > $F
for e in "" "-e *" "-e @libgreet.so" "-e strlen" "-l libgreet.so" "-e write" "-e write@*" "-l libc.so.6" "-x cmp"; do
	if [ "$e" = "-e *" ]; then
		echo "\$ ltrace -e '*' ./usegreet 2>&1 | head -40" >> $F
		ltrace $e ./usegreet 2>&1 | trim 40 >> $F
	else
		echo "\$ ltrace $e ./usegreet 2>&1 | head -14" >> $F
		ltrace $e ./usegreet 2>&1 | trim 14 >> $F
	fi
	echo >> $F
done
set +f

#### 7. ltrace -S
F=$OUT/07-ltrace-S.txt
echo '$ ltrace -S -o tmp ./readline >/dev/null; grep -A40 fopen tmp | head -25   (the dynamic loader startup syscalls before fopen dropped)' > $F
ltrace -S -o lt-S.txt ./readline > /dev/null
echo "[$(awk '/fopen/{print NR-1; exit}' lt-S.txt) lines before fopen dropped]" >> $F
grep -A40 'fopen' lt-S.txt | trim 25 >> $F

echo "== done"
