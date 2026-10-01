#!/bin/bash
# Wylde — Linux 6.16.1 with a Wylde-tuned config (roadmap 1c)
set -e
export LFS=/mnt/lfs
export LOGDIR=${LOGDIR:-/tmp/wylde-build}
mkdir -p "$LOGDIR"
KV=6.16.1

echo "[$(date +%H:%M:%S)] START kernel" >> "$LOGDIR/build.log"
if chroot "$LFS" /usr/bin/env -i \
      HOME=/root TERM=dumb PS1='(wylde) #' \
      PATH=/usr/bin:/usr/sbin MAKEFLAGS="-j$(nproc)" \
      /bin/bash -s > "$LOGDIR/kernel.log" 2>&1 <<INNER
set -e
KV=$KV
cd /sources
rm -rf linux-\$KV
tar -xf linux-\$KV.tar.xz
cd linux-\$KV

# The book uses the reference config from ftp.kernel.org, but that file is no
# longer published there. x86_64_defconfig + the Wylde tuning pass below.
make x86_64_defconfig

./scripts/config --file .config \
  --disable DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT \
  --enable  DEBUG_INFO_NONE \
  --disable DEBUG_INFO_BTF \
  --disable DEBUG_INFO_BTF_MODULE \
  --disable DEBUG_KERNEL \
  --disable KALLSYMS_ALL \
  --enable  KALLSYMS \
  --disable MODULE_SIG \
  --disable MODULE_SIG_ALL \
  --disable MODULE_SIG_FORCE \
  --set-val MODULE_SIG_KEY "" \
  --set-val SYSTEM_TRUSTED_KEYS "" \
  --set-val SYSTEM_REVOCATION_KEYS "" \
  --disable GCC_PLUGINS \
  --disable GDB_SCRIPTS \
  --enable  DRM \
  --enable  DRM_KMS \
  --enable  FB \
  --enable  FBDEV \
  --enable  DRM_VIRTIO \
  --enable  DRM_BOCHS \
  --enable  DRM_AMDGPU \
  --enable  DRM_I915 \
  --enable  DRM_RADEON \
  --enable  SOUND \
  --enable  SND \
  --enable  SND_PCM \
  --enable  SND_HDA_INTEL \
  --enable  SND_HDA_INTEL_HDMI \
  --enable  SND_HDA_CODEC \
  --enable  SND_USB_AUDIO \
  --enable  USB_AUDIO \
  --disable WLAN \
  --disable BT \
  --enable  NETFILTER \
  --enable  NETFILTER_XTABLES \
  --enable  IP_NF_IPTABLES \
  --enable  IP_NF_FILTER \
  --enable  IP_NF_NAT \
  --enable  IP_NF_TARGET_MASQUERADE \
  --enable  NF_CONNTRACK \
  --enable  BRIDGE \
  --enable  BRIDGE_NETFILTER \
  --enable  EXT4_FS \
  --enable  EXT4_USE_FOR_EXT2 \
  --enable  EXT4_FS_POSIX_ACL \
  --enable  EXT4_FS_SECURITY \
  --enable  TMPFS \
  --enable  DEVTMPFS \
  --enable  DEVTMPFS_MOUNT \
  --enable  VIRTIO \
  --enable  VIRTIO_PCI \
  --enable  VIRTIO_BLK \
  --enable  VIRTIO_NET \
  --enable  VIRTIO_CONSOLE \
  --enable  HW_RANDOM_VIRTIO \
  --enable  ACPI \
  --enable  PCI \
  --enable  ATA_PIIX \
  --enable  ATA \
  --enable  BLK_DEV_SD \
  --enable  SERIAL_8250 \
  --enable  SERIAL_8250_CONSOLE \
  --enable  PRINTK \
  --enable  DEVKMSG \
  --enable  PROC_KMSG \
  --enable  PRINTK_TIME \
  --enable  MAGIC_SYSRQ \
  --disable IPV6_DEFAULT

make olddefconfig
make -j$(nproc) bzImage modules
make modules_install

mkdir -p /boot
cp -iv arch/x86/boot/bzImage /boot/vmlinuz-\$KV-lfs-12.4
cp -iv System.map /boot/System.map-\$KV
cp -iv .config /boot/config-\$KV
cp -r Documentation -T /usr/share/doc/linux-\$KV

install -v -m755 -d /etc/modprobe.d
cat > /etc/modprobe.d/usb.conf << "CONF"
# Begin /etc/modprobe.d/usb.conf
install ohci_hcd /sbin/modprobe ehci_hcd ; /sbin/modprobe -i ohci_hcd ; true
install uhci_hcd /sbin/modprobe ehci_hcd ; /sbin/modprobe -i uhci_hcd ; true
# End /etc/modprobe.d/usb.conf
CONF
ls -lh /boot/
INNER
then
  echo "[$(date +%H:%M:%S)] DONE kernel" >> "$LOGDIR/build.log"
else
  echo "[$(date +%H:%M:%S)] FAIL kernel — see $LOGDIR/kernel.log" >> "$LOGDIR/build.log"
  exit 1
fi
