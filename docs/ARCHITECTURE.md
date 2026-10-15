# Architecture

```
lab/Dockerfile         the image: Debian 13 (trixie) with every tool
lab/qemu.Dockerfile    Alpine with qemu-system-x86_64, e2fsprogs and tar
lab/run.sh             the runner
lab/vm/guest-init      PID 1 of the guest
lab/build/             rootfs image, kernel copy, per-run disks, locks (ignored by git)
experiments/_lib/      lib.sh (shared shell helpers), count.c (a fixed workload)
experiments/<name>/    MODE, run.sh, src/
results/<name>/        what the last run of <name> wrote
tools/figs.py          figures/*.svg and *.png from results/
```

## The image

`lab/Dockerfile` installs, from Debian packages only: gcc, g++, glibc with debug symbols, binutils, elfutils, gdb, python3, perl; strace, ltrace, valgrind, uftrace, heaptrack; linux-perf, bpftrace, bpftool, blktrace, trace-cmd; lttng-tools, liblttng-ust-dev, babeltrace2, systemtap-sdt-dev (for USDT); and procps, util-linux, e2fsprogs, kmod, iproute2. It also installs `lab/vm/guest-init` as `/sbin/tracelab-init`. The same image serves both modes.

## The runner

`./lab/run.sh <name>` reads `experiments/<name>/MODE` (`container` if missing), builds the image (`docker build -q -t tracelab`, cached after the first time), empties `results/<name>/`, and runs the experiment. `./lab/run.sh all` runs every directory under `experiments/` that does not start with `_`, one after another.

Concurrency is limited by two lock files, `lab/build/.lock` and `.lock2`. A run takes whichever it can with `flock -n`, polling once a second, so at most two experiments run at once. With `EXCLUSIVE=1` a run takes both, blocking, so it runs alone, for timings that should not share the CPU.

Every run is wrapped in `timeout -s KILL $TIMEOUT` (default 900 s), and an exit trap kills the container by name (`tracelab-<name>-<pid>`), so an interrupted run leaves nothing behind.

## Container mode

```
docker run --rm --user $(id -u):$(id -g) --memory 2g --network none \
    -e HOME=/tmp -e OUT=/out \
    -v experiments:/src:ro -v results/<name>:/out tracelab \
    sh -c 'cp -r /src/_lib /src/<name> /tmp/experiments/ && cd /tmp/experiments/<name> && sh ./run.sh > /out/run.log 2>&1'
```

The experiment runs as the invoking user, without extra capabilities. That is enough to ptrace one's own children (strace, ltrace, gdb, the hand-written tracers), to preload libraries, to run Valgrind and uftrace, and to compile with `-pg` or `-finstrument-functions`. It is not enough for `perf_event_open` on hardware counters, tracefs or `bpf()`. Sources are copied to `/tmp` so the build never writes into the repository; only `/out` is writable from outside.

## VM mode

The tools that need root over a kernel (perf, tracepoints, kprobes, uprobes, eBPF, blktrace) run in a KVM guest that boots the host's own kernel, so the results describe that kernel and its PMU, while the host itself is never traced.

1. **Root filesystem.** The image is exported (`docker create` + `docker export`) and piped into a `tracelab-qemu` container that runs `mke2fs -t ext4 -d` to build a 3 GB ext4 image, `lab/build/rootfs-<image id>.img`. It is rebuilt only when the image ID changes; `lab/build/.rootfs.lock` stops two runs building it at once, and older rootfs files are deleted.
2. **Kernel.** `$KERNEL` (default `/boot/vmlinuz-linux`) is copied to `lab/build/vmlinuz`. It must have virtio-blk and ext4 built in, since the guest has no initramfs.
3. **Disks.** A per-run directory `lab/build/run-<pid>/` holds:

   | Guest device | File | Contents |
   |---|---|---|
   | `/dev/vda` | `rootfs-<id>.img` | root filesystem, opened with `snapshot=on`: guest writes are discarded |
   | `/dev/vdb` | `in` | read-only tar of `experiments/_lib`, `experiments/<name>` and `.name` |
   | `/dev/vdc` | `out.img` | 512 MB, raw; the guest writes a tar of `/out` onto it |
   | `/dev/vdd` | `data.img` | 256 MB, blank, for I/O experiments (blktrace, one-bug) |

4. **Boot.** QEMU runs inside the `tracelab-qemu` container with `/dev/kvm` passed through, no network and a 1500 MB memory limit:

   ```
   qemu-system-x86_64 -enable-kvm -cpu host -smp $VM_CPUS -m 1G -kernel vmlinuz \
       -append "root=/dev/vda rw console=ttyS0 panic=-1 loglevel=4 init=/sbin/tracelab-init $KARGS" \
       -drive …vda,snapshot=on -drive …vdb,readonly=on -drive …vdc -drive …vdd \
       -nographic -no-reboot -nic none
   ```

   `-cpu host` exposes the host's performance counters to the guest. The serial console is saved to `results/<name>/console.log`; lines starting with `tracelab:` are echoed to the terminal.
5. **Guest init.** `/sbin/tracelab-init` mounts proc, sysfs, devtmpfs, devpts, tmpfs on `/tmp` and `/run`, tracefs at `/sys/kernel/tracing`, debugfs at `/sys/kernel/debug` and bpffs at `/sys/fs/bpf`; sets `kernel.perf_event_paranoid=-1` and `kernel.kptr_restrict=0`; unpacks `/dev/vdb` into `/work`; runs `run.sh` as root with `OUT=/out`, output to `/out/run.log`; records the exit status in `/out/.exit`; writes `tar cf /dev/vdc -C /out .`; and powers off through `/proc/sysrq-trigger`, since there is no init system to ask.
6. **Collection.** The host untars `out.img` into `results/<name>/`. A missing tar or a non-zero `.exit` fails the run and prints the tail of `run.log`. The per-run directory is removed on exit.

## Experiments

An experiment is a directory with a `MODE` file and a POSIX `run.sh`, started in its own directory with `$OUT` set. It compiles its programs from `src/` during the run, calls `env_snapshot TOOL…` to record the kernel, CPU, compiler, glibc and tool versions in `$OUT/env.txt`, and writes each result to its own numbered file in `$OUT`. Most files begin with the command that produced them (`$ strace -c ./slowcat`) followed by its output, so a file can be read without the script.

`experiments/_lib/lib.sh` provides:

| Helper | Output |
|---|---|
| `env_snapshot TOOL…` | `$OUT/env.txt`; reports whether it ran in the container or the guest |
| `wall_ms CMD…` | wall-clock milliseconds of one run of CMD |
| `stats` | `median min max n` of numbers on stdin |
| `repeat N CMD…` | runs CMD N times (CMD prints one number) and reports `stats` |
| `repeat_wall N CMD…` | `stats` of the wall time of N runs |

Timings are medians of several runs (usually 5 or 7), reported with minimum and maximum. A cost per event comes from a loop of known length, timed with and without the tracer. `experiments/_lib/count.c` is a fixed Collatz workload with no system calls, used where several tools are asked the same question.

`smoke-container` and `smoke-vm` are not tied to a note: they check that the tools are present and that ptrace, the PMU, tracefs and BPF work in each mode.

## Figures

`tools/figs.py` writes every figure as SVG and renders a PNG at twice the size with `rsvg-convert`. Values are read from `results/` where a file states them directly (`med(file, key)` takes the first number after a label); the rest are written into the script beside a comment naming the results file they come from. `python3 tools/figs.py strace perf-stat` redraws only the named groups. Five shapes cover the series: a dot plot on a log axis for costs, bars, paired small multiples, a sequence diagram of who wakes whom, and a flame graph built from a folded stack file (`results/perf-record/callers.folded`). Each note also has a 1600×360 banner made of lines from its results.
