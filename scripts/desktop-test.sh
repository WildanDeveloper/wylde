#!/bin/bash
# Wylde — boot the image with a graphics device and prove the session works.
#
# The unit of trust for a desktop is not "the compositor started". It is "a
# client connected and the compositor answered". scripts/benchmark.sh measures
# the command line system; this measures the session.
#
#   1. boot with a virtual GPU and USB input, as a real machine would
#   2. wait for the login prompt
#   3. log in and ask the session what it has: udev, seatd, one compositor
#   4. connect with wylde-session-probe and count the globals it serves
#
# Fails when the session is missing, when more than one compositor is running,
# or when the probe cannot connect.
set -e

IMG=${1:-/mnt/wylde/wylde.img}
PORT=${PORT:-4595}
ACCEL=${ACCEL:-tcg}
ROOT=${WYLDE_ROOT:-/root/lfs-root}
KERNEL=${KERNEL:-$ROOT/boot/vmlinuz-6.16.1-lfs-12.4}
INITRD=${INITRD:-/root/distro/build/initramfs.cpio.gz}
LOG=${LOG:-/tmp/wylde-desktop-test.log}

log() { echo "[desktop-test] $*"; }

# the bracket keeps pkill from matching its own command line
pkill -f '[q]emu-system-x86_64' 2>/dev/null || true
sleep 1

[ -f "$KERNEL" ] || { log "no kernel at $KERNEL"; exit 1; }

ROOT_UUID=$(blkid -o value -s UUID "$IMG" 2>/dev/null || true)
if [ -z "$ROOT_UUID" ]; then
    LOOP=$(losetup -f --show -P "$IMG")
    ROOT_UUID=$(blkid -o value -s UUID "${LOOP}p2")
    losetup -d "$LOOP"
fi

ACCEL_ARGS=tcg,thread=multi
[ "$ACCEL" = kvm ] && ACCEL_ARGS=kvm

log "booting $IMG with accel=$ACCEL"
qemu-system-x86_64 \
    -m 2048 -smp 2 -accel "$ACCEL_ARGS" -snapshot \
    -kernel "$KERNEL" \
    -initrd "$INITRD" \
    -append "root=UUID=$ROOT_UUID ro console=ttyS0,115200n8 init=/init panic=10" \
    -drive file="$IMG",format=raw,if=ide,index=0,media=disk \
    -device virtio-gpu-pci \
    -usb -device usb-kbd -device usb-tablet \
    -boot c -display none \
    -serial "tcp:127.0.0.1:$PORT,server,nowait" \
    -nic user,model=virtio-net-pci >/dev/null 2>&1 &

sleep 3
set +e
python3 "$(dirname "$0")/session-check.py" "$PORT" "$LOG"
STATUS=$?
set -e

pkill -f "[q]emu-system-x86_64.*$PORT" 2>/dev/null || true

if [ $STATUS -eq 0 ]; then
    log "the session is up: see $LOG"
else
    log "the session did not come up: see $LOG"
fi
exit $STATUS