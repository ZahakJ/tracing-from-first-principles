<p align="center"><img src="docs/media/banner.png" width="820" alt="Tracing from first principles: real output from the experiments (a hand-written strace, a perf report line, a kernel function patched with int3, a perf counter, a Valgrind count)"></p>

The experiments behind [Tracing from first principles](https://astrolabe.avicenna.space/Zombies/Tracing%20from%20first%20principles), a series of notes on Linux tracing tools: strace, ltrace, mtrace, gprof, uftrace, perf, tracepoints, kprobes, uprobes, eBPF, Valgrind and blktrace. Every number and every piece of output the notes quote is a file under `results/`, and one command regenerates it on your own kernel.

<p align="center">
  <img src="docs/media/perf-record-flame.png" width="400" alt="A flame graph from perf record: checksum called from render and compress, qsort calling back into the program">
  <img src="docs/media/perf-stat-same-work.png" width="400" alt="perf stat: summing a matrix by rows and by columns executes the same instructions but takes twenty times the cycles">
</p>
<p align="center">
  <img src="docs/media/strace-stops.png" width="400" alt="One system call under strace: two ptrace stops, each waking the tracer">
  <img src="docs/media/kprobes-cost.png" width="400" alt="The cost of stopping at one instruction, from compiler hooks at 38 ns to ltrace at 52 µs, log scale">
</p>

## Run

```sh
git clone https://github.com/ZahakJ/tracing-from-first-principles
cd tracing-from-first-principles
./lab/run.sh strace            # one experiment
./lab/run.sh all               # every experiment
```

Needs Docker. Experiments marked VM below also need a writable `/dev/kvm` and a readable kernel image (`/boot/vmlinuz-linux`, or `KERNEL=/path/to/bzImage`) with virtio-blk and ext4 built in.

## Use

| Note | Experiment | Runs in | What it shows |
|---|---|---|---|
| Six ways to watch a program | `mechanisms` | container | printf, compiler hooks, a signal-driven sampler, a ptrace breakpoint, an LD_PRELOAD shim and a single-stepper, each in a page of C, with their cost per event |
| strace | `strace` | container | a 55-line strace; a program that hides its error; the cost of ptrace per system call; fault injection |
| ltrace | `ltrace` | container | the PLT stub, the 0xCC in it, the cost per call, the builds ltrace cannot see |
| mtrace | `mtrace` | container | counting, mtrace, heaptrack, AddressSanitizer, memcheck on the same leak; what interposers miss |
| gprof and uftrace | `gprof-uftrace` | container | what `-pg` inserts; gprof attributing time backwards; uftrace; cost per call |
| perf stat | `perf-stat` | VM | same instructions, 20x the cycles; perf_event_open by hand; multiplexing |
| perf record | `perf-record` | VM | sampling, skid, frame pointers vs DWARF vs LBR, a flame graph, the blind spot |
| Tracepoints | `tracepoints` | VM | a tracepoint's bytes off and on; strace vs perf trace vs the ring buffer; why a program waited |
| kprobes and uprobes | `kprobes-uprobes` | VM | the kernel patching itself (nop, call, int3, jmp); a program watching its own breakpoint; USDT; LTTng |
| eBPF and bpftrace | `ebpf` | VM | a BPF program assembled by hand; the verifier refusing five programs; the cost of a program at a hook |
| Valgrind | `valgrind` | container | a translated block; exact counts; callgrind, cachegrind, memcheck |
| Following a write to the disk | `blktrace` | VM | where a write is 30 s after `write()` returns; what one fsync costs the disk |
| Which tracer do I reach for | `one-bug` | VM | one slow program through eight tools, in order |

Output lands in `results/<experiment>/`: one file per thing a note quotes, plus `env.txt` (kernel, CPU, tool versions) and `run.log`. `python3 tools/figs.py` redraws `figures/` from it (needs `rsvg-convert`).

| Variable | Default | Effect |
|---|---|---|
| `KERNEL` | `/boot/vmlinuz-linux` | kernel the VM boots |
| `TIMEOUT` | `900` | seconds before a run is killed |
| `VM_CPUS` | `4` | vCPUs in the VM |
| `KARGS` | | extra kernel command-line arguments |
| `EXCLUSIVE` | | `1`: wait until no other experiment is running |

The results in this repository were produced on Linux 7.1.8 with a Debian 13 userspace.

## How it works

One Debian 13 image holds every tool. A container experiment runs in it as an unprivileged Docker container with no network, which is enough for anything built on ptrace or LD_PRELOAD. A VM experiment needs root over a real kernel: the same image is exported to an ext4 file and booted as the root filesystem of a KVM guest running the host's own kernel. The experiment goes in on one virtio disk, its results come back as a tar on another, and the guest powers off. The host is never traced.

## Docs

- [Architecture](docs/ARCHITECTURE.md): the runner, both modes, the guest's disks and init, locking, results and figures.
- [Experiments](docs/EXPERIMENTS.md): each experiment's programs and output files.
- [Writing an experiment](experiments/README.md): the contract a `run.sh` follows.

The ftrace note has its own repository, [ftscope](https://github.com/ZahakJ/ftscope).

## License

MIT
