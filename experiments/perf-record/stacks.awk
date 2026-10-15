# stacks.awk: read "perf script" output (one sample per paragraph:
# a header line, then one indented line per frame, leaf first) and
# either fold it for a flame graph (mode=fold) or measure how many
# stacks are complete (mode=quality; frames of inlined functions are
# skipped there, so the leaf is the real function the CPU was in).
BEGIN { RS = ""; FS = "\n" }
{
	n = 0
	for (i = 2; i <= NF; i++) {
		if (mode == "quality" && $i ~ /\(inlined\)/)
			continue	# not a real frame: no return address of its own
		split($i, w, " ")
		s = w[2]; sub(/\+0x[0-9a-f]+$/, "", s)
		if (s == "") s = "[unknown]"
		f[++n] = s
	}
	if (n == 0) next
	total++
	st = f[n]; for (i = n - 1; i >= 1; i--) st = st ";" f[i]
	if (mode == "fold") { fold[st]++; next }
	full = (st ~ /(^|;)(main|__libc_start_call_main|__libc_start_main[^;]*|_start)(;|$)/)
	if (full) reach++
	leaf[f[1]]++; if (full) leafreach[f[1]]++
	if (f[1] == "cmp") cmpchain[st]++
}
END {
	if (mode == "fold") { for (s in fold) print s, fold[s]; exit }
	printf "samples %d, stack reaches main: %d (%.1f%%)\n", total, reach, total ? 100 * reach / total : 0
	for (l in leaf) if (l == "checksum" || l == "cmp")
		printf "  leaf %-9s %6d samples, reach main %6d (%.1f%%)\n", l, leaf[l], leafreach[l], 100 * leafreach[l] / leaf[l]
	print "  most common stacks ending in cmp (root;...;leaf):"
	for (s in cmpchain) printf "  %6d  %s\n", cmpchain[s], s | "sort -rn | head -5"
}
