# blktrace: following a write from write() to the disk.
. ../_lib/lib.sh
env_snapshot blktrace blkparse btt strace perf mkfs.ext4
T=/tmp/bt; mkdir -p $T $T/bt; EXPDIR=$(pwd)
gcc -O1 -Wall -o $T/writer src/writer.c
gcc -O1 -Wall -o $T/logger src/logger.c
gcc -O1 -Wall -o $T/seqwrite src/seqwrite.c
W=$T/writer; L=$T/logger; S=$T/seqwrite
TR=/sys/kernel/tracing
DEV=/dev/vdd
MARK=524280	# sector of the last 4 KiB of the disk: we read it as a time marker

# show FILE CMD... : append "$ CMD" and its output to $OUT/FILE
show() { _f=$1; shift; { echo "\$ $*"; "$@" 2>&1; echo; } >> "$OUT/$_f"; }
# bt_start NAME / bt_stop : blktrace of $DEV into $T/bt/NAME.blktrace.<cpu>
bt_start() { BTN=$1; blktrace -d $DEV -D $T/bt -o $1 > $T/$1.btout 2>&1 & BTPID=$!; sleep 1; }
bt_stop() { kill -INT $BTPID; wait $BTPID; }
# marker: one 4 KiB O_DIRECT read of sector $MARK, so the trace has a timestamp we chose
marker() { dd if=$DEV of=/dev/null bs=4096 count=1 skip=65535 iflag=direct 2>/dev/null; }
# parse NAME : default blkparse text into $T/NAME.txt
parse() { blkparse -D $T/bt -i $1 > $T/$1.txt 2>&1; }
# trimmed FILE N : first N lines of FILE, then a count of the rest
trimmed() { head -n $2 $1; _r=$(( $(wc -l < $1) - $2 )); [ $_r -gt 0 ] && echo "[... $_r more lines]"; }
# events NAME : action/process summary counts with a compact blkparse format
events() { blkparse -D $T/bt -i $1 -q -f "%a %d %n %C\n" 2>/dev/null | grep -E '^[A-Z]+ '; }

echo "tracelab: 1 setup"
F=01-setup.txt
echo "Parts 2-9 use the raw disk $DEV (no filesystem): a write at byte offset 0 is sector 0." >> $OUT/$F
echo "Parts 10-14 put ext4 on the same disk afterwards." >> $OUT/$F
echo >> $OUT/$F
for f in scheduler max_sectors_kb max_hw_sectors_kb max_segments nr_requests rotational write_cache logical_block_size; do
	echo "/sys/block/vdd/queue/$f: $(cat /sys/block/vdd/queue/$f)"
done >> $OUT/$F
echo >> $OUT/$F
show $F sysctl vm.dirty_expire_centisecs vm.dirty_writeback_centisecs vm.dirty_background_ratio vm.dirty_ratio
sync; sleep 1

echo "tracelab: 2 buffered write"
F=02-buffered.txt
bt_start buffered
marker
T0=$(cut -d' ' -f1 /proc/uptime)
{
	echo "\$ ./writer buffered $DEV   (uptime $T0 s; marker read of sector $MARK just before)"
	$W buffered $DEV
	echo
	echo "polling once a second: meminfo Dirty/Writeback and vdd writes completed (/sys/block/vdd/stat field 5)"
} > $OUT/$F
got=; i=0
poll() { echo "+${1}s $(grep -E '^(Dirty|Writeback):' /proc/meminfo | tr -s ' ' | tr '\n' ' ') vdd_writes=$(awk '{print $5}' /sys/block/vdd/stat)" >> $OUT/$F; }
while [ $i -lt 40 ]; do
	sleep 1; i=$((i+1)); poll $i
	[ "$(awk '{print $5}' /sys/block/vdd/stat)" -gt 0 ] && { got=1; sleep 1; i=$((i+1)); poll $i; break; }
done
if [ -z "$got" ]; then
	echo "nothing written after 40 s: lowering vm.dirty_expire_centisecs to 500" >> $OUT/$F
	sysctl -w vm.dirty_expire_centisecs=500 >> $OUT/$F
	while [ $i -lt 55 ]; do
		sleep 1; i=$((i+1)); poll $i
		[ "$(awk '{print $5}' /sys/block/vdd/stat)" -gt 0 ] && break
	done
	sysctl -w vm.dirty_expire_centisecs=3000 >> $OUT/$F
fi
bt_stop
parse buffered
SEC=0
{
	echo
	echo "data = byte offset 0 of $DEV = sector $SEC"
	echo
	echo "--- blkparse lines for the marker read (sector $MARK) and the data (sector $SEC):"
	grep -E " ($MARK|$SEC) \+ " $T/buffered.txt
	echo
	awk -v m=$MARK -v s=$SEC '$6=="Q" && $8==m && !tm {tm=$4} $6=="Q" && $8==s && !ts {ts=$4; p=$NF} END {printf "marker Q at %s s, data Q at %s s by %s: data queued %.3f s after write()\n", tm, ts, p, ts-tm}' $T/buffered.txt
	echo
	echo "--- whole blkparse output (trace events only):"
	grep -E '^ *[0-9]+,[0-9]+ ' $T/buffered.txt > $T/buffered.ev
	trimmed $T/buffered.ev 70
	echo
	echo "--- blkparse summary:"
	sed -n '/^CPU[0-9]* (/,$p' $T/buffered.txt | head -n 60
	echo
	echo "--- blktrace's own exit report:"
	cat $T/buffered.btout
} >> $OUT/$F

echo "tracelab: 3 fsync and direct"
for m in fsync direct; do
	F=03-$m.txt
	bt_start $m
	show $F $W $m $DEV
	sleep 1
	bt_stop
	parse $m
	{
		echo "--- blkparse (trace events):"
		grep -E '^ *[0-9]+,[0-9]+ ' $T/$m.txt > $T/$m.ev
		trimmed $T/$m.ev 60
		echo
		echo "--- blkparse summary:"
		sed -n '/^CPU[0-9]* (/,$p' $T/$m.txt | head -n 20
	} >> $OUT/$F
done

F=03-timing.txt
echo "writer without any tracing, 7 runs each: median min max n (us)" > $OUT/$F
for m in buffered fsync direct; do
	for i in 1 2 3 4 5 6 7; do $W $m $DEV; done > $T/tm.txt
	echo "$m write(): $(awk '/^write/ {print $3}' $T/tm.txt | stats)" >> $OUT/$F
	[ $m = fsync ] && echo "fsync fsync(): $(awk '/^fsync/ {print $3}' $T/tm.txt | stats)" >> $OUT/$F
done

echo "tracelab: 5 logger + btt"
F=05-btt.txt
bt_start logger
show $F $L 200 $DEV
bt_stop
blkparse -D $T/bt -i logger -d $T/bp.bin -O > /dev/null 2>&1
{
	echo "\$ blkparse -D bt -i logger -d bp.bin -O; btt -i bp.bin -A   (sections trimmed)"
	btt -i $T/bp.bin -A 2>&1 | awk '/^=+ .* =+$/ {keep = /All Devices|Per Process|Device Overhead|Device Merge/} keep' | head -n 80
	echo
	echo "--- D (issue) events by process and RWBS, and per fdatasync (200):"
	events logger | awk '$1=="D" {k=$4 " " $2; n[k]++; s[k]+=$3} END {for (k in n) printf "%-14s %-6s D=%4d  per fsync %.2f  mean %.1f sectors\n", substr(k,1,index(k," ")-1), substr(k,index(k," ")+1), n[k], n[k]/200, s[k]/n[k]}' | sort
	echo
	echo "--- from the blkparse text, per fdatasync (paired in order), us: n mean min max"
	parse logger
	awk '$6=="Q" && $7=="WS" && $9=="+" {dq[++a]=$4} $6=="D" && $7=="WS" && $9=="+" {dd[++b]=$4}
	     $6=="C" && $7=="WS" && $9=="+" {dc[++c]=$4} $6=="Q" && $7=="FWS" {fq[++d]=$4}
	     $6=="D" && $7=="FN" {fd[++e]=$4} $6=="C" && $7=="FN" {fc[++f]=$4} $6=="C" && $7=="WS" && $9!="+" {fwc[++g]=$4}
	     function st(name, x, y, n,   i, v, s, lo, hi) { lo=1e9; hi=0; s=0
		for (i=1; i<=n; i++) { v=(x[i]-y[i])*1e6; s+=v; if (v<lo) lo=v; if (v>hi) hi=v }
		printf "%-44s %4d %9.1f %9.1f %9.1f\n", name, n, s/n, lo, hi }
	     END { st("data D2C (D WS -> C WS)", dc, dd, b); st("flush D2C (D FN -> C FN)", fc, fd, e);
		   st("flush Q2C (Q FWS -> C WS, no size)", fwc, fq, d); st("data C -> flush Q (CPU, back in fsync)", fq, dc, d);
		   st("whole fsync in block layer (data Q -> flush C)", fwc, dq, g) }' $T/logger.txt
	echo
	echo "--- all actions by count:"
	events logger | awk '{n[$1]++} END {for (a in n) print a, n[a]}' | sort
} >> $OUT/$F

echo "tracelab: 6 merging and splitting"
F=06-merge.txt
# sizes NAME : counts of each action, and the size distribution of write requests at D
sizes() {
	echo "action counts: $(events $1 | awk '{n[$1]++} END {for (a in n) printf "%s=%d ", a, n[a]}')"
	echo "D sizes (sectors, RWBS, process -> count):"
	events $1 | awk '$1=="D" {print $3, $2, $4}' | sort | uniq -c | sort -k2,2n | head -n 20
}
orig=$(cat /sys/block/vdd/queue/max_sectors_kb)
bt_start merge1
show $F $S buffered 2048 $DEV
sleep 1; bt_stop
sizes merge1 >> $OUT/$F
echo >> $OUT/$F
echo "\$ echo 64 > /sys/block/vdd/queue/max_sectors_kb   (was $orig)" >> $OUT/$F
echo 64 > /sys/block/vdd/queue/max_sectors_kb
bt_start merge2
show $F $S buffered 2048 $DEV
sleep 1; bt_stop
sizes merge2 >> $OUT/$F
echo "X (split) lines:" >> $OUT/$F
parse merge2; grep -E '^ *[0-9]+,[0-9]+ .* X ' $T/merge2.txt | head -n 5 >> $OUT/$F
bt_start merge2x
show $F dd if=/dev/zero of=$DEV bs=1M count=2 oflag=direct
sleep 1; bt_stop
sizes merge2x >> $OUT/$F
parse merge2x; echo "first 24 events of the dd run:" >> $OUT/$F
grep -E '^ *[0-9]+,[0-9]+ ' $T/merge2x.txt | head -n 24 >> $OUT/$F
echo $orig > /sys/block/vdd/queue/max_sectors_kb
echo >> $OUT/$F
bt_start merge3
show $F $S direct 2048 $DEV
sleep 1; bt_stop
sizes merge3 >> $OUT/$F
parse merge3
echo "first 30 events of the O_DIRECT run:" >> $OUT/$F
grep -E '^ *[0-9]+,[0-9]+ ' $T/merge3.txt | grep seqwrite | head -n 30 >> $OUT/$F

echo "tracelab: 7 without blktrace"
F=07a-tracepoints.txt
echo > $TR/trace
echo 1 > $TR/events/block/block_rq_issue/enable
echo 1 > $TR/events/block/block_rq_complete/enable
show $F $W fsync $DEV
sleep 1
echo 0 > $TR/events/block/block_rq_issue/enable
echo 0 > $TR/events/block/block_rq_complete/enable
{ echo "\$ cat $TR/trace   (block_rq_issue + block_rq_complete enabled)"; grep -v '^#' $TR/trace > $T/tp.txt; trimmed $T/tp.txt 30; } >> $OUT/$F
F=07b-blk-tracer.txt
{
	echo "\$ echo 1 > /sys/block/vdd/trace/enable; echo blk > $TR/current_tracer"
	echo "available_tracers: $(cat $TR/available_tracers)"
	ls /sys/block/vdd/trace/
} > $OUT/$F
echo 1 > /sys/block/vdd/trace/enable 2>> $OUT/$F
echo blk > $TR/current_tracer 2>> $OUT/$F
echo > $TR/trace
show $F $W fsync $DEV
sleep 1
{ echo "\$ cat $TR/trace"; grep -v '^#' $TR/trace > $T/blk.txt; trimmed $T/blk.txt 40; } >> $OUT/$F
echo nop > $TR/current_tracer
echo 0 > /sys/block/vdd/trace/enable
F=07c-plumbing.txt
bt_start plumb
show $F ls -la /sys/kernel/debug/block/vdd/
bt_stop
strace -f -e trace=ioctl -o $T/st.txt blktrace -d $DEV -w 1 -D $T/bt -o st > /dev/null 2>&1
{ echo "\$ strace -f -e trace=ioctl -o st.txt blktrace -d /dev/vdd -w 1   (BLKTRACE* ioctls only)"; grep -E 'BLKTRACE|0x1274|0xc0481273|0x1275|0x1276' $T/st.txt | head -n 20; echo "(st.txt has $(wc -l < $T/st.txt) lines in total)"; } >> $OUT/$F

echo "tracelab: 8 price"
F=08-price.txt
echo "seqwrite direct 20000 (4 KiB O_DIRECT writes, no fsync), us per write; runs alternate" > $OUT/$F
rm -f $T/p0 $T/p1 $T/sz
for i in 1 2 3 4 5; do
	$S direct 20000 $DEV | awk '{print $6}' >> $T/p0
	bt_start price$i
	$S direct 20000 $DEV | awk '{print $6}' >> $T/p1
	bt_stop
	du -cb $T/bt/price$i.blktrace.* | tail -n 1 | cut -f1 >> $T/sz
	[ $i = 1 ] && { echo "blktrace exit report, run 1:"; cat $T/price1.btout; } >> $OUT/$F
	rm -f $T/bt/price$i.*
done
{
	echo "without blktrace: median min max n = $(stats < $T/p0)   (all: $(tr '\n' ' ' < $T/p0))"
	echo "with blktrace:    median min max n = $(stats < $T/p1)   (all: $(tr '\n' ' ' < $T/p1))"
	echo "trace size bytes: median min max n = $(stats < $T/sz)"
	echo "bytes per 4 KiB write = median size / 20000 = $(stats < $T/sz | awk '{printf "%.1f", $1/20000}')"
} >> $OUT/$F

echo "tracelab: 9 application side"
F=09-appview.txt
show $F strace -c -w $L 200 $DEV
show $F perf trace -s $L 200 $DEV
echo "tracelab: done"

# ---- the filesystem half: ext4 on the same disk ----
echo "tracelab: 10 ext4"
F=10-ext4-setup.txt
show $F mkfs.ext4 -F -q -b 4096 -E lazy_itable_init=0,lazy_journal_init=0 $DEV
mkdir -p /mnt
show $F mount -t ext4 $DEV /mnt
grep ' /mnt ' /proc/mounts >> $OUT/$F
{ echo "\$ dumpe2fs -h $DEV | grep -E 'Block size|Journal size|Default mount|features'"; dumpe2fs -h $DEV 2>/dev/null | grep -E 'Block size|Journal size|Default mount|features'; } >> $OUT/$F
sync; sleep 1
# agg: a compact blkparse text of NAME with only real events; d2c NAME [agg]
evtext() { grep -E '^ *[0-9]+,[0-9]+ ' $T/$1.txt; }
d2c() { evtext $1 | awk -v agg=${2:-0} -f $EXPDIR/d2c.awk; }

echo "tracelab: 11 ext4 fsync"
for m in fsync buffered direct; do
	F=11-ext4-$m.txt
	bt_start e$m
	show $F $W $m /mnt/$m.dat
	sleep 1; bt_stop; parse e$m
	{ echo "--- blkparse events:"; evtext e$m > $T/e.ev; trimmed $T/e.ev 70; echo; echo "--- D2C of each request:"; d2c e$m; } >> $OUT/$F
	[ $m = fsync ] && filefrag -v /mnt/fsync.dat | tr -d ".:" | awk '$1=="0" {print "data block of fsync.dat: fs block " $4 " = sector " ($4+0)*8}' >> $OUT/$F
done

echo "tracelab: 12 ext4 logger"
F=12-ext4-logger.txt
bt_start elog
show $F $L 200 /mnt/log.dat
bt_stop; parse elog
{
	echo "--- D events by RWBS and process, mean D2C (paired D->C):"
	d2c elog 1 | sort
	echo
	echo "--- D (issue) count per fdatasync, by process:"
	events elog | awk '$1=="D" {n[$4]++; t++} END {for (p in n) printf "%-16s %5d  %.2f per fdatasync\n", p, n[p], n[p]/200; printf "total D %d = %.2f per fdatasync\n", t, t/200}'
	echo
	echo "--- bytes written to the device (sectors at D with W in RWBS) per 4 KiB of payload:"
	events elog | awk '$1=="D" && $2 ~ /W/ {s += $3} END {printf "%d sectors = %d bytes for 819200 bytes of payload: %.2f x\n", s, s*512, s*512/819200}'
	echo
	echo "--- one fdatasync from the middle (events 100th fdatasync window):"
	evtext elog | awk '$6=="Q" && $7 ~ /W/ && $9=="+" && $11=="[logger]" {q++} q==100' | head -n 30
} >> $OUT/$F

echo "tracelab: 13 ext4 buffered, nothing forcing it"
F=13-ext4-background.txt
bt_start ebg
marker
{ echo "\$ ./writer buffered /mnt/bg.dat   (marker read of sector $MARK just before; data=ordered, default commit)"; $W buffered /mnt/bg.dat; } > $OUT/$F
i=0; got=0
while [ $i -lt 50 ]; do
	sleep 1; i=$((i+1))
	ph=$(filefrag -v /mnt/bg.dat 2>/dev/null | awk '$1=="0:" {print $4}' | tr -d '.:')
	echo "+${i}s $(grep -E '^(Dirty|Writeback):' /proc/meminfo | tr -s ' ' | tr '\n' ' ') vdd_writes=$(awk '{print $5}' /sys/block/vdd/stat) block=$( case "$ph" in ''|0|*[!0-9]*) echo "not allocated yet";; *) echo $ph;; esac )" >> $OUT/$F
	# filefrag shows physical block 0 while the block is not allocated yet (delayed allocation)
	case $ph in ''|0|*[!0-9]*) ph=;; *) got=$((got+1)); [ $got -ge 3 ] && break;; esac
done
bt_stop; parse ebg
PH=$(filefrag -v /mnt/bg.dat | awk '$1=="0:" {print $4}' | tr -d '.:')
{
	echo "data block $PH = sector $((PH*8))"
	echo "--- all events, time in s after the marker read:"
	evtext ebg > $T/e.ev; trimmed $T/e.ev 60
	echo "--- D2C:"; d2c ebg
} >> $OUT/$F

echo "tracelab: 14 batch"
F=14-ext4-batch.txt
bt_start ebatch
show $F $S buffered 200 /mnt/batch.dat
sleep 1; bt_stop; parse ebatch
{ echo "--- D events by RWBS and process (200 x 4 KiB writes, one fsync at the end):"; d2c ebatch 1 | sort; events ebatch | awk '$1=="D" && $2 ~ /W/ {s+=$3; n++} END {printf "write requests %d, %d bytes for 819200 bytes of payload\n", n, s*512}'; } >> $OUT/$F
umount /mnt
echo "tracelab: done ext4"
