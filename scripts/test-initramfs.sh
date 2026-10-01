#!/bin/bash
# Test the initramfs path directly: kernel + initrd from the build tree, root
# disk attached. Skips GRUB so the probe and switch_root are what is under test.
set -e
IMG=${1:-/mnt/wylde/wylde.img}
KERNEL=${2:-/mnt/lfs/boot/vmlinuz-6.16.1-lfs-12.4}
INITRD=${3:-/root/distro/build/initramfs.cpio.gz}
LOG=${4:-/tmp/opencode/initramfs-boot.log}

LOOP=$(losetup -f --show -P "$IMG")
UUID=$(blkid -o value -s UUID ${LOOP}p2)
losetup -d "$LOOP"
echo "root uuid: $UUID"

timeout 300 qemu-system-x86_64 \
  -m 2048 -smp 2 -accel tcg,thread=multi -snapshot \
  -kernel "$KERNEL" -initrd "$INITRD" \
  -append "root=UUID=$UUID ro console=ttyS0,115200n8 init=/init panic=10" \
  -drive file="$IMG",format=raw,if=ide,index=0,media=disk \
  -boot c -display none \
  -serial tcp:127.0.0.1:4556,server,nowait \
  -nic user,model=virtio-net-pci > /dev/null 2>&1 &

sleep 3
python3 - "$LOG" <<'PY'
import socket, sys, time
log = sys.argv[1]
deadline = time.time() + 280
text = ""
s = socket.create_connection(("127.0.0.1", 4556), timeout=5)
s.settimeout(1.0)
while time.time() < deadline:
    try:
        chunk = s.recv(4096)
    except socket.timeout:
        continue
    if not chunk:
        break
    piece = chunk.decode("utf-8", "replace")
    text += piece
    sys.stdout.write(piece)
    sys.stdout.flush()
    if "wylde login" in text or "fatal" in text or "panic" in text:
        time.sleep(3)
        break
open(log, "w").write(text)
PY
pkill -f 'qemu-system-x86_64\[.*initrd' 2>/dev/null || true
echo "log: $LOG"
