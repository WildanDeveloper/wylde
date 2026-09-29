# Wylde build system

Every script here is derived verbatim from the **LFS 12.4** book, with every
deviation documented in [`../docs/build-notes.md`](../docs/build-notes.md).
Run them in order, as root:

```bash
sudo ./build/all.sh          # everything, start to finish
```

or one phase at a time:

| Script | What it builds | LFS chapter |
|--------|----------------|-------------|
| `01-toolchain.sh` | binutils → gcc pass 1 → glibc → libstdc++ → 15 tools → binutils/gcc pass 2 | ch. 5, as user `lfs` |
| `02-chroot.sh` | chroot entry, directory tree, essential files | ch. 7 step 1 |
| `03-chroot-tools.sh` | gettext, bison, perl, Python, texinfo, util-linux | ch. 7 |
| `04-bootcritical.sh` | bzip2, zlib, zstd, pkgconf, ninja, meson, kmod, bison, flex, libelf, ncurses, procps, iproute2, e2fsprogs, sysvinit, bootscripts | subset of ch. 8 |
| `05-kernel.sh` | Linux 6.16.1, Wylde-tuned config | ch. 10 |
| `06-grub.sh` | gperf, libtool, autoconf, automake, GRUB 2.12 | subset of ch. 8 |
| `07-shadow.sh` | libcap, libxcrypt, attr, acl, shadow + `/etc/inittab` and friends | subset of ch. 8 + ch. 9 |
| `../scripts/make-disk-image.sh` | partitioned ext4 image, fstab, GRUB install | ch. 10 |
| `../scripts/qemu-boot.sh` | boots the image, serial console on stdio | — |

## Requirements

* Debian 12+ host, 4+ cores, 8 GB RAM **and 4 GB swap** (see build notes: the
  `insn-automata` step of gcc gets OOM-killed without swap)
* LFS host requirements satisfied (`version-check.sh` clean, `/bin/sh` → bash)
* Packages under `/mnt/lfs/sources`, checksums verified against the LFS
  `md5sums` file
* Scripts 02+ expect the kernel filesystems from script 01 to stay mounted;
  the chain aborts loudly if a stage fails

## Environment

* `LFS=/mnt/lfs` — the target root
* `LFS_TGT=x86_64-lfs-linux-gnu` — cross target
* Log directory: `/tmp/wylde-build` (override with `LOGDIR=...`)
* The `lfs` user builds ch. 5; everything after the chroot is built as root
  inside the chroot

## Known deviations from LFS 12.4

See `docs/build-notes.md` for the full story. Summary:

1. `ncurses` — the book's `6.5-20250809.tgz` snapshot is gone from every mirror
   (including `invisible-mirror.net`, which the book links); Wylde uses
   `6.6-20260926.tgz`. No patches are involved, so nothing version-locked breaks.
2. `kmod` — built with `-D openssl=disabled` (no module signing), so OpenSSL
   is not a kmod dependency.
3. `meson` — installed from its source tree instead of via `pip3`, because the
   chroot Python is built `--without-ensurepip`.
4. Kernel — `make x86_64_defconfig` plus a Wylde tuning pass (`scripts/config`)
   instead of the kernel.org reference config, which is no longer published.
   Debug info, module signing, GCC plugins, DRM, sound, WLAN and Bluetooth are
   off; netfilter, ext4, virtio, ACPI and devtmpfs are built in. The 6.16
   `defconfig` is nearly all built-in (13 modules), which is also why the
   kernel image is 11 MB with no module dependencies at boot.
