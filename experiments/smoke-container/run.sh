# Smoke test: are the userspace tools present and allowed to ptrace?
set -x
id; uname -r; gcc --version | head -1; ldd --version | head -1
for t in strace ltrace valgrind uftrace heaptrack gprof gdb mtrace lttng perf bpftrace; do printf '%s: ' $t; command -v $t || echo MISSING; done
strace -V | head -1; ltrace -V | head -1; valgrind --version; uftrace --version; heaptrack --version
strace -c -o $OUT/strace-true.txt true
echo 'int main(){return 0;}' > t.c && gcc t.c -o t && valgrind -q ./t && echo valgrind ok
ltrace -o $OUT/ltrace-true.txt /bin/echo hi
