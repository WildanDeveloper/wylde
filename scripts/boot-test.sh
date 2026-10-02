#!/bin/bash
# Boot test: the image must reach a login prompt.
#
# Separate from benchmark.sh on purpose. A regression in the measurement code
# should not be able to hide a system that does not boot, and vice versa.
set -e

IMG=${1:-/mnt/wylde/wylde.img}
KERNEL=${2:-/mnt/lfs/boot/vmlinuz-6.16.1-lfs-12.4}
INITRD=${INITRD:-/root/distro/build/initramfs.cpio.gz}
PORT=${PORT:-4571}
TIMEOUT=${BOOT_TIMEOUT:-900}
LOG=${LOG:-/tmp/wylde-boot.log}

log() { echo "[boot-test] $*"; }

# the bracket keeps pkill from matching its own command line
pkill -f '[q]emu-system-x86_64' 2>/dev/null || true
sleep 1

[ -f "$IMG" ] || { log "no image at $IMG"; exit 1; }
[ -f "$KERNEL" ] || { log "no kernel at $KERNEL"; exit 1; }

ROOT_UUID=$(blkid -o value -s UUID "$IMG" 2>/dev/null || true)
if [ -z "$ROOT_UUID" ]; then
    LOOP=$(losetup -f --show -P "$IMG")
    ROOT_UUID=$(blkid -o value -s UUID "${LOOP}p2")
    losetup -d "$LOOP"
fi
log "root uuid $ROOT_UUID"

qemu-system-x86_64 \
    -m 2048 -smp 2 -accel tcg,thread=multi -snapshot \
    -kernel "$KERNEL" \
    -initrd "$INITRD" \
    -append "root=UUID=$ROOT_UUID ro console=ttyS0,115200n8 init=/init panic=10" \
    -drive file="$IMG",format=raw,if=ide,index=0,media=disk \
    -boot c -display none \
    -serial "tcp:127.0.0.1:$PORT,server,nowait" \
    -nic user,model=virtio-net-pci >/dev/null 2>&1 &
QEMU_PID=$!
trap 'kill $QEMU_PID 2>/dev/null || true' EXIT

log "waiting for the login prompt (up to ${TIMEOUT}s)"
python3 - "$PORT" "$TIMEOUT" "$LOG" << 'PY'
import socket, sys, time
port, timeout, log = int(sys.argv[1]), int(sys.argv[2]), sys.argv[3]
deadline = time.time() + timeout
try:
    sock = socket.create_connection(("127.0.0.1", port), timeout=10)
except OSError as e:
    sys.exit(f"cannot reach the serial port: {e}")
sock.settimeout(1.0)
buf = []
while time.time() < deadline:
    try:
        chunk = sock.recv(4096).decode("utf-8", "replace")
    except socket.timeout:
        continue
    if not chunk:
        break
    buf.append(chunk)
    text = "".join(buf)
    if "login:" in text:
        open(log, "w").write(text)
        sys.exit(0)
    if "Kernel panic" in text:
        open(log, "w").write(text)
        sys.exit("the guest panicked")
open(log, "w").write("".join(buf))
sys.exit(f"no login prompt within {timeout}s (transcript: {log})")
PY

log "reached the login prompt"