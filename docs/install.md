# Installing Wylde Linux

## Requirements

| | Minimum | Recommended |
|---|---|---|
| RAM | 2 GB | 4 GB |
| Disk | 8 GB | 20 GB |
| CPU | any x86_64 | 2+ cores |
| Network | optional (for `wld sync`) | broadband |

Wylde boots on BIOS (legacy) systems and QEMU/KVM guests. UEFI is not yet
supported — GRUB is installed for `i386-pc`.

## From the ISO

1. Write `wylde.iso` (or the raw image) to a USB stick:

   ```bash
   dd if=wylde.iso of=/dev/sdX bs=4M status=progress
   ```

2. Boot the stick, log in as `root` (the first-boot image has no password).
3. Run the installer:

   ```bash
   sudo ./wylde-installer
   ```

The guided mode asks four questions — target device, partition layout, hostname,
timezone — and does everything else. Nothing is written to the disk before it
prints the device name back and asks you to type it again.

## Manual install

For anything unusual, drive the steps yourself. `wylde-installer --expert` asks
every question explicitly, and the script it runs is short enough to read first:

```bash
sudo less /path/to/wylde-installer
```

The steps, in order:

```bash
# 1. partition: 100 MB bootable, rest root (add a third for /home if wanted)
sfdisk /dev/sdX <<'EOF'
label: dos
unit: sectors
start=2048, size=204800, type=83, bootable
start=206848, size=4000000, type=83
EOF

# 2. format
mkswap /dev/sdX1
mkfs.ext4 -L wylde /dev/sdX2

# 3. mount and copy
mount /dev/sdX2 /mnt
rsync -aAXH --one-file-system --exclude=/mnt/lfs / /mnt/

# 4. fstab (use blkid to get the UUIDs)
cat > /mnt/etc/fstab <<'EOF'
UUID=<root>   /        ext4  defaults,noatime  0 1
UUID=<swap>   swap     swap  defaults          0 0
proc          /proc    proc  defaults          0 0
sysfs         /sys     sysfs defaults          0 0
devpts        /dev/pts devpts gid=5,mode=0620 0 0
tmpfs         /run     tmpfs defaults,mode=0755 0 0
devtmpfs      /dev     devtmpfs defaults      0 0
tmpfs         /dev/shm tmpfs defaults          0 0
EOF

# 5. bootloader
mkdir -p /mnt/boot/grub
chroot /mnt /usr/sbin/grub-install --target=i386-pc /dev/sdX
chroot /mnt /usr/sbin/grub-mkconfig -o /boot/grub/grub.cfg

umount -R /mnt
reboot
```

## After the first boot

```bash
wylde-doctor              # what is running, what is using memory
wld sync                  # see what the repository offers
wld install git           # or curl, or htop, or anything else in ports/
```

Set a root password, or better, a normal user with `sudo`:

```bash
passwd root
useradd -m -G wheel yourname
passwd yourname
```

`wheel` is the group `sudo` trusts (see `/etc/sudoers`). If your image still has
an empty root password, do this before putting the machine on a network.
