#!/bin/bash
# Wylde — full build: LFS 12.4 + Wylde additions, from an empty $LFS to a
# bootable disk image. Run as root.
set -e
cd "$(dirname "$0")"

# Building LFS means mounting filesystems and switching to the lfs user, which
# is root work. Saying so up front beats a confusing "su: must be run from a
# terminal" three seconds in.
if [ "$(id -u)" -ne 0 ]; then
    echo "build/all.sh must run as root (it mounts /proc, /sys and /dev into $LFS)" >&2
    echo "try: sudo -E ./build/all.sh" >&2
    exit 1
fi

echo "=== Wylde build start: $(date) ==="

for phase in 01-toolchain 02-chroot 03-chroot-tools 04-bootcritical \
             05-kernel 06-grub 07-shadow 08-udev-sysklogd 09-dhcpcd; do
  echo "--- $phase"
  ./$phase.sh
done

echo "--- disk image"
./../scripts/make-disk-image.sh

echo "=== Wylde build done: $(date) ==="
echo "Boot it with: ./scripts/qemu-boot.sh"
