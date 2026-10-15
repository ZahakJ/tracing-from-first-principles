# Smoke test: what does the guest have? PMU, tracefs, BPF.
set -x
uname -a; nproc; free -m | head -2
perf --version; bpftrace --version
ls /sys/bus/event_source/devices/
dmesg | grep -i -E 'perf|pmu|ibs|lbr' | head -20
grep -m1 -E '^flags' /proc/cpuinfo | tr ' ' '\n' | grep -E 'perfctr|ibs|lbr|arch_perfmon|pmu|brs' | tr '\n' ' '; echo
perf stat -e cycles,instructions,branches,branch-misses,cache-references,cache-misses,task-clock,context-switches,page-faults -- sh -c 'i=0; while [ $i -lt 200000 ]; do i=$((i+1)); done' 2>&1
perf list hw cache 2>&1 | head -40
perf record -o /tmp/p.data -g -- sh -c 'i=0; while [ $i -lt 200000 ]; do i=$((i+1)); done' 2>&1 | tail -3
perf report -i /tmp/p.data --stdio 2>/dev/null | head -30
bpftrace -e 'BEGIN { printf("bpf ok\n"); exit(); }'
bpftrace -e 'tracepoint:syscalls:sys_enter_openat { @[comm] = count(); } interval:s:1 { exit(); }'
ls /sys/kernel/tracing | head -50
cat /sys/kernel/tracing/available_tracers
ls /sys/kernel/debug/kprobes/ 2>&1
ls -la /dev/vd*
