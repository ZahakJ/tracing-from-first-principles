#!/usr/bin/env bash
# tracelab: regenerate the output quoted in a note.
#
#   ./lab/run.sh <experiment>     e.g. ./lab/run.sh strace
#   ./lab/run.sh all
#
# Each experiment is a directory experiments/<name>/ with a run.sh and a MODE
# file: "container" (an ordinary unprivileged Docker container) or "vm" (a
# throwaway KVM guest booted from the same image, for tools that need root).
# Results land in results/<name>/. Needs Docker; vm mode also needs /dev/kvm
# and a readable kernel image (KERNEL=/path/to/bzImage, default /boot/vmlinuz-linux).
set -euo pipefail
LAB=$(cd "$(dirname "$0")" && pwd); ROOT=$(dirname "$LAB")
KERNEL=${KERNEL:-/boot/vmlinuz-linux}
TIMEOUT=${TIMEOUT:-900}
[ $# -ge 1 ] || { sed -n '2,12p' "$0"; echo; echo "experiments:"; ls "$ROOT/experiments" | grep -v -e "^_" -e README; exit 1; }

if [ "$1" = all ]; then
	for d in "$ROOT"/experiments/[!_]*/; do "$0" "$(basename "$d")"; done; exit 0
fi
NAME=$1; EXP=$ROOT/experiments/$NAME
[ -f "$EXP/run.sh" ] || { echo "no such experiment: $NAME" >&2; exit 1; }
MODE=$(cat "$EXP/MODE" 2>/dev/null || echo container)
OUT=$ROOT/results/$NAME; BUILD=$LAB/build
mkdir -p "$BUILD"
# At most two experiments at once; with EXCLUSIVE=1, only this one.
if [ -n "${EXCLUSIVE:-}" ]; then
	exec 9>"$BUILD/.lock" 8>"$BUILD/.lock2"; flock 9; flock 8
else
	while :; do
		exec 9>"$BUILD/.lock";  flock -n 9 && break
		exec 9>"$BUILD/.lock2"; flock -n 9 && break
		sleep 1
	done
fi
CN=tracelab-$NAME-$$
trap 'docker kill "$CN" >/dev/null 2>&1 || true' EXIT INT TERM

echo "tracelab: building image (first time takes a few minutes)" >&2
docker build -q -t tracelab -f "$LAB/Dockerfile" "$LAB" >/dev/null
rm -rf "$OUT"; mkdir -p "$OUT" "$BUILD"

case $MODE in
container)
	# Unprivileged. ptrace of our own children is all the userspace tools need.
	timeout -s KILL "$TIMEOUT" docker run --rm --name "$CN" --user "$(id -u):$(id -g)" \
		--memory 2g --network none -e HOME=/tmp -e OUT=/out \
		-v "$ROOT/experiments:/src:ro" -v "$OUT:/out" tracelab \
		sh -c "mkdir /tmp/experiments && cp -r /src/_lib /src/$NAME /tmp/experiments/ && cd /tmp/experiments/$NAME && sh ./run.sh > /out/run.log 2>&1" \
		|| { echo "experiment failed; tail of results/$NAME/run.log:" >&2; tail -n 20 "$OUT/run.log" >&2; exit 1; }
	;;
vm)
	[ -r "$KERNEL" ] || { echo "cannot read kernel image $KERNEL (set KERNEL=)" >&2; exit 1; }
	[ -w /dev/kvm ] || { echo "/dev/kvm is not writable" >&2; exit 1; }
	docker build -q -t tracelab-qemu -f "$LAB/qemu.Dockerfile" "$LAB" >/dev/null
	ID=$(docker image inspect -f '{{.Id}}' tracelab | cut -d: -f2 | cut -c1-12)
	ROOTFS=$BUILD/rootfs-$ID.img
	exec 7>"$BUILD/.rootfs.lock"; flock 7      # two runs must not build the same rootfs at once
	if [ ! -f "$ROOTFS" ]; then
		echo "tracelab: turning the image into a guest root filesystem" >&2
		rm -f "$BUILD"/rootfs-*.img
		C=$(docker create --name "tracelab-export-$$" tracelab)
		docker export "$C" | docker run --rm -i --name "tracelab-mkfs-$$" -v "$BUILD:/build" tracelab-qemu sh -c \
			"mkdir /r && tar xf - -C /r && mke2fs -q -t ext4 -d /r /build/rootfs.tmp 3G && chown $(id -u):$(id -g) /build/rootfs.tmp"
		docker rm "$C" >/dev/null
		mv "$BUILD/rootfs.tmp" "$ROOTFS"
	fi
	flock -u 7
	cp "$KERNEL" "$BUILD/vmlinuz"
	W=$BUILD/run-$$; mkdir -p "$W"; trap 'docker kill "$CN" >/dev/null 2>&1 || true; rm -rf "$W"' EXIT INT TERM
	echo "$NAME" > "$W/.name"
	tar cf "$W/in" -C "$ROOT" experiments/_lib "experiments/$NAME" -C "$W" .name
	truncate -s 256M "$W/data.img"                                # /dev/vdd: a blank disk to do I/O on
	truncate -s 512M "$W/out.img"
	# -snapshot: the guest may scribble on its root disk; nothing is written back.
	timeout -s KILL "$TIMEOUT" docker run --rm --name "$CN" --device /dev/kvm --user "$(id -u):$(id -g)" \
		--group-add "$(stat -c %g /dev/kvm)" --memory 1500m --network none \
		-v "$BUILD:/build" tracelab-qemu \
		qemu-system-x86_64 -enable-kvm -cpu host -smp "${VM_CPUS:-4}" -m 1G \
			-kernel /build/vmlinuz \
			-append "root=/dev/vda rw console=ttyS0 panic=-1 loglevel=4 init=/sbin/tracelab-init ${KARGS:-}" \
			-drive "file=/build/$(basename "$ROOTFS"),format=raw,if=virtio,snapshot=on" \
			-drive "file=/build/run-$$/in,format=raw,if=virtio,readonly=on" \
			-drive "file=/build/run-$$/out.img,format=raw,if=virtio" \
			-drive "file=/build/run-$$/data.img,format=raw,if=virtio" \
			-nographic -no-reboot -nic none | tee "$OUT/console.log" | grep --line-buffered '^tracelab:' >&2 || true
	tar xf "$W/out.img" -C "$OUT" 2>/dev/null || { echo "no results came back; see results/$NAME/console.log" >&2; exit 1; }
	[ "$(cat "$OUT/.exit" 2>/dev/null)" = 0 ] || { echo "experiment failed; tail of results/$NAME/run.log:" >&2; tail -n 20 "$OUT/run.log" >&2; exit 1; }
	rm -f "$OUT/.exit"
	;;
*) echo "unknown MODE '$MODE'" >&2; exit 1;;
esac
echo "tracelab: results in results/$NAME/" >&2
