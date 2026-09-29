#!/bin/bash
# Wylde — build a bootable disk image (roadmap 1d)
# Layout: MBR (legacy BIOS/GRUB) + 2 partitions (swap, root ext4)
set -e
LFS=/mnt/lfs
IMG=${1:-/mnt/wylde/wylde.img}
MNT=/mnt/wyldemnt
KV=6.16.1

mkdir -p /mnt/wylde
if [ ! -f "$IMG" ]; then
  echo "creating $IMG (6 GiB sparse)"
  truncate -s 6G "$IMG"
fi

LOOP=$(losetup -f --show -P "$IMG")
echo "loop device: $LOOP"
PART1=${LOOP}p1
PART2=${LOOP}p2

if [ -z "$(blkid -o value -s TYPE $PART2 2>/dev/null)" ]; then
  echo "partitioning"
  sfdisk "$LOOP" <<'EOF'
label: dos
unit: sectors

start=2048, size=204800, type=83, bootable
start=206848, size=12000000, type=83
EOF
  partprobe "$LOOP" || true
  sleep 2
fi

mkswap -q "$PART1"
if ! blkid -o value -s TYPE "$PART2" | grep -q ext4; then
  mkfs -q -t ext4 -L wylde "$PART2"
fi

mkdir -p "$MNT"
mount "$PART2" "$MNT"
mkdir -p "$MNT/boot" "$MNT/proc" "$MNT/sys" "$MNT/dev" "$MNT/run" "$MNT/tmp"
chmod 1777 "$MNT/tmp"

echo "syncing root filesystem into image"
# /sources and /tools are build-time only: source trees and the cross toolchain.
# /usr/bin/gcc (the cross compiler) stays in the image and works for this arch.
rsync -aAXH --delete --one-file-system \
  --exclude=/dev --exclude=/proc --exclude=/sys --exclude=/run --exclude=/tmp \
  --exclude=/sources --exclude=/tools --exclude=/mnt/lfs \
  "$LFS"/ "$MNT"/

echo "writing fstab (UUID-based: loop device names change between runs)"
UUID_ROOT=$(blkid -o value -s UUID "$PART2")
UUID_SWAP=$(blkid -o value -s UUID "$PART1")
cat > "$MNT/etc/fstab" <<EOF
# Begin /etc/fstab
# <file system> <mount point> <type> <options> <dump> <fsck order>
UUID=$UUID_ROOT	/		ext4	defaults,noatime	0 1
UUID=$UUID_SWAP	swap	swap	defaults	0 0
proc	/proc	proc	defaults	0 0
sysfs	/sys	sysfs	defaults	0 0
devpts	/dev/pts	devpts	gid=5,mode=0620	0 0
tmpfs	/run	tmpfs	defaults,mode=0755	0 0
devtmpfs	/dev	devtmpfs	defaults	0 0
tmpfs	/dev/shm	tmpfs	defaults	0 0
cgroup2	/sys/fs/cgroup	cgroup2	defaults	0 0
# End /etc/fstab
EOF

echo "installing GRUB"
mkdir -p "$MNT"/{dev,proc,sys}
mount --bind /dev "$MNT/dev"
mount -t proc proc "$MNT/proc"
mount -t sysfs sysfs "$MNT/sys"
chroot "$MNT" /usr/sbin/grub-install --target=i386-pc "$LOOP" --recheck
# grub-mkconfig derives root= from the running system, which is the loop device;
# force the name the guest will actually see (sda for the IDE disk in QEMU)
chroot "$MNT" /usr/sbin/grub-mkconfig -o /boot/grub/grub.cfg
sed -i "s|root=UUID=$UUID_ROOT|root=/dev/sda2|; s|root=/dev/loop[0-9]*p2|root=/dev/sda2|" \
  "$MNT/boot/grub/grub.cfg"
umount "$MNT/proc" "$MNT/sys" "$MNT/dev"

echo "unmounting"
umount "$MNT"
losetup -d "$LOOP"

echo "IMAGE_READY: $IMG"
ls -lh "$IMG"
