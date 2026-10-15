/*
 * rawbpf: the whole of eBPF with no tools. Only the bpf() syscall and
 * struct bpf_insn from <linux/bpf.h>.
 *
 *   rawbpf count      load a counter, attach it to raw_syscalls:sys_enter for
 *                     one child that makes 1,000,000 getppid() calls, read it
 *   rawbpf bad        ask the verifier to load six doubtful programs
 *   rawbpf hold SECS  attach the counter for SECS seconds, then print it
 */
#include <linux/bpf.h>
#include <linux/perf_event.h>
#include <sys/ioctl.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

/* One 64-bit instruction: opcode, dst reg, src reg, 16-bit offset, 32-bit imm. */
#define INSN(c, d, s, o, i) \
	((struct bpf_insn){ .code = (c), .dst_reg = (d), .src_reg = (s), .off = (o), .imm = (i) })
#define MOV64_IMM(d, i)		INSN(BPF_ALU64 | BPF_MOV | BPF_K, d, 0, 0, i)
#define MOV64_REG(d, s)		INSN(BPF_ALU64 | BPF_MOV | BPF_X, d, s, 0, 0)
#define ADD64_IMM(d, i)		INSN(BPF_ALU64 | BPF_ADD | BPF_K, d, 0, 0, i)
#define ST_W(d, o, i)		INSN(BPF_ST | BPF_MEM | BPF_W, d, 0, o, i)	/* *(u32 *)(d + o) = i */
#define LDX_DW(d, s, o)		INSN(BPF_LDX | BPF_MEM | BPF_DW, d, s, o, 0)	/* d = *(u64 *)(s + o) */
#define ATOMIC_ADD_DW(d, s, o)	INSN(BPF_STX | BPF_ATOMIC | BPF_DW, d, s, o, BPF_ADD)
/* A map's fd is a 64-bit immediate: two instruction slots. */
#define LD_MAP_FD(d, fd)	INSN(BPF_LD | BPF_DW | BPF_IMM, d, BPF_PSEUDO_MAP_FD, 0, fd), INSN(0, 0, 0, 0, 0)
#define CALL(f)			INSN(BPF_JMP | BPF_CALL, 0, 0, 0, f)
#define JEQ_IMM(d, i, o)	INSN(BPF_JMP | BPF_JEQ | BPF_K, d, 0, o, i)
#define JA(o)			INSN(BPF_JMP | BPF_JA, 0, 0, o, 0)
#define EXIT()			INSN(BPF_JMP | BPF_EXIT, 0, 0, 0, 0)

static char log_buf[65536];

static long bpf(int cmd, union bpf_attr *attr)
{
	return syscall(SYS_bpf, cmd, attr, sizeof(*attr));
}

static int map_create(int type)
{
	union bpf_attr a = { 0 };

	a.map_type = type;
	a.key_size = 4;
	a.value_size = 8;
	a.max_entries = 1;
	return bpf(BPF_MAP_CREATE, &a);
}

static unsigned long long map_read(int map)
{
	union bpf_attr a = { 0 };
	unsigned int key = 0;
	unsigned long long val = 0;

	a.map_fd = map;
	a.key = (unsigned long)&key;
	a.value = (unsigned long)&val;
	bpf(BPF_MAP_LOOKUP_ELEM, &a);
	return val;
}

/* A plain listing, one line per instruction. */
static void list(const struct bpf_insn *p, int n)
{
	for (int i = 0; i < n; i++)
		printf("  %2d: code=0x%02x dst=r%d src=r%d off=%-4d imm=%d\n",
		       i, p[i].code, p[i].dst_reg, p[i].src_reg, p[i].off, p[i].imm);
}

static int load(const struct bpf_insn *p, int n, int verbose)
{
	union bpf_attr a = { 0 };
	int fd;

	a.prog_type = BPF_PROG_TYPE_TRACEPOINT;
	a.insns = (unsigned long)p;
	a.insn_cnt = n;
	a.license = (unsigned long)"GPL";
	if (verbose) {		/* a log buffer with log_level 0 is EINVAL */
		a.log_buf = (unsigned long)log_buf;
		a.log_size = sizeof(log_buf);
		a.log_level = verbose;
	}
	strcpy(a.prog_name, "rawbpf_count");
	log_buf[0] = 0;
	fd = bpf(BPF_PROG_LOAD, &a);
	if (fd < 0)
		perror("BPF_PROG_LOAD");
	return fd;
}

static int prog_id(int fd)
{
	struct bpf_prog_info info = { 0 };
	union bpf_attr a = { 0 };

	a.info.bpf_fd = fd;
	a.info.info_len = sizeof(info);
	a.info.info = (unsigned long)&info;
	bpf(BPF_OBJ_GET_INFO_BY_FD, &a);
	return info.id;
}

/* Ask the kernel for the machine code the JIT produced; write it to a file. */
static void save_jited(int fd, const char *path)
{
	struct bpf_prog_info info = { 0 };
	union bpf_attr a = { 0 };
	static unsigned char code[4096];
	FILE *f;

	info.jited_prog_len = sizeof(code);
	info.jited_prog_insns = (unsigned long)code;
	a.info.bpf_fd = fd;
	a.info.info_len = sizeof(info);
	a.info.info = (unsigned long)&info;
	if (bpf(BPF_OBJ_GET_INFO_BY_FD, &a) < 0 || !(f = fopen(path, "w"))) {
		perror("save_jited");
		return;
	}
	fwrite(code, 1, info.jited_prog_len, f);
	fclose(f);
	printf("wrote %u bytes of x86-64 code to %s\n", info.jited_prog_len, path);
}

static int tracepoint_id(const char *name)
{
	char path[256];
	FILE *f;
	int id = -1;

	snprintf(path, sizeof(path), "/sys/kernel/tracing/events/%s/id", name);
	f = fopen(path, "r");
	if (!f || fscanf(f, "%d", &id) != 1)
		perror(path);
	if (f)
		fclose(f);
	return id;
}

/* Open the tracepoint as a perf event for (pid, cpu), hang the program on it. */
static int attach(int prog, int tp, int pid, int cpu)
{
	struct perf_event_attr pa = { 0 };
	int ev;

	pa.type = PERF_TYPE_TRACEPOINT;
	pa.size = sizeof(pa);
	pa.config = tp;
	pa.sample_period = 1;
	ev = syscall(SYS_perf_event_open, &pa, pid, cpu, -1, 0);
	if (ev < 0 || ioctl(ev, PERF_EVENT_IOC_SET_BPF, prog) < 0 ||
	    ioctl(ev, PERF_EVENT_IOC_ENABLE, 0) < 0) {
		perror("attach");
		exit(1);
	}
	return ev;
}

int main(int argc, char **argv)
{
	int map = map_create(BPF_MAP_TYPE_ARRAY);
	struct bpf_insn good[] = {
		ST_W(BPF_REG_10, -4, 0),		/* u32 key = 0 on the stack */
		MOV64_REG(BPF_REG_2, BPF_REG_10),
		ADD64_IMM(BPF_REG_2, -4),		/* r2 = &key */
		LD_MAP_FD(BPF_REG_1, map),		/* r1 = map */
		CALL(BPF_FUNC_map_lookup_elem),		/* r0 = &value or NULL */
		JEQ_IMM(BPF_REG_0, 0, 2),		/* if r0 == NULL skip the add */
		MOV64_IMM(BPF_REG_1, 1),
		ATOMIC_ADD_DW(BPF_REG_0, BPF_REG_1, 0),	/* *(u64 *)r0 += 1 */
		MOV64_IMM(BPF_REG_0, 0),
		EXIT(),
	};
	int n = sizeof(good) / sizeof(good[0]);
	const char *mode = argc > 1 ? argv[1] : "count";

	if (map < 0) {
		perror("BPF_MAP_CREATE");
		return 1;
	}
	if (!strcmp(mode, "bad")) {
		struct bpf_insn nonull[sizeof(good) / sizeof(good[0])];
		struct bpf_insn nonull_hash[sizeof(good) / sizeof(good[0])];
		struct bpf_insn ctx[] = { LDX_DW(BPF_REG_0, BPF_REG_1, 30000), EXIT() };
		struct bpf_insn uninit[] = { LDX_DW(BPF_REG_0, BPF_REG_3, 0), EXIT() };
		struct bpf_insn loop[] = { MOV64_IMM(BPF_REG_0, 0), JA(-1) };
		struct bpf_insn noexit[] = { MOV64_IMM(BPF_REG_0, 0) };
		struct { const char *what; struct bpf_insn *p; int n; } t[] = {
			{ "(i-a) no NULL check, array map, constant key 0", nonull, n - 1 },
			{ "(i-b) no NULL check, the same program on a hash map", nonull_hash, n - 1 },
			{ "(ii-a) read through the context pointer at offset 30000", ctx, 2 },
			{ "(ii-b) read through an uninitialised register r3", uninit, 2 },
			{ "(iii) a loop that never ends (goto -1)", loop, 2 },
			{ "(iv) falling off the end without exit", noexit, 1 },
		};

		/* the good program with instruction 6 (the NULL check) removed */
		memcpy(nonull, good, 6 * sizeof(good[0]));
		memcpy(nonull + 6, good + 7, (n - 7) * sizeof(good[0]));
		memcpy(nonull_hash, nonull, sizeof(nonull));
		nonull_hash[3].imm = map_create(BPF_MAP_TYPE_HASH);
		for (int i = 0; i < 6; i++) {
			printf("==== %s\n", t[i].what);
			list(t[i].p, t[i].n);
			printf("-- result: ");
			fflush(stdout);
			if (load(t[i].p, t[i].n, 1) >= 0)
				printf("accepted\n");
			fflush(stderr);
			printf("-- verifier log:\n%s\n", log_buf);
		}
		return 0;
	}

	printf("instructions loaded (%d):\n", n);
	list(good, n);
	int prog = load(good, n, 0);
	int tp = tracepoint_id("raw_syscalls/sys_enter");

	if (prog < 0 || tp < 0)
		return 1;
	printf("prog fd %d, prog id %d, map fd %d, tracepoint id %d\n",
	       prog, prog_id(prog), map, tp);
	fflush(stdout);

	if (!strcmp(mode, "hold")) {
		int secs = argc > 2 ? atoi(argv[2]) : 5;

		/*
		 * One event, on CPU 0. A second SET_BPF of the same program on
		 * the same tracepoint (CPU 1) fails with EEXIST: the program
		 * hangs on the tracepoint, not on the perf event.
		 */
		attach(prog, tp, -1, 0);
		save_jited(prog, "/tmp/jit.bin");
		printf("attached (event on CPU 0, all processes) for %d s\n", secs);
		fflush(stdout);
		sleep(secs);
		printf("slot 0 = %llu\n", map_read(map));
		return 0;
	}

	/* count: a child waits on a pipe until we have attached to it */
	int go[2];
	char c;

	pipe(go);
	pid_t child = fork();

	if (child == 0) {
		read(go[0], &c, 1);
		for (int i = 0; i < 1000000; i++)
			syscall(SYS_getppid);
		_exit(0);
	}
	attach(prog, tp, child, -1);
	printf("slot 0 before: %llu\n", map_read(map));
	write(go[1], "x", 1);
	/* does the parent's own 500,000 calls count? (it is not the pid we opened) */
	for (int i = 0; i < 500000; i++)
		syscall(SYS_getppid);
	waitpid(child, NULL, 0);
	printf("slot 0 after the child's 1,000,000 getppid() calls\n"
	       "  and the parent's own 500,000:  %llu\n", map_read(map));
	return 0;
}
