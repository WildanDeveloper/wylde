# Wylde — Build Notes

Every build error and its fix, recorded as they happen. This file becomes part of
the project documentation later.

Base: LFS 12.4 (stable). Build host: Debian 13 (trixie), x86_64, 4 cores.

---

## Phase 0 — Host preparation

### Missing host toolchain
`version-check.sh` reported missing `binutils`, `bison`, `flex`, `m4`, `texinfo`.
**Fix:** `apt-get install -y binutils bison flex m4 texinfo`

### `/bin/sh` was dash, not bash
```
ERROR: sh   is NOT Bash
```
LFS requires `/bin/sh` → `bash`. Debian defaults to dash.
**Fix:** `ln -sf bash /bin/sh` (revert with `ln -sf dash /bin/sh`)

### `version-check.sh` is not downloadable
`https://www.linuxfromscratch.org/lfs/downloads/stable/version-check.sh` → 404.
The script is embedded in the book HTML (chapter 2.2 "Host System Requirements").
**Fix:** extract the heredoc from
`https://www.linuxfromscratch.org/lfs/view/stable/chapter02/hostreqs.html`

---

## Phase 1a — Cross toolchain (LFS ch. 5)

### gcc pass 1 died with `Error 137`
```
make[2]: *** [Makefile:2786: s-automata] Error 137
```
Error 137 = SIGKILL = OOM killer. The host had 7.7 GB RAM but only ~1.2 GB
available (desktop session: gnome-shell, Chrome, two agent sessions).
`insn-automata`/`attribs` each need ~1.5 GB.
**Fix:** created a 4 GB swapfile. Both gcc passes then completed without OOM:
```bash
fallocate -l 4G /swapfile && chmod 600 /swapfile
mkswap /swapfile && swapon /swapfile
```

### `limits.h` merge failed: `No such file or directory`
```
bash: line 44: /include/limits.h: No such file or directory
```
The final gcc pass 1 step calls `$LFS_TGT-gcc`, which was not on `PATH`. My
`~/.bashrc` was missing two lines the book specifies (LFS 12.4, section 4.4):
```bash
PATH=$LFS/tools/bin:$PATH
CONFIG_SITE=$LFS/usr/share/config.site
```
**Fix:** added both to the lfs login environment.

### glibc failed instantly: `ln: failed to create symbolic link ... No such file or directory`
```
ln -sfv ../lib/ld-linux-x86-64.so.2 $LFS/lib64                        # ok
ln -sfv ../lib/ld-linux-x86-64.so.2 $LFS/lib64/ld-lsb-x86-64.so.3     # FAIL
```
Root cause: I skipped **chapter 2.7 "Creating the Minimal Layout"**. Without
`mkdir -pv $LFS/lib64`, the first `ln` created `lib64` as a dangling symlink, and
the second command could not descend into it. The book's "several syntactic
versions" note only works when `lib64` is a real directory — `ln -sf A DIR`
places `A`'s basename *inside* the directory.
**Fix:**
```bash
mkdir -pv $LFS/{etc,var} $LFS/usr/{bin,lib,sbin}
for i in bin lib sbin; do ln -sv usr/$i $LFS/$i; done
mkdir -pv $LFS/lib64
```

### ncurses tarball no longer exists
`ncurses-6.5-20250809.tgz` (pinned by LFS 12.4) returns 404 from every mirror:
the book's `invisible-mirror.net` link is dead, and `invisible-island.net` only
keeps `.patch.gz` files for 6.5 now.
**Fix:** used the current snapshot `ncurses-6.6-20260926.tgz` from
`invisible-island.net/archives/ncurses/current/`. Safe: LFS 12.4 builds ncurses
without patches, so there is nothing version-locked to break.

---

## Automation lessons (ch. 5 driven by script)

- **Always `rm -rf` the source directory before `tar -xf`.** Extracting over a
  stale tree leaves old `build/` dirs behind, and the book's `mkdir -v build`
  then aborts the whole run.
- **Log directories must be writable by the build user.** `/tmp/opencode/chain`
  was created by root; the `lfs` user could not write to it, so the chain
  aborted before logging anything.
- **`su - lfs -c '...'` is broken when the login profile uses `exec`.** The
  LFS-mandated `~/.bash_profile` execs `env -i ... /bin/bash`, which discards the
  `-c` command. Feed scripts through stdin instead: `su - lfs < script.sh`.
- **Never use `pkill -f <pattern>` where the pattern also matches the invoking
  command line** — it kills the caller's own shell.

---

## Verification (ch. 5 complete)

Toolchain proven end-to-end by compiling and *running* static binaries:
```bash
$LFS_TGT-gcc -static hello.c -o hello && ./hello    # exit 42
$LFS_TGT-g++ -static hello.cpp -o hello && ./hello # "cpp ok: 42"
```
228 binaries installed under `$LFS/usr/bin`. The cross toolchain (binutils 2.45,
gcc 15.2.0, glibc 2.42, libstdc++) is functional.

---

## Phase 1b — Chroot + basic system (LFS ch. 7)

Entered the chroot as root, created the directory tree and essential files, then
built the temporary tools: gettext 0.26, bison 3.8.2, perl 5.42.0, Python 3.13.7,
texinfo 7.2, util-linux 2.41.1.

### `install: invalid user 'tester'`
The book's `createfiles` block runs `install -o tester -d /home/tester` — the
`tester` account must already exist in `/etc/passwd` when that runs. Extracted
command blocks lose their surrounding order, so the append had to precede the
install. Reruns are guarded with `grep -q '^tester:'` to avoid duplicate entries.

### `ln: failed to create symbolic link '/etc/mtab': File exists`
Book uses `ln -sv` (not `-f`), so the stage is not rerunnable. Changed to
`ln -sfv` for idempotency.

### Chroot automation notes
- The chroot's `/usr/bin/gcc` is the cross compiler: `--host` and `--target` are
  both `x86_64-lfs-linux-gnu`, so the drivers install unprefixed. Inside the
  chroot, plain `make` produces correct target binaries — `/tools/bin` does not
  need to be in `PATH`.
- Kernel filesystems (`devpts`, `proc`, `sysfs`, `tmpfs` on `/run`, `/dev/shm`)
  must stay mounted for the whole chroot phase. The chain script checks
  `mountpoint` before mounting, so reruns are safe.

### Verification (chroot)
```bash
chroot /mnt/lfs /usr/bin/env -i PATH=/usr/bin:/usr/sbin /bin/bash -c \
  'printf "int main(){puts(\"ok\");}" > /tmp/x.c && gcc /tmp/x.c -o /tmp/x && /tmp/x'
# wylde chroot ok — dynamically linked, runs against /usr/lib/libc.so.6
```
bash 5.3.0, coreutils 9.7, Python 3.13.7, perl 5.42.0, util-linux 2.41.1 all
functional inside the target root.

---

## Phase 1b (cont.) — Boot-critical packages (subset of LFS ch. 8)

Built the packages needed for a first boot: ninja 1.13.1, meson 1.8.3, zlib
1.3.1, zstd 1.5.7, pkgconf 2.5.1, kmod 34.2, bison 3.8.2, flex 2.6.4,
procps-ng 4.0.5, iproute2 6.16.0, e2fsprogs 1.47.3, sysvinit 3.14 + bootscripts.

### `ModuleNotFoundError: No module named 'mesonbuild'`
The book's meson install relies on `pip3`, but the ch. 7 Python was built with
`--without-ensurepip`, so there is no pip. Installed meson from source instead:
tree copied to `/usr/lib/meson` with a `/usr/bin/meson` shim that prepends it to
`sys.path`. Do **not** `os.chdir()` in the shim — meson resolves the source
directory relative to the caller's cwd.

### `ModuleNotFoundError: No module named 'zlib'` (inside the chroot)
Ch. 7 Python builds before zlib exists, so its zlib module is missing, and meson
cannot even `import gzip`. Fixed by building zlib from ch. 8 and rebuilding
Python — exactly the order the book uses. Also created `/etc/ld.so.conf` early
(planned for ch. 9) because the shared-library install steps need `ldconfig`.

### kmod: `Dependency "libcrypto" not found`
kmod wants OpenSSL for PKCS#7-signed modules. Wylde does not sign modules, so
built with `-D openssl=disabled` instead of pulling in OpenSSL — lean by design.

### procps: `Cannot find ncurses wide library ncursesw with --enable-watch8bit`
The ch. 7 ncurses is a stripped temporary tools build. Installed the full
ch. 8 ncurses (6.6) with ABI-5 compatibility libraries before procps.

### A glob ate a tarball
The ch. 5 cleanup step `rm -rf ncurses-*` matched `ncurses-6.6-20260926.tgz` as
well as the extracted directory, deleting the tarball. Re-downloaded. Cleanup
globs must be anchored: `rm -rf ncurses-6.6-20260926` (exact name), never
`ncurses-*`.

### Verification (1b complete)
```
/sbin/init                — SysV init, 65 KB
/etc/init.d               — 21 boot scripts (checkfs, cleanfs, modules, udev, …)
/etc/rc.d/rc{0..6}.d      — runlevel symlinks
mke2fs 1.47.3, ip 6.16.0, ps 4.0.5, modprobe 34.2
```

---

## Phase 1c–1d — Kernel, GRUB, first boot

Built OpenSSL 3.5.2 (needed by later packages anyway), Linux 6.16.1 with a
Wylde-tuned config, and GRUB 2.12. First boot reached the login prompt.

### objtool: `gelf.h: No such file or directory`
The kernel's objtool needs libelf, which does not exist yet at that point.
Built elfutils' libelf (ch. 8) first, then rebuilt the kernel.

### `certs/extract-cert.c: openssl/bio.h: No such file or directory`
The kernel's `extract-cert` host tool needs libcrypto. Rather than trimming the
cert options out of the config, OpenSSL was built — curl, git and openssh all
need it in phase 2 anyway.

### kernel.org no longer publishes reference configs
`https://cdn.kernel.org/pub/linux/kernel/v6.x/config-6.16.1` → 404, and the
directory listing has no `config-*` files at all. The book starts from that
file; Wylde uses `make x86_64_defconfig` plus the `scripts/config` tuning pass
in `build/05-kernel.sh`.

Surprise worth knowing: in 6.16, `x86_64_defconfig` builds almost everything
**built-in** (13 modules total). So the "lean" kernel is 11 MB with no module
dependencies at boot — smaller overall than a modular kernel plus 200 MB of
modules.

### Two globs ate two tarballs
`rm -rf ncurses-*` deleted `ncurses-6.6-20260926.tgz`, and `rm -rf grub-2.12*`
deleted `grub-2.12.tar.xz`. Cleanup must use exact directory names.

### `grub-mkconfig_lib` was binary garbage in the image
A QEMU boot test had been killed mid-write with the image attached read-write,
so the ext4 journal was left incomplete and files came out corrupt. Two lessons,
both now enforced:
- `scripts/qemu-boot.sh` passes `-snapshot`, so the base image is never written.
- If a test is interrupted, `e2fsck` the image before trusting it.

### `root=/dev/loop7p2` → `VFS: Cannot open root device`
`grub-mkconfig` derives `root=` from the *host* loop device, which changes
between runs. The image script now rewrites it to `/dev/sda2`, the name the
guest actually sees on the QEMU IDE disk.

### `INIT: No inittab file found` → `Enter runlevel:`
`/etc/inittab` is created in the book's chapter 9, which had been skipped. It
lives in `build/07-shadow.sh`, with one addition: an `agetty` on `ttyS0` at
115200 so the system is reachable over serial. Root gets an empty password for
the first boot only.

### `mount: /run: can't find in /etc/fstab`
The first `fstab` only had `/` and swap. SysV's `mountvirtfs` calls plain
`mount /run`, `/proc`, `/sys`, `/dev/pts` and `/dev/shm`, so all of them need
fstab entries. Now generated in full by `scripts/make-disk-image.sh`.

### shadow: `readpassphrase() is missing`
The book's flags `--without-libbsd` (use the bundled copy) and
`make exec_prefix=/usr install` are both required; plain `make install` puts
binaries under the wrong prefix.

### `Login incorrect` at the serial prompt
`/etc/shadow` had been overwritten with a placeholder line (`root:x:`) after
`pwconv` had already produced a valid one. A valid passwordless root entry is
`root::19000:0:99999:7:::` — the account is only passwordless for the very
first boot, and the release checklist must not ship that.

### Two boot scripts failed: no `/bin/udevadm`, syslog daemon missing
`udev_retry` and `sysklogd` come from packages the boot-critical subset had
skipped. Both are now built (`build/08-udev-sysklogd.sh`): udev from the
`systemd-257.8` tarball, and `sysklogd-2.7.2` with `/etc/syslog.conf` in
`secure_mode 2` — no network syslog listener.

### `python3 is missing modules: jinja2` (meson, udev)
The chroot Python has no pip and no DNS, so jinja2 (pure Python) is copied in
from the host's `dist-packages`. Same trick is needed for any later meson
package that imports jinja2.

## First boot

```
Linux version 6.16.1 (gcc (GCC) 15.2.0, GNU ld (GNU Binutils) 2.45)
INIT: version 3.14 booting
INIT: Entering runlevel: 3
Wylde Linux 0.1-alpha
Kernel 6.16.1 on x86_64 (ttyS0)
wylde login: root
-bash-5.3#
```

Verified inside the guest: kernel identity, `/etc/issue`, root filesystem
listing, `gcc` compiling and running a binary, disk usage, memory, loopback
networking, mount table, running processes, runlevel-3 boot scripts. The image
boots under QEMU with `-snapshot`, so the image on disk is never touched by
tests.





---

## Phase 2b/2e — the package manager used on itself

Porting apps with `wld` inside the running target system (not on the host)
found real bugs in both the manager and the ports.

### `wld`: no downloader on day one
The first port could not fetch its source: a distro built from scratch has no
`curl` and no `wget` when `wld` starts. `wld` now tries `curl`, then `wget`, and
sets `SSL_CERT_FILE`/`CURL_CA_BUNDLE` to `/etc/ssl/certs/ca-certificates.crt`
explicitly, because both tools look in their own compiled-in paths.

### `wget`: rc=5, "cannot verify github.com's certificate"
Same root cause from the other side: no CA bundle in the chroot. Bootstrapped by
copying the host's bundle into `/etc/ssl/certs/`.

### Cache files collided
Sources were cached under their URL's last path component, so any two ports with
a `3.4.1.tar.gz` would clobber each other, and a failed download left a
truncated tarball that unpacked forever after. Cached names are now
`<package>-<last component>`, and a mismatched checksum aborts the build.

### `sudo --with-passwd does not take an argument`
It is a boolean flag (use shadow's `passwd`). `--with-group` likewise.

### rsync needed xxhash, lz4 and libidn2
rsync 3.5.1 aborts unless each is found or explicitly disabled. Ported xxhash
0.8.4 and lz4 1.10.0 (both small and useful), disabled IDN (which would pull in
libunistring).

### git 2.55+ needs a Rust toolchain
`make` stops with `CARGO target/release/libgitcore.a` — from 2.55 on, git builds
a Rust core. Wylde does not carry cargo in the base system, so it tracks 2.54.0,
the last C-only release. Documented in the Pkgfile.

### git installed 2.9 GB, now 38 MB
Two separate problems, both real bugs in `wld`:

1. git installs ~180 byte-identical copies of one binary. The port now collapses
   them into hardlinks after staging.
2. `wld install` used `fs::copy()` per path, which *broke* those hardlinks, and
   `total_size` counted every path separately, reporting 2.9 GiB of files that
   were never on disk together. Fixed both: install now maps staged inodes to
   one destination plus hardlinks, and size accounting counts each inode once.

Result: `git-core` went from 614 MB on disk to 24 MB. For a project whose first
principle is "not a single byte more", a package manager that copies 180 times
what it needs to link once is not acceptable.

### Boot-time bug found by the new init
`dhcpcd -b` forks into the background, so init saw it exit, respawned it six
times, then gave up — leaving the system with no network and no explanation
beyond one line. `dhcpcd -B` keeps it in the foreground with a pid init owns.
Hostname was `(none)` at the login prompt until a one-shot `hostname` service
was added.

### Iteration cost
The QEMU test harness originally waited on prompt regexes and spent 90 s per
check on timeouts. It now appends a unique sentinel to each command and matches
it line-anchored (`\r?$`): all 21 checks finish in under a second, and a full
"sync + boot + verify" cycle is about two minutes instead of ten.

### neovim: deferred, and why
`neovim` (roadmap 2e) turned into a dependency chain — cmake, lua 5.1 (for its
code generation), libuv, then luv, which vendors LuaJIT and fails its own
architecture probe (`deps/luajit.cmake` compiles a test including `lj_arch.h`
before that include path exists). Each fix is upstream-specific, and after luv
neovim still wants utf8proc, libtermkey, msgpack and tree-sitter grammars.

Rather than spend the effort there, Wylde installs the three ports that are
useful on their own — **cmake 4.4.3**, **lua 5.1.5**, **libuv 1.53.0** — and
defers the editor to phase 4, where a graphical release wants one anyway. Broken
recipes are not committed: `ports/` only holds ports that build.

### lua 5.1.5 needs the old dialect
```
luaconf.h:275:10: fatal error: readline/readline.h: No such file or directory
```
Two fixes: build the `posix` target instead of `linux` (no readline dependency
until readtext is ported), and force `MYCFLAGS="-O2 -std=gnu89 -fPIC"` — code
from 2011 predates the C99 implicit-declaration rules that gcc 14 turned into
errors.
