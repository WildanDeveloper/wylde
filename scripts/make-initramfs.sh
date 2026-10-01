#!/bin/bash
# Build the Wylde initramfs: static musl utilities, a tiny shell, and the init.
#
#   probe  — finds the root filesystem by UUID or path (src/initramfs/probe.c)
#   sh     — a small static shell to run the init script
#   init   — mounts, probes, switch_root
#
# Everything is statically linked with musl: the initramfs has no shared
# libraries of its own, which is what lets it run before the real libc exists.
set -e

OUT=${1:-/mnt/wylde/initramfs}
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)

command -v musl-gcc >/dev/null || { echo "musl-gcc is required (apt install musl-tools)" >&2; exit 1; }

rm -rf "$OUT"
mkdir -p "$OUT"/{bin,sbin,dev,proc,sys,run,newroot}
cp -a "$ROOT/.git" /dev/null 2>/dev/null || true

echo "building probe (static musl)"
musl-gcc -O2 -Wall -Wextra -static -Wno-format-truncation \
    -o "$OUT/bin/probe" "$ROOT/src/initramfs/probe.c"

echo "building a static shell for the initramfs"
# dash is small and static-friendly; fall back to busybox if available
if [ -f /mnt/lfs/usr/bin/busybox ]; then
    cp /mnt/lfs/usr/bin/busybox "$OUT/bin/busybox"
elif command -v busybox >/dev/null; then
    cp "$(command -v busybox)" "$OUT/bin/busybox"
else
    echo "a static busybox is required (apt install busybox-static)" >&2
    exit 1
fi

cp "$ROOT/src/initramfs/init" "$OUT/init"
chmod 755 "$OUT/init"
if [ -f "$OUT/bin/busybox" ]; then
    for applet in sh ash mount umount mkdir switch_root cat ls sleep dmesg; do
        [ -e "$OUT/bin/$applet" ] || ln -sf busybox "$OUT/bin/$applet"
    done
fi

echo "packing initramfs"
( cd "$OUT" && find . | cpio -o -H newc --quiet ) | gzip -9 > "$ROOT/build/initramfs.cpio.gz"

ls -lh "$ROOT/build/initramfs.cpio.gz"
echo "initramfs: $ROOT/build/initramfs.cpio.gz"
