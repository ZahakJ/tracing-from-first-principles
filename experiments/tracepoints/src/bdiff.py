#!/usr/bin/env python3
# bdiff: print the byte ranges where two dumps of the same function differ,
# and, given objdump listings of both, the instructions around each change.
#   bdiff.py BASEADDR A B [A.s B.s]
import sys
base = int(sys.argv[1], 16)
a, b = open(sys.argv[2], "rb").read(), open(sys.argv[3], "rb").read()
lst = [[l for l in open(f) if l[:1] == " " or l[:1] in "0123456789abcdef"]
       for f in sys.argv[4:6]]

def around(lines, addr):	# 2 instructions before and after the one holding addr
	at = [int(l.split(":")[0], 16) for l in lines]
	i = max(k for k in range(len(at)) if at[k] <= addr)
	return "".join("      " + l.split("\t", 1)[0] + "\t" + "\t".join(l.rstrip().split("\t")[1:]) + "\n"
		       for l in lines[max(i - 2, 0):i + 3])

i, n = 0, 0
while i < min(len(a), len(b)):
	if a[i] == b[i]:
		i += 1
		continue
	j = i
	while j < len(a) and a[j] != b[j]:
		j += 1
	print("  +%#x (%#x): %s  ->  %s" % (i, base + i, a[i:j].hex(" "), b[i:j].hex(" ")))
	if lst:
		print("    before:\n" + around(lst[0], base + i) + "    after:\n" + around(lst[1], base + i))
	n += 1
	i = j
print("  %d changed range(s)" % n)
