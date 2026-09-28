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
