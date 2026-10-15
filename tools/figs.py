#!/usr/bin/env python3
"""Figures and banners for the notes, drawn from the numbers in results/.

    python3 tools/figs.py            # writes figures/*.svg and figures/*.png

Each figure is a dark panel with its own background. PNGs are made with
rsvg-convert.
"""
import html, math, os, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "figures")
SURFACE, INK, INK2, INK3, GRID = "#1a1a19", "#ffffff", "#c3c2b7", "#8f8e86", "#2e2e2b"
BLUE, ORANGE, AQUA = "#3987e5", "#d95926", "#199e70"
SANS, MONO = "DejaVu Sans, sans-serif", "JetBrainsMono Nerd Font Mono, DejaVu Sans Mono, monospace"


def esc(s):
    return html.escape(str(s), quote=True)


def text(x, y, s, size=13, fill=INK2, anchor="start", weight="normal", font=SANS, extra=""):
    return (f'<text x="{x:.1f}" y="{y:.1f}" font-family="{font}" font-size="{size}" fill="{fill}" '
            f'text-anchor="{anchor}" font-weight="{weight}" {extra}>{esc(s)}</text>')


def save(name, w, h, body):
    svg = (f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">'
           f'<rect width="{w}" height="{h}" rx="10" fill="{SURFACE}"/>{"".join(body)}</svg>')
    path = os.path.join(OUT, name + ".svg")
    open(path, "w").write(svg)
    subprocess.run(["rsvg-convert", "-z", "2", "-o", path[:-4] + ".png", path], check=True)
    print("wrote", os.path.relpath(path[:-4] + ".png", ROOT))


def fmt(v):
    if v >= 1e6:
        return f"{v/1e6:.3g} ms"
    if v >= 1000:
        return f"{v/1000:.3g} µs"
    return f"{v:.3g} ns"


def dots_log(name, title, subtitle, rows, unit_fmt=fmt, lo=None, hi=None, left=None, width=760):
    """A dot plot on a log axis. rows: (label, value) or (label, value, colour)."""
    vals = [r[1] for r in rows]
    lo = lo or 10 ** math.floor(math.log10(min(vals)))
    hi = hi or 10 ** math.ceil(math.log10(max(vals)))
    right, top, rowh = 112, 80, 34
    left = left or 24 + int(max(len(r[0]) for r in rows) * 9.1) + 16
    h = top + rowh * len(rows) + 48
    plot = width - left - right
    X = lambda v: left + plot * (math.log10(v) - math.log10(lo)) / (math.log10(hi) - math.log10(lo))
    b = [text(24, 34, title, 18, INK, weight="bold"), text(24, 58, subtitle, 15, INK3)]
    d = math.log10(lo)
    while d <= math.log10(hi) + 1e-9:
        x = X(10 ** d)
        b.append(f'<line x1="{x:.1f}" y1="{top-6}" x2="{x:.1f}" y2="{h-40}" stroke="{GRID}" stroke-width="1"/>')
        b.append(text(x, h - 20, unit_fmt(10 ** d), 14.5, INK3, "middle"))
        d += 1
    for i, r in enumerate(rows):
        label, v = r[0], r[1]
        col = r[2] if len(r) > 2 else BLUE
        y = top + rowh * i + rowh / 2
        b.append(text(left - 16, y + 5.5, label, 16.5, INK2, "end"))
        b.append(f'<line x1="{left}" y1="{y}" x2="{X(v):.1f}" y2="{y}" stroke="{col}" stroke-width="2" opacity="0.45"/>')
        b.append(f'<circle cx="{X(v):.1f}" cy="{y}" r="6" fill="{col}" stroke="{SURFACE}" stroke-width="2"/>')
        b.append(text(X(v) + 13, y + 5.5, unit_fmt(v), 16.5, INK, font=SANS))
    save(name, width, h, b)


def bars(name, title, subtitle, rows, unit="", width=760, fmtv=lambda v: f"{v:g}", left=300):
    """Horizontal bars on a linear axis from zero. rows: (label, value[, colour])."""
    top, rowh, right = 74, 32, 120
    h = top + rowh * len(rows) + 22
    plot = width - left - right
    vmax = max(r[1] for r in rows)
    b = [text(24, 32, title, 16, INK, weight="bold"), text(24, 53, subtitle, 12.5, INK3)]
    b.append(f'<line x1="{left}" y1="{top-6}" x2="{left}" y2="{h-16}" stroke="{GRID}" stroke-width="1"/>')
    for i, r in enumerate(rows):
        label, v = r[0], r[1]
        col = r[2] if len(r) > 2 else BLUE
        y = top + rowh * i + 6
        wpx = max(2, plot * v / vmax)
        b.append(text(left - 14, y + 14.5, label, 13, INK2, "end"))
        b.append(f'<path d="M{left},{y} h{wpx-4:.1f} a4,4 0 0 1 4,4 v12 a4,4 0 0 1 -4,4 h-{wpx-4:.1f} z" fill="{col}"/>')
        b.append(text(left + wpx + 10, y + 14.5, fmtv(v) + unit, 12.5, INK))
    save(name, width, h, b)


def pairs(name, title, subtitle, panels, labels, width=760, colors=(BLUE, ORANGE)):
    """Small multiples: each panel compares a few cases on its own scale.
    panels: (panel title, [values...], formatter[, labels for this panel])."""
    top, gap, left = 84, 14, 24
    all_labels = [l for p in panels for l in (p[3] if len(p) > 3 else labels)]
    lab_w = 24 + int(max(len(l) for l in all_labels) * 9.1)
    b = [text(24, 34, title, 18, INK, weight="bold"), text(24, 58, subtitle, 15, INK3)]
    y0 = top
    for panel in panels:
        ptitle, vals, f = panel[:3]
        plabels = panel[3] if len(panel) > 3 else labels
        b.append(text(left, y0 + 6, ptitle, 16, INK, weight="bold"))
        vmax = max(vals)
        plot = width - left - lab_w - 150
        for i, v in enumerate(vals):
            y = y0 + 20 + 30 * i
            wpx = max(5, plot * v / vmax)
            b.append(text(left + lab_w - 12, y + 15.5, plabels[i], 16.5, INK2, "end"))
            b.append(f'<path d="M{left+lab_w},{y} h{wpx-4:.1f} a4,4 0 0 1 4,4 v12 a4,4 0 0 1 -4,4 h-{wpx-4:.1f} z" fill="{colors[i % len(colors)]}"/>')
            b.append(text(left + lab_w + wpx + 10, y + 15.5, f(v), 16.5, INK))
        y0 += 30 * len(vals) + 44 + gap
    save(name, width, y0 - gap + 4, b)


def lanes(name, title, subtitle, lane_names, steps, width=760, note=None):
    """A sequence picture: vertical lanes, time runs downward.
    steps: (from_lane, to_lane, label) draws an arrow; (lane, None, label) a note on one lane;
    ("gap", None, label) a dashed pause across all lanes."""
    top, rowh = 112, 40
    h = top + rowh * len(steps) + 30 + (26 if note else 0)
    n = len(lane_names)
    xs = [width * (i + 0.5) / n for i in range(n)]
    b = [text(24, 34, title, 18, INK, weight="bold"), text(24, 58, subtitle, 15, INK3),
         f'<defs><marker id="ah" markerWidth="9" markerHeight="8" refX="8" refY="4" orient="auto">'
         f'<path d="M0,0 L9,4 L0,8 z" fill="{INK2}"/></marker></defs>']
    for x, nm in zip(xs, lane_names):
        b.append(f'<rect x="{x-92:.1f}" y="74" width="184" height="26" rx="5" fill="{GRID}"/>')
        b.append(text(x, 92, nm, 15, INK, "middle", weight="bold"))
        b.append(f'<line x1="{x:.1f}" y1="100" x2="{x:.1f}" y2="{top + rowh*len(steps) + 8}" stroke="{GRID}" stroke-width="2"/>')
    for i, (a, c, label) in enumerate(steps):
        y = top + rowh * i + 22
        if a == "gap":
            b.append(f'<line x1="24" y1="{y-6}" x2="{width-24}" y2="{y-6}" stroke="{INK3}" stroke-width="1" stroke-dasharray="3 5"/>')
            b.append(text(width / 2, y - 12, label, 13.5, INK3, "middle"))
        elif c is None:
            x = xs[a]
            wbox = max(120, len(label) * 8.8 + 22)
            x0 = min(max(x - wbox / 2, 12), width - wbox - 12)
            b.append(f'<rect x="{x0:.1f}" y="{y-18}" width="{wbox:.1f}" height="27" rx="5" fill="{SURFACE}" stroke="{BLUE}" stroke-width="1.5"/>')
            b.append(text(x0 + wbox / 2, y, label, 15, INK, "middle"))
        else:
            x1, x2 = xs[a], xs[c]
            d = 1 if x2 > x1 else -1
            b.append(f'<line x1="{x1 + 3*d:.1f}" y1="{y}" x2="{x2 - 4*d:.1f}" y2="{y}" stroke="{INK2}" stroke-width="2" marker-end="url(#ah)"/>')
            b.append(text((x1 + x2) / 2, y - 8, label, 15, INK2, "middle",
                          extra=f'paint-order="stroke" stroke="{SURFACE}" stroke-width="5" stroke-linejoin="round"'))
    if note:
        b.append(text(24, h - 16, note, 13.5, INK3))
    save(name, width, h, b)


def banner(name, lines, accent=BLUE):
    """A banner made of real output: a few lines of monospace, fading out to the right."""
    w, h = 1600, 360
    b = [f'<defs><linearGradient id="fade" x1="0" x2="1"><stop offset="0.55" stop-color="{SURFACE}" stop-opacity="0"/>'
         f'<stop offset="1" stop-color="{SURFACE}" stop-opacity="1"/></linearGradient>'
         f'<linearGradient id="glow" x1="0" x2="1" y1="0" y2="1"><stop offset="0" stop-color="{accent}" stop-opacity="0.20"/>'
         f'<stop offset="0.6" stop-color="{accent}" stop-opacity="0"/></linearGradient></defs>',
         f'<rect width="{w}" height="{h}" fill="url(#glow)"/>']
    y = 78
    for i, ln in enumerate(lines):
        hot = ln.startswith(">")
        s = ln[1:] if hot else ln
        b.append(text(56, y, s, 27, INK if hot else INK3, font=MONO, weight="bold" if hot else "normal",
                      extra='xml:space="preserve"'))
        y += 46
    b.append(f'<rect width="{w}" height="{h}" fill="url(#fade)"/>')
    b.append(f'<rect x="0" y="0" width="6" height="{h}" fill="{accent}"/>')
    b.append(text(w - 48, h - 34, "TRACING FROM FIRST PRINCIPLES", 17, INK3, "end", font=SANS, extra='letter-spacing="3"'))
    svg = (f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">'
           f'<rect width="{w}" height="{h}" fill="{SURFACE}"/>{"".join(b)}</svg>')
    path = os.path.join(OUT, name + ".svg")
    open(path, "w").write(svg)
    subprocess.run(["rsvg-convert", "-o", path[:-4] + ".png", path], check=True)
    print("wrote", os.path.relpath(path[:-4] + ".png", ROOT))


def read(path):
    return open(os.path.join(ROOT, "results", path)).read()


def med(path, key):
    """First number after `key` on its line in a results file."""
    for ln in read(path).splitlines():
        if ln.startswith(key):
            return float(ln[len(key):].split()[0])
    raise KeyError(key)


def six_ways():
    c = "mechanisms/08-cost.txt"
    step = float(read("mechanisms/07-step.txt").split(" ns per instruction")[0].split()[-1])
    shim = med(c, "malloc+free, with shim.so") - med(c, "malloc+free, no shim")
    rows = [
        ("5 · doorway: preloaded shim, per call", shim),
        ("1 · tell: binary record in memory", med(c, "ring (rdtsc -> memory)")),
        ("2 · compiler hooks, per call", med(c, "compiler hooks (enter+exit)")),
        ("1 · tell: printf through stdio", med(c, "printf (text -> stdio -> file)")),
        ("1 · tell: one write() per line", med(c, "write (text -> write() each)")),
        ("6 · single-step, per instruction", step),
        ("4 · breakpoint via ptrace, per hit", med(c, "breakpoint via ptrace")),
    ]
    dots_log("six-ways-cost", "What one event costs", "nanoseconds per event, log scale",
             rows, lo=0.1, hi=100000)
    banner("six-ways-banner", [
        "171212157926415 make_record",
        ">   435   80.9%  checksum",
        "code at 0x401330 was 015e8d53fd894855, is now 015e8d53fd8948cc",
        "malloc: 200002 calls, 8739041 bytes",
        ">2714158 instructions, 6126 ns per instruction",
        "call   4014d0 <__cyg_profile_func_enter>",
    ])


def six_ways_bp():
    lanes("six-ways-breakpoint", "One hit of a ptrace breakpoint",
          "time runs downward; every arrow that reaches the tracer is a switch between processes",
          ["the program", "the kernel", "the tracer (bp)"], [
              (0, 1, "executes 0xCC: trap"),
              (1, 2, "stop the program, wake the tracer"),
              (2, 1, "read registers, restore the byte, rip - 1"),
              (2, 1, "PTRACE_SINGLESTEP"),
              (1, 0, "run exactly one instruction"),
              (0, 1, "trap again"),
              (1, 2, "wake the tracer"),
              (2, 1, "write 0xCC back, PTRACE_CONT"),
              (1, 0, "resume"),
          ], note="measured: 14,637 ns per hit (results/mechanisms/08-cost.txt)")


def strace():
    lanes("strace-stops", "One system call under strace",
          "the program is stopped twice, and each stop wakes the tracer",
          ["the program", "the kernel", "strace"], [
              (0, 1, "syscall instruction"),
              (1, 2, "stop 1, on the way in: wake strace"),
              (2, 1, "read registers, PTRACE_SYSCALL"),
              (1, None, "the kernel does the work"),
              (1, 2, "stop 2, on the way out: wake strace"),
              (2, 1, "read registers, PTRACE_SYSCALL"),
              (1, 0, "back to the program"),
          ], note="measured: 265 ns alone, 13,217 ns under strace (results/strace/06-cost-sysloop.txt)")
    # results/strace/06-cost-sysloop.txt, ns per getppid(), medians of 5
    dots_log("strace-cost", "What one system call costs",
             "ns per getppid() call, log scale; medians of 5 runs", [
                 ("alone", 264.9),
                 ("strace -f --seccomp-bpf -e trace=openat", 261.0),
                 ("the 55-line toy, counting only", 11392.3),
                 ("strace -e trace=openat", 11413.8),
                 ("strace -c", 12550.3),
                 ("strace", 13217.1),
             ], lo=100, hi=100000)
    banner("strace-banner", [
        'openat(AT_FDCWD, "/etc/ld.so.cache", O_RDONLY|O_CLOEXEC) = 3',
        '>openat(AT_FDCWD, "/etc/liar/liar.conf", O_RDONLY) = -1 ENOENT (No such file or directory)',
        '>openat(AT_FDCWD, "/tmp/.liar.conf", O_RDONLY) = -1 ENOENT (No such file or directory)',
        '>openat(AT_FDCWD, "./liar.conf", O_RDONLY) = -1 ENOENT (No such file or directory)',
        'liar: startup failed',
        '+++ exited with 1 +++',
    ], ORANGE)


def ltrace():
    lanes("ltrace-plt", "A call into a shared library",
          "every call to strlen, from anywhere in the program, passes through one stub",
          ["main()", "strlen@plt (the stub)", "strlen in libc"], [
              (0, 1, "call 1050 <strlen@plt>"),
              (1, None, "first byte ff -> cc under ltrace"),
              (1, 2, "jmp *pointer (set by the dynamic linker)"),
              (2, None, "the real strlen runs"),
              (2, 0, "ret, straight back to main"),
          ])
    banner("ltrace-banner", [
        'strlen("hello world hello wo")                   = 20',
        ">toupper('h')                                     = 'H'",
        'strlen("Hello world hello wo")                   = 20',
        ">toupper('e')                                     = 'E'",
        'strlen("HEllo world hello wo")                   = 20',
        ">puts stub at 0x401030: cc 25 ca 2f",
    ], AQUA)


def mtrace():
    # results/mtrace/06-cost.txt, ns per malloc+free pair, medians of 5
    dots_log("mtrace-cost", "What watching malloc costs",
             "ns per malloc+free pair on an allocator stress test, log scale; medians of 5 runs", [
                 ("alone", 7.3),
                 ("counting shim (LD_PRELOAD)", 8.4),
                 ("heaptrack: the whole stack", 101.4),
                 ("AddressSanitizer", 284.6),
                 ("mtrace, log sent to /dev/null", 302.3),
                 ("mtrace: one line of text per event", 447.4),
                 ("Valgrind memcheck", 700.0),
                 ("ltrace -e malloc+free", 112411),
             ], lo=1, hi=1000000)
    banner("mtrace-banner", [
        "= Start",
        "@ ./leaky:[0x1284] + 0x562f2c2a12a0 0x18",
        ">@ ./leaky:[0x12d1] + 0x562f2c2a14c0 0x100",
        "@ ./leaky:[0x1403] - 0x562f2c2a14c0",
        ">Memory not freed:",
        ">0x0000562f2c2a14c0    0x100  at /tmp/experiments/mtrace/src/leaky.c:43",
    ], BLUE)


def gprof():
    pct = lambda v: f"{v:.1f}%"
    # results/gprof-uftrace/03-gprof-callgraph.txt, 06-uftrace-graph.txt
    pairs("gprof-guess", "Who gets charged for spin()?",
          "share of spin's 1.1 s attributed to each caller, three ways", [
              ("charged to slow_path (100 long calls)", [99.02, 1.0, 98.98], pct),
              ("charged to fast_path (9,900 short calls)", [0.98, 99.0, 1.02], pct),
          ], ["stopwatch", "gprof", "uftrace"], colors=(AQUA, ORANGE, BLUE))
    banner("gprof-banner", [
        "index % time    self  children    called     name",
        "                0.01    0.00     100/10000       slow_path [4]",
        ">                1.09    0.00    9900/10000       fast_path [3]",
        ">[1]    100.0    1.10    0.00   10000         spin [1]",
        "   11.412 ms :  | (9900) spin",
        ">    1.109  s :    (100) spin",
    ], ORANGE)


def perf_stat():
    g = lambda v: f"{v/1e9:.2f} billion"
    m = lambda v: f"{v/1e6:.0f} million"
    # results/perf-stat/01-sum2d.txt
    pairs("perf-stat-same-work", "Same instructions, twenty times the cycles",
          "summing a 256 MiB matrix by rows and by columns", [
              ("instructions executed", [1688919639, 1697088872], g),
              ("clock cycles", [468855677, 9985374605], g),
              ("reads that missed the first-level cache", [25491276, 420542443], m),
          ], ["by rows", "by columns"])
    banner("perf-stat-banner", [
        "        2587474189      instructions:u",
        "        2587474189      instructions:u",
        "        2587474189      instructions:u",
        "        2587474189      instructions:u",
        "        2587474189      instructions:u",
        ">                40      instructions:u",
    ], BLUE)


def flame(name, title, subtitle, folded_path, kinds, width=760, min_frac=0.004, drop_roots=0):
    """A flame graph from folded stacks ("a;b;c 123" per line). Each box sits on its caller;
    width = number of samples. Consecutive identical frames (recursion) are merged.
    kinds: function(name) -> index into the colour list / legend."""
    legend = ["the program's own code", "the C library", "the kernel"]
    cols = [BLUE, ORANGE, AQUA]
    root = {"n": 0, "kids": {}}
    for ln in open(os.path.join(ROOT, "results", folded_path)):
        stack, n = ln.rsplit(None, 1)
        frames = []
        for f in stack.split(";")[drop_roots:]:
            f = f.replace(" (inlined)", "")
            if not frames or frames[-1] != f:
                frames.append(f)
        node = root
        node["n"] += int(n)
        for f in frames:
            node = node["kids"].setdefault(f, {"n": 0, "kids": {}})
            node["n"] += int(n)
    total = root["n"]
    boxes = []

    def walk(node, x, depth):
        for nm, k in sorted(node["kids"].items(), key=lambda kv: -kv[1]["n"]):
            w = k["n"] / total
            if w >= min_frac:
                boxes.append((depth, x, w, nm, k["n"]))
                walk(k, x, depth + 1)
            x += w
    walk(root, 0.0, 0)
    depth = max(b[0] for b in boxes) + 1
    rowh, top, left = 26, 78, 24
    plot = width - 2 * left
    h = top + rowh * depth + 54
    b = [text(24, 34, title, 18, INK, weight="bold"), text(24, 58, subtitle, 15, INK3)]
    for d, x, w, nm, n in boxes:
        y = top + rowh * (depth - 1 - d)          # callers below, callees on top
        px, pw = left + plot * x, plot * w
        c = cols[kinds(nm)]
        b.append(f'<rect x="{px+1:.1f}" y="{y+1}" width="{max(pw-2,1):.1f}" height="{rowh-2}" rx="3" fill="{c}"/>')
        label = f"{nm}  {100*n/total:.0f}%" if pw > 150 else nm
        if pw > len(label) * 7.6 + 10:
            b.append(text(px + 8, y + 18, label, 13.5, INK))
        elif pw > len(nm) * 7.6 + 10:
            b.append(text(px + 8, y + 18, nm, 13.5, INK))
    x = left
    for i, lg in enumerate(legend):
        if any(kinds(bx[3]) == i for bx in boxes):
            b.append(f'<rect x="{x}" y="{h-30}" width="14" height="14" rx="3" fill="{cols[i]}"/>')
            b.append(text(x + 21, h - 18, lg, 13.5, INK2))
            x += 40 + len(lg) * 7.6
    save(name, width, h, b)


def perf_record():
    libc = ("__libc", "_start", "__GI_", "msort", "qsort")
    kind = lambda nm: 2 if nm.startswith("[k]") or nm.endswith("_[k]") else (1 if nm.startswith(libc) else 0)
    flame("perf-record-flame", "Where the samples were, and how the program got there",
          "4,504 samples of callers, stacks unwound with DWARF; each box sits on its caller",
          "perf-record/callers.folded", kind)
    lanes("perf-record-sample", "One sample",
          "the counter interrupts the CPU; the kernel writes a record and returns",
          ["the program", "the kernel", "perf"], [
              (0, 1, "the cycle counter overflows: interrupt"),
              (1, None, "40-byte record into the ring buffer"),
              (1, 0, "resume where it was"),
              ("gap", None, "... a few thousand samples later ..."),
              (1, 2, "buffer filling up: wake perf"),
              (2, None, "copy to perf.data"),
          ], note="no other process is woken for a sample: this is why it is cheap where a ptrace stop is not")
    banner("perf-record-banner", [
        "    77.00%  callers-nofp  callers-nofp   [.] checksum",
        "            ---checksum",
        ">               |--58.11%--render",
        "               |          main",
        ">                --18.89%--compress",
        "                          main",
    ], BLUE)


def valgrind():
    x = lambda v: f"{v:g}x"
    # results/valgrind/06-price-list.txt: slowdown = median wall time / native median
    pairs("valgrind-cost", "How much slower, under each Valgrind tool",
          "slowdown against the same program run natively; two different workloads", [
              ("a tight integer loop (0.45 s natively)", [2.7, 5.3, 10.0, 33.0, 62.7], x),
              ("a loop of malloc and free (0.036 s natively)", [9.9, 68.2, 80.2], x, ["none", "memcheck", "callgrind"]),
          ], ["none", "memcheck", "cachegrind", "callgrind", "lackey"], colors=(BLUE,))
    banner("valgrind-banner", [
        "  401769:	add    $0x1,%ecx",
        "   t52 = Not32(t51)",
        "   t53 = And32(t24,t52)",
        "   t60 = Xor32(t59,t58)",
        ">   t7 = Add32(t24,0x1:I32)",
        ">==82== Collected : 20480256",
    ], AQUA)


def kprobes():
    # results/kprobes-uprobes/04, 05, 06, 08; results/mechanisms/08-cost.txt; results/ltrace/04-overhead.txt
    dots_log("kprobes-cost", "What it costs to stop at one instruction",
             "added nanoseconds per hit, log scale; who handles the event decides the price", [
                 ("compiler-inserted hooks", 38),
                 ("LTTng tracepoint: no trap, the program writes", 65),
                 ("kprobe, optimised to a jump", 136),
                 ("kprobe at a function entry", 144),
                 ("kprobe, breakpoint", 359),
                 ("uprobe on a nop (a USDT probe)", 439),
                 ("uprobe on an ordinary instruction", 2885),
                 ("ptrace breakpoint: another process", 19899),
                 ("ltrace, per library call", 51964),
             ], lo=10, hi=100000)
    banner("kprobes-banner", [
        "53                      push   %rbx",
        "e8 b1 6e 0c 00          call   0xffffffffbb053500",
        ">cc                      int3",
        "48 8b 05 c1 b9 13 03    mov    0x313b9c1(%rip),%rax",
        ">e9 28 5a 47 05          jmp    0xffffffffc040207c",
        "ffffffffbaf8c64f  k  __do_sys_getppid+0xf    [OPTIMIZED]",
    ], ORANGE)


def hub():
    banner("tracing-banner", [
        "syscall 257 = 3",
        ">   435   80.9%  checksum",
        "code at 0x401330 was 015e8d53fd894855, is now 015e8d53fd8948cc",
        ">        2587474189      instructions:u",
        "cc                      int3",
        ">==82== Collected : 20480256",
    ], BLUE)


def ebpf():
    ns = lambda v: f"+{v:g} ns"
    # results/ebpf/06a-price.txt: added ns per getppid() call, medians of 7
    pairs("ebpf-cost", "What one event costs at the system call's entry",
          "nanoseconds added to a 116 ns getppid() call; medians of 7 runs", [
              ("", [33.4, 53.6, 55.7, 66.3, 93.8, 110.8], ns),
          ], ["BPF count() at the function's entry (fentry)", "the hand-made 11 instructions, on the tracepoint",
              "bpftrace count(), on the tracepoint", "bpftrace count(), on a kprobe",
              "bpftrace count() into a hash map keyed by name", "no BPF: a record into the ring buffer"],
          colors=(BLUE, BLUE, BLUE, BLUE, BLUE, ORANGE))
    banner("ebpf-banner", [
        "5: (85) call bpf_map_lookup_elem#1    ; R0=map_value_or_null(id=1,ks=4,vs=8)",
        "6: (b7) r1 = 1                        ; R1=1",
        "7: (db) lock *(u64 *)(r0 +0) += r1",
        ">R0 invalid mem access 'map_value_or_null'",
        "  58:	f0 48 01 78 00       	lock add %rdi,0x0(%rax)",
        ">[256, 512)       1020506 |@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@|",
    ], AQUA)


def tracepoints():
    # results/tracepoints/05-price.txt: ns per getppid() call, medians of 5
    dots_log("tracepoints-cost", "The same events, at very different prices",
             "nanoseconds added to one getppid() call, log scale; medians of 5 runs", [
                 ("perf stat: count, no record", 50.6),
                 ("tracepoint at entry: one record", 137.5),
                 ("tracepoints at entry and exit: two records", 249.3),
                 ("perf record: records into a file", 372.3),
                 ("perf trace: woken for every call", 7765.0),
                 ("strace: every call stopped twice", 16011.4),
             ], lo=10, hi=100000)
    banner("tracepoints-banner", [
        "off:   0f 1f 44 00 00       nopl   0x0(%rax,%rax,1)",
        ">on:    e9 31 09 00 00       jmp    0xffffffff86b6d1b6",
        " sleepy-310  [002] d..2.  4.487226: sched_switch: prev_comm=sleepy prev_pid=310 prev_prio=120 prev_state=S",
        ">total off-CPU: 1.800301 s",
        "entries still in buffer 160136, overwritten (overrun) 19139678",
        "events per second: 9640280",
    ], BLUE)


def which():
    # One point per mechanism, from the result files of the whole series (ns per event).
    dots_log("which-prices", "What one event costs, across the series",
             "nanoseconds per event, log scale; from different experiments, some in a VM", [
                 ("preloaded library in a doorway", 0.4),
                 ("gprof's mcount hook", 3.6),
                 ("binary record into memory", 7.1),
                 ("BPF program at a function's entry", 33),
                 ("BPF program at a tracepoint", 56),
                 ("uftrace, per call", 63),
                 ("LTTng user-space tracepoint", 65),
                 ("heaptrack, per malloc+free pair", 94),
                 ("tracepoint writing a record", 125),
                 ("kprobe, optimised to a jump", 136),
                 ("kprobe, breakpoint", 359),
                 ("uprobe on a no-op (USDT)", 439),
                 ("uprobe on an ordinary instruction", 2885),
                 ("single-step, per instruction", 6126),
                 ("perf trace, per system call", 7765),
                 ("perf record, per sample", 10000),
                 ("strace, per system call", 13217),
                 ("ptrace breakpoint", 14637),
                 ("ltrace, per library call", 51964),
             ], lo=0.1, hi=100000)
    banner("which-banner", [
        "real 3.42  user 0.34  sys 0.00",
        ">    97.44%  ingest   ingest                [.] checksum.constprop.0",
        " 99.77    3.072288       10240       300           fdatasync",
        ">        jbd2_log_wait_commit+183",
        "  flushes: 202 (2.02 per fdatasync)  D2C avg 5.304 ms",
        ">real 0.33  user 0.32  sys 0.00",
    ], ORANGE)


def blktrace():
    us = lambda v: f"{v:,.0f} µs"
    # results/blktrace/03-timing.txt (medians of 7) and 12-ext4-logger.txt
    dots_log("blktrace-cost", "Writing is cheap. Being sure is what costs.",
             "microseconds the program waits, log scale", [
                 ("write() into the kernel's memory", 3.9),
                 ("write() straight to the device (O_DIRECT)", 57.7),
                 ("fsync() on the bare device: 1 flush", 5161),
                 ("fdatasync() on ext4: 2 flushes", 10490),
             ], unit_fmt=us, lo=1, hi=100000)
    banner("blktrace-banner", [
        "write() took 7.8 us",
        ">254,48   3        7    30.876221251    15  Q   W 0 + 8 [kworker/u16:1]",
        "254,48   1        5     0.000005871   429  D  WS 0 + 8 [writer]",
        ">254,48   1        9     0.000070973   177  D  FN [kworker/1:1H]",
        "254,48   1       10     0.006859165     0  C  FN 0 [0]",
        "action counts: P=9 D=10 M=2039 G=10 U=9 C=11 Q=2049",
    ], AQUA)


FIGS = {"six-ways": six_ways, "six-ways-bp": six_ways_bp, "strace": strace, "ltrace": ltrace,
        "mtrace": mtrace, "gprof": gprof, "perf-stat": perf_stat, "perf-record": perf_record, "valgrind": valgrind, "kprobes": kprobes, "hub": hub, "ebpf": ebpf, "tracepoints": tracepoints, "which": which, "blktrace": blktrace}

if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for k, f in FIGS.items():
        if len(sys.argv) < 2 or k in sys.argv[1:]:
            f()
