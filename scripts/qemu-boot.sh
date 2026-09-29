#!/bin/bash
# Boot the Wylde image in QEMU (TCG, since nested KVM is unavailable).
# Serial console on stdio so the boot is scriptable; VNC display :1 for graphical.
IMG=${1:-/mnt/wylde/wylde.img}
MEM=${MEM:-2048}
DISK=${DISK:-sda}

exec qemu-system-x86_64 \
  -m "$MEM" \
  -smp 2 \
  -accel tcg,thread=multi \
  -snapshot \
  -drive file="$IMG",format=raw,if=ide,index=0,media=disk \
  -boot c \
  -serial mon:stdio \
  -display none \
  -nic user,model=virtio-net-pci \
  "$@"
