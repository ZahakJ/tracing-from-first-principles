# Experiments

Each section lists the programs an experiment builds from its `src/` directory and the files it writes to `results/<name>/`. Every experiment also writes `env.txt` and `run.log`; VM experiments add `console.log`.

## mechanisms (container)

Six ways to observe a program, each written by hand, applied to one workload.

| Program | What it is |
|---|---|
| `work.c` | builds N fake log records, checksums each, keeps every tenth |
| `hooks.c` | `-finstrument-functions` hooks counting calls and time per function |
| `sampler.c` | an LD_PRELOAD profiler: a timer signal per millisecond of CPU time records the interrupted address |
| `bp.c` | a ptrace breakpoint: writes 0xCC at an address, counts hits, restores and single-steps |
| `shim.c` | an LD_PRELOAD shim around `malloc` and `free` |
| `step.c` | runs a program one instruction at a time with `PTRACE_SINGLESTEP` between two addresses |
| `cost.c` | one function called N times; the modes differ only in how each call is reported |

Output: `01-plain` (unobserved), `02-tell` (the program printing a line per record), `03-compiler`, `04-sampler`, `05-breakpoint`, `06-shim`, `07-step`, `08-cost` (the price list).

## strace (container)

| Program | What it is |
|---|---|
| `minitrace.c` | a strace in one page: `PTRACE_SYSCALL`, printing `syscall <nr> = <ret>` |
| `liar.c` | looks for a config file in three places and reports only "startup failed" |
| `slowcat.c`, `fastcat.c` | copy stdin to stdout one byte at a time, and 64 KiB at a time |
| `waits.c` | sleeps, blocks on a pipe, fsyncs |
| `sysloop.c` | N `getppid()` calls, ns per call |
| `spin.c` | a second of CPU with no system calls |
| `saver.c`, `saver_checked.c` | ignores, and checks, the return value of `write()` |

Output: `01-minitrace`, `02-liar`, `03-slowcat-wall`, `04-slowcat-strace-c`, `05-waits`, `06-cost-sysloop`, `07-cost-cat`, `08-spin`, `09-inject` (fault injection with `-e inject`), `10-stack-k`, `11-ptrace-scope`.

## ltrace (container)

| Program | What it is |
|---|---|
| `shout.c` | upper-cases a string with `strlen()` in the loop condition |
| `hello.c` | calls `puts()` and `strlen()` |
| `selfpeek.c` | prints the first bytes of its own PLT stub for `puts()`, showing the 0xCC ltrace writes |
| `callloop.c` | N calls to `labs()` through the PLT, ns per call |
| `shim.c` | an LD_PRELOAD `labs()`, for comparison |
| `greet.c`, `usegreet.c` | a shared library calling libc, and a program calling it |
| `readline.c` | stdio open, read, close |

Output: `01-shout-*` (wall time, `ltrace -c`, `strace -c`, disassembly), `02-plt`, `03-selfpeek`, `03b-selfpeek-variants`, `04-*` (cost per call, overhead, the shim check), `05-truth-table` (which builds ltrace can see), `06-between-libs`, `07-ltrace-S`.

## mtrace (container)

| Program | What it is |
|---|---|
| `leaky.c` | a toy server that leaks on its error paths |
| `count.c` | an LD_PRELOAD counter of `malloc` and `free` |
| `churn.c` | N malloc/free pairs with 1000 blocks live, ns per pair |
| `uaf.c` | a one-byte overflow and a use after free |

Output: `01-leaky`, `02-count`, `03a`–`03d` (`MALLOC_TRACE`, the debug library, the `mtrace` script, a non-PIE build), `04-wrapper`, `05-heaptrack`, `06-cost`, `07a`–`07g` (the heap bugs under mtrace, ASan, LSan and memcheck), `08-mallinfo`, `09-ltrace`.

## gprof-uftrace (container)

| Program | What it is |
|---|---|
| `paths.c`, `paths_truth.c` | two callers of `spin()` with very different costs, and the same with a stopwatch around each |
| `calls.c`, `cyg_hooks.c` | the cost of a call with and without an instrumentation hook |
| `blind.c` | time asleep, time in libc and time in the program's own code |
| `threads.c` | the same loop in the main thread and in a second thread |

Output: `01-truth`, `02-inserted` (what `-pg` adds), `03-gprof-*` (call graph, PIE and non-PIE, repeated runs), `04-timer`, `05-blind-gprof`, `06-uftrace-*` (record, replay, report, graph, filter), `07-uftrace-dynamic`, `08-cost`, `09-threads`.

## valgrind (container)

| Program | What it is |
|---|---|
| `sum2d.c` | a 2048×2048 matrix summed by rows or by columns |
| `paths.c` | two callers of one function, cheap and expensive |
| `mallocs.c` | many small allocations |
| `over.c`, `uaf.c`, `uninit.c` | an overflow, a use after free, a branch on uninitialised memory |
| `threads.c` | four CPU-bound threads |

Output: `01-bare-machine`, `02-translated-block` (one block of VEX IR), `03-callgrind-paths`, `04-cachegrind`, `05-memcheck-*`, `05-uninit-other-tools`, `06-price-list` (slowdown under each tool), `07-threads`.

## perf-stat (VM)

| Program | What it is |
|---|---|
| `sum2d.c` | a matrix summed by rows or by columns: same instructions, different cycles |
| `branchy.c` | sums bytes ≥ 128 of a random array, sorted or shuffled |
| `ministat.c` | `perf_event_open` by hand: two counters around a piece of work |
| `phases.c` | a program whose behaviour changes over time, to test multiplexing estimates |
| `sysloop.c` | 2,000,000 `getppid()` calls, for the user/kernel split |

Output: `01-sum2d`, `02-branchy` (each with disassembly), `03-*` (cache events, how many counters the guest PMU has, the event lists), `04-ministat`, `05-overhead`, `06-*` (multiplexing and the scaling error), `07-user-kernel`, `08-count`, `09-system-wide`.

## perf-record (VM)

| Program | What it is |
|---|---|
| `hot.c` | three functions with work in the ratio 6:3:1 |
| `skid.c` | a loop dominated by one dependent divide |
| `callers.c` | one leaf reached from two callers, and `qsort()` calling back into the program |
| `sleepy.c` | 0.2 s of computing and 1.8 s of waiting |
| `sum2d.c` | the same matrix walk, for sampling other events |
| `stacks.awk` | folds `perf script` output and measures stack depth per unwinder |

Output: `01-hot-report`, `02-what-a-sample-is`, `03-any-event`, `04-skid`, `05-callers`, `05-stack-quality` (frame pointers, DWARF, LBR), `06-*` and `callers.folded` (the flame graph's input), `07-rates`, `08-kernel`, `09-blind-spot`, `09-sched-switch`, `10-system-wide`.

## tracepoints (VM)

| Program | What it is |
|---|---|
| `sysloop.c` | the price of one `getppid()` |
| `sleepy.c` | computing, then a sleep and a blocking read |
| `spin.c` | N seconds of CPU without sleeping |
| `wakeup.c` | sleeps 10 ms N times and measures how late each wake-up was |
| `kpeek` | reads the machine code at a kernel symbol from `/proc/kcore` |
| `bdiff.py` | the byte ranges where two dumps of a function differ |
| `switches.py` | time a PID spent switched out, from a `sched_switch` trace |

Output: `01-what-exists`, `02-by-hand` (tracefs only), `03-static-key` (a tracepoint's code disabled and enabled), `04-sleepy`, `05-price`, `06-perf-trace`, `07-perf-sched`, `08-firehose`, `09-perf-attach`.

## kprobes-uprobes (VM)

| Program | What it is |
|---|---|
| `kpeek` | as above, with `--raw` |
| `app.c` | a program with one function worth watching; `watch` prints its first bytes every 200 ms |
| `bp.c` | the hand-written ptrace breakpoint |
| `app_usdt.c` | the same loop with a USDT probe (`DTRACE_PROBE1`) |
| `app_lttng.c`, `tp.c`, `tp.h` | the same loop with an LTTng-UST tracepoint |
| `sysloop.c` | the price of one `getppid()` |

Output: `01-kpeek`, `02-selfpatch` (the kernel's code before and after a kprobe: nop, call, int3, jmp), `03-openat`, `04-kprobe-cost`, `05-uprobe`, `05-uprobe-cost`, `06-usdt`, `07-perf-probe`, `08-lttng`, `09-sysctl-hang`.

## ebpf (VM)

| Program | What it is |
|---|---|
| `rawbpf.c` | a BPF program assembled from `struct bpf_insn`, loaded and attached with the `bpf()` system call alone |
| `reader.c` | `read()` calls of three sizes, so latency spans orders of magnitude |
| `hist.py` | the same histogram from `perf script` output, for comparison |
| `hot.c`, `sleepy.c`, `churn.c`, `sysloop.c` | workloads for profiling, off-CPU time, uprobes and price |

Output: `01a`–`01d` (the event stream versus an in-kernel histogram), `02-rawbpf`, `03-verifier` (five rejected programs), `04-jit`, `05a`–`05f` (profile, kprobe, kretprobe, off-CPU, uprobe, the probe list), `06a-price`, `06b-uprobe-price`, `07a-codegen`, `07b-bpftool`, `08a`–`08c` (unbounded loops, lost events, missing probes).

## blktrace (VM)

Runs on the blank disk `/dev/vdd`, first raw, then formatted as ext4.

| Program | What it is |
|---|---|
| `writer.c` | one 4 KiB write, buffered, `O_DIRECT` or with `fsync` |
| `seqwrite.c` | N sequential 4 KiB writes |
| `logger.c` | N records with `fdatasync()` after each, like a database log |
| `d2c.awk` | pairs dispatch and completion events from `blkparse` |

Output: `01-setup`, `02-buffered`, `03-direct`, `03-fsync`, `03-timing`, `05-btt`, `06-merge`, `07a`–`07c` (the block tracepoints, ftrace's blk tracer, and how blktrace sits on them), `08-price`, `09-appview`, then the ext4 half: `10-ext4-setup` to `14-ext4-batch`.

## one-bug (VM)

`ingest.c` spends about 1 ms of CPU per record in `checksum()`, which is not the problem, and then waits on `fdatasync()` of an audit log on `/dev/vdd`, which is. The experiment runs it through the tools in the order the note uses them.

Output: `00-setup`, `01-time`, `02-perf-wrong-lead`, `03-strace`, `04-who-calls`, `05-offcpu` (`offcpu.bt`, `jbd2off.bt`), `06-perf-trace`, `07-blktrace`, `08-fix`, `09-overhead`, `10-wrong-kind`.
