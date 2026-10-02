#!/bin/bash
# Wylde — publish the working chroot into a fresh bootable image.
#
# The chroot has to live somewhere a compiler can use, and it needs to survive
# being rebuilt. It lives in its own image on a loop device:
#
#   /mnt/wylde/wylde-chroot.img   the chroot, attached with losetup -P
#   /mnt/lfs.chroot               where it is mounted while building
#   /root/lfs-root                a plain copy of it, the source for an image
#   /mnt/wylde/wylde.img          the bootable image, built from that copy
#
# Copying out is not optional. rsync-ing a mounted filesystem back onto the
# image it came from corrupts the image — that happened once, and it cost a
# rebuilt tree.
set -e

CHROOT_IMG=${CHROOT_IMG:-/mnt/wylde/wylde-chroot.img}
CHROOT_MNT=${CHROOT_MNT:-/mnt/lfs.chroot}
STAGE=${STAGE:-/root/lfs-root}
OUT_IMG=${OUT_IMG:-/mnt/wylde/wylde.img}

log() { echo "[publish] $*"; }

LOOP=""

detach() {
    if mountpoint -q "$CHROOT_MNT"; then
        umount "$CHROOT_MNT" 2>/dev/null || umount -l "$CHROOT_MNT"
    fi
    if [ -n "$LOOP" ]; then
        losetup -d "$LOOP" 2>/dev/null || true
        LOOP=""
    fi
}

trap detach EXIT

log "attaching the chroot image"
mkdir -p "$(dirname "$CHROOT_IMG")" "$CHROOT_MNT" "$STAGE"

if [ ! -f "$CHROOT_IMG" ]; then
    log "creating a 16G sparse chroot image"
    truncate -s 16G "$CHROOT_IMG"
fi

LOOP=$(losetup -f --show -P "$CHROOT_IMG")
log "loop device $LOOP"

if ! sfdisk -l "$LOOP" 2>/dev/null | grep -q '^Device'; then
    log "writing a partition table"
    sfdisk "$LOOP" >/dev/null <<'PART'
label: dos
unit: sectors
start=2048, size=204800, type=83, bootable
start=206848, type=83
PART
    partprobe "$LOOP" || true
    sleep 2
    if ! blkid -o value -s TYPE "${LOOP}p2" 2>/dev/null | grep -q ext4; then
        log "formatting"
        mkfs -q -t ext4 -L wylde-chroot "${LOOP}p2"
    fi
else
    # A filesystem blkid cannot read is usually a dirty journal. Fixing that
    # costs nothing; reformatting would destroy the tree.
    log "checking the filesystem"
    e2fsck -fy "${LOOP}p2" >/dev/null 2>&1 || true
fi

mount "${LOOP}p2" "$CHROOT_MNT" || {
    log "will not mount; run: e2fsck -fy ${LOOP}p2"
    exit 1
}
log "chroot mounted at $CHROOT_MNT ($(ls "$CHROOT_MNT" | wc -l) entries)"

log "installing the desktop session"
# 18-desktop.sh compiles the session probe inside the chroot, which needs
# /dev/null and /proc. Without them gcc fails on a missing device node.
mkdir -p "$CHROOT_MNT"/{dev,proc,sys}
mount --bind /dev "$CHROOT_MNT/dev"
mount -t proc proc "$CHROOT_MNT/proc"
mount --bind /sys "$CHROOT_MNT/sys"
LFS="$CHROOT_MNT" LOGDIR="${LOGDIR:-/tmp/wylde-build}" ./build/18-desktop.sh >/dev/null
umount "$CHROOT_MNT/proc" "$CHROOT_MNT/sys" "$CHROOT_MNT/dev" 2>/dev/null || true
log "session installed"

log "copying the tree into $STAGE for the image build"
# /boot/grub is written by make-disk-image; a stale one makes grub-install fail
rsync -aH --delete --exclude=/boot/grub "$CHROOT_MNT/" "$STAGE/"
rm -rf "$STAGE/boot/grub"
log "staged $(du -sh "$STAGE" | cut -f1)"

detach
trap - EXIT

log "building $OUT_IMG from the staged copy"
LFS="$STAGE" ./scripts/make-disk-image.sh "$OUT_IMG"

log "done: $OUT_IMG ($(du -h "$OUT_IMG" | cut -f1))"
log "boot it with: ./scripts/qemu-boot.sh"