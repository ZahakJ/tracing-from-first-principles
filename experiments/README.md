# Experiments

One directory per note. `./lab/run.sh <name>` runs `experiments/<name>/run.sh`
and collects everything it writes to `$OUT` into `results/<name>/`.

    experiments/<name>/MODE      "container" or "vm"
    experiments/<name>/run.sh    POSIX sh; cwd is the experiment directory; stdout+stderr go to $OUT/run.log
    experiments/<name>/src/      the small C programs the note talks about
    experiments/_lib/lib.sh      helpers: env_snapshot, wall_ms, stats, repeat, repeat_wall
    experiments/_lib/count.c     a fixed workload used to compare tools against each other

- **container**: an ordinary unprivileged Docker container (no network, 2 GB),
  as the invoking user. ptrace of your own children works; `perf_event_open`,
  tracefs and BPF do not.
- **vm**: a throwaway KVM guest (4 vCPUs, 1 GB) running the host's kernel with
  this image as its root filesystem; `run.sh` runs as root with tracefs at
  `/sys/kernel/tracing`, debugfs at `/sys/kernel/debug`, and a blank 256 MB
  disk at `/dev/vdd`. The root disk is a snapshot: writes vanish at power-off.

Each experiment compiles from source inside the run, prints the kernel and
tool versions (`env_snapshot`), reports medians of several runs with min and
max, and writes each thing the note quotes to its own file in `$OUT`.
