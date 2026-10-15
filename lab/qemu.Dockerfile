# The machine room: QEMU and mke2fs, kept out of the guest image.
FROM alpine:3.22
RUN apk add --no-cache qemu-system-x86_64 e2fsprogs tar
