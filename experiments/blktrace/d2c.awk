# d2c.awk: pair blkparse D and C lines (default text format) and print D2C.
# Sized requests pair by start sector, flushes (no sector) in order.
# agg=1: print n and mean D2C per (RWBS at D, process) instead of each line.
function out(us, what, proc) {
	if (agg) { split(what, w, " "); k = w[1] " " proc; n[k]++; s[k] += us; return }
	printf "D2C %9.1f us  %-8s %s\n", us, what, proc
}
$6 == "D" && $9 == "+" { dt[$8] = $4; rw[$8] = $7 " " $8 "+" $10; pr[$8] = $11 }
$6 == "D" && $9 != "+" { fd[++nd] = $4; frw[nd] = $7; fpr[nd] = $8 }
$6 == "C" && $9 == "+" && ($8 in dt) { out(($4 - dt[$8]) * 1e6, rw[$8], pr[$8]); delete dt[$8] }
$6 == "C" && $9 != "+" && $7 ~ /^F/ { nc++; out(($4 - fd[nc]) * 1e6, frw[nc], fpr[nc]) }
END { if (agg) for (k in n) { split(k, a, " "); printf "%-8s %-20s n=%4d  mean D2C %8.1f us\n", a[1], a[2], n[k], s[k] / n[k] } }
