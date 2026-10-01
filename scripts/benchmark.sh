#!/bin/bash
# Measure boot time and idle memory of the Wylde image in QEMU.
#
#   boot_seconds   kernel's own clock from the first message to the login prompt
#   ram_idle_kib   MemTotal - MemAvailable once the system is up and idle
#
# Writes a JSON document. CI compares it against benchmarks/baseline.json and
# fails the build when a number regresses beyond the allowed percentage.
set -e

IMG=${1:-/mnt/wylde/wylde.img}
KERNEL=${2:-/mnt/lfs/boot/vmlinuz-6.16.1-lfs-12.4}
INITRD=${INITRD:-/root/distro/build/initramfs.cpio.gz}
OUT=${3:-/tmp/opencode/benchmark.json}
PORT=${4:-4557}

ROOT_UUID=$(blkid -o value -s UUID "$IMG" 2>/dev/null || true)
if [ -z "$ROOT_UUID" ]; then
    LOOP=$(losetup -f --show -P "$IMG")
    ROOT_UUID=$(blkid -o value -s UUID "${LOOP}p2")
    losetup -d "$LOOP"
fi

qemu-system-x86_64 \
    -m 2048 -smp 2 -accel tcg,thread=multi -snapshot \
    -kernel "$KERNEL" \
    -initrd "$INITRD" \
    -append "root=UUID=$ROOT_UUID ro console=ttyS0,115200n8 init=/init panic=10" \
    -drive file="$IMG",format=raw,if=ide,index=0,media=disk \
    -boot c -display none \
    -serial "tcp:127.0.0.1:$PORT,server,nowait" \
    -nic user,model=virtio-net-pci >/dev/null 2>&1 &

sleep 3
python3 - "$PORT" "$OUT" <<'PY'
import json, socket, sys, time

port = int(sys.argv[1])
out_path = sys.argv[2]

s = socket.create_connection(("127.0.0.1", port), timeout=5)
s.settimeout(1.0)

text = ""
boot_clock = None
deadline = time.time() + 900
while time.time() < deadline:
    try:
        chunk = s.recv(4096)
    except socket.timeout:
        continue
    if not chunk:
        break
    piece = chunk.decode("utf-8", "replace")
    text += piece
    if "login:" in text and boot_clock is None:
        # the last kernel timestamp before the login prompt is the boot time
        stamps = []
        for line in text.splitlines():
            if line.startswith("[") and "]" in line:
                try:
                    stamps.append(float(line[1:line.index("]")]))
                except ValueError:
                    pass
        if stamps:
            boot_clock = max(stamps)
        break

if "login:" not in text:
    print("benchmark failed: the guest never reached a login prompt")
    sys.exit(1)

def send(line):
    s.sendall(line.encode() + b"\n")

def read_until(marker, timeout=120):
    global text
    end = time.time() + timeout
    while time.time() < end:
        if marker in text:
            return True
        try:
            chunk = s.recv(4096)
        except socket.timeout:
            continue
        if not chunk:
            break
        piece = chunk.decode("utf-8", "replace")
        text += piece
    return marker in text

# the login banner takes a while under TCG emulation
send("root")
if not read_until("Password:", timeout=180):
    send("")
read_until("Password:", timeout=60)
send("")
if not read_until("# ", timeout=180):
    print("benchmark failed: no shell prompt after login")
    sys.exit(1)

send("cat /proc/meminfo | head -3; echo __DONE__")
read_until("__DONE__")
send("exit")

mem_total = None
mem_available = None
for line in text.splitlines():
    if line.startswith("MemTotal:"):
        mem_total = int(line.split()[1])
    elif line.startswith("MemAvailable:"):
        mem_available = int(line.split()[1])

result = {
    "boot_seconds": round(boot_clock, 2) if boot_clock else None,
    "ram_total_kib": mem_total,
    "ram_idle_kib": (mem_total - mem_available) if mem_total and mem_available else None,
}
with open(out_path, "w") as f:
    json.dump(result, f, indent=2)
print(json.dumps(result, indent=2))
PY

pkill -f "qemu-system-x86_64.*$PORT" 2>/dev/null || true
echo "benchmark: $OUT"
