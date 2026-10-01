#!/bin/bash
# Measure boot time and idle memory of a Wylde image in QEMU.
#
#   boot_seconds   guest uptime at the login prompt (kernel start -> login)
#   ram_idle_kib   MemTotal - MemAvailable once the system is up
#
# Writes JSON. CI compares it against benchmarks/baseline.json and fails when a
# number regresses (tools/check-regression.py).
set -e

IMG=${1:-/mnt/wylde/wylde.img}
KERNEL=${2:-/mnt/lfs/boot/vmlinuz-6.16.1-lfs-12.4}
OUT=${3:-/tmp/opencode/benchmark.json}
PORT=${4:-4561}
INITRD=${INITRD:-/root/distro/build/initramfs.cpio.gz}

# a guest from an interrupted run still holds the serial port and CPU
pkill -f "qemu-system-x86_64" 2>/dev/null || true
sleep 1

# KVM and TCG are not comparable: the same guest boots an order of magnitude
# faster with hardware virtualisation, so the measurement records which one ran
ACCEL=tcg
if [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
    ACCEL=kvm
fi
echo "benchmark: accelerator $ACCEL"

ROOT_UUID=$(blkid -o value -s UUID "$IMG" 2>/dev/null || true)
if [ -z "$ROOT_UUID" ]; then
    LOOP=$(losetup -f --show -P "$IMG")
    ROOT_UUID=$(blkid -o value -s UUID "${LOOP}p2")
    losetup -d "$LOOP"
fi

qemu-system-x86_64 \
    -m 2048 -smp 2 -accel "$ACCEL" -snapshot \
    -kernel "$KERNEL" \
    -initrd "$INITRD" \
    -append "root=UUID=$ROOT_UUID ro console=ttyS0,115200n8 init=/init panic=10" \
    -drive file="$IMG",format=raw,if=ide,index=0,media=disk \
    -boot c -display none \
    -serial "tcp:127.0.0.1:$PORT,server,nowait" \
    -nic user,model=virtio-net-pci >/dev/null 2>&1 &

sleep 3
set +e
python3 "$(dirname "$0")/measure.py" "$PORT" "$OUT" "$ACCEL"
STATUS=$?
set -e

pkill -f "qemu-system-x86_64.*$PORT" 2>/dev/null || true
[ -f "$OUT" ] && { echo "benchmark: $OUT"; cat "$OUT"; }
exit $STATUS
