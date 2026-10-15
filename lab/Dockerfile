# One image, two uses: `docker run` it for the userspace experiments, and
# export it as the root filesystem of the KVM guest for the ones that need root.
FROM debian:trixie
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update -qq && apt-get install -y -qq --no-install-recommends \
      gcc g++ libc6-dev libc-dev-bin libc6-dbg make binutils elfutils gdb python3 perl \
      strace ltrace valgrind uftrace heaptrack \
      linux-perf bpftrace blktrace trace-cmd \
      lttng-tools liblttng-ust-dev babeltrace2 systemtap-sdt-dev \
      libc-devtools bpftool procps util-linux e2fsprogs kmod iproute2 time bc xxd file less ca-certificates \
    && rm -rf /var/lib/apt/lists/*
COPY vm/guest-init /sbin/tracelab-init
RUN chmod +x /sbin/tracelab-init
