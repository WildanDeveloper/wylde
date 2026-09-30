# wld — Wylde package manager

A package manager for a distribution with no base distro to inherit package
management from. Written in Rust, statically linked against musl, no runtime
dependencies, zero crates — everything it needs is in `src/`.

```
wld build <port>      Build a port (no install)
wld install <port>    Build and install
wld remove <name>     Remove a package and its files
wld list              Installed packages
wld info <name>       Details about a package
wld search <term>     Search ports
wld ports             Available ports
wld tree              Port tree
wld doctor            Report on the local installation
```

## The port format

A port is a directory with one file, `Pkgfile`. Plain Bash, no DSL:

```bash
name=hello
version=2.12.3
description="GNU Hello: the traditional system administration test program"
license=GPL-3.0-or-later
source=https://ftp.gnu.org/gnu/hello/hello-$version.tar.gz
checksum(https://ftp.gnu.org/gnu/hello/hello-$version.tar.gz)=0d5f60154382f...

build() {
    ./configure --prefix=/usr
    make
    make DESTDIR="$PKG" install
}
```

Recognised keys: `name`, `version`, `description`, `license`, `source` (one or
more), `checksum(<url>)`, `depends`. Anything else is ignored, so a Pkgfile can
carry comments and local variables without confusing `wld`.

`build()` runs with these variables set:

| Variable | Meaning |
|----------|---------|
| `$PKG` | staging root: install here, nothing lands in the real filesystem |
| `$DESTDIR` | the install prefix the staging tree will be copied into |
| `$SRCDIR` | the unpacked source directory |

## How install and remove work

1. Sources are downloaded once into `$WLD_ROOT/sources`, cached.
2. Every source is sha256-verified against the Pkgfile. A mismatch aborts.
3. Sources are unpacked into `$WLD_ROOT/build/<name>/`.
4. `build()` runs there. If it fails, nothing has been installed.
5. The staged tree is copied into `$WLD_DESTDIR` (default `/`).
6. The list of installed paths — absolute — is written to
   `$WLD_ROOT/db/<name>-<version>.files`, with metadata in the matching `.info`.

`wld remove` reads that file list and deletes exactly those paths. No
dependency tracking, no reverse-index database: a flat file per package is
readable, greppable, and can be repaired by hand. That is deliberate — principle
3 of the project: nothing runs behind your back, including the package manager.

## Build

```bash
cargo build --release                              # native
cargo build --release --target x86_64-unknown-linux-musl   # static, for the ISO
cargo test
```

Release profile: `opt-level="z"`, LTO, one codegen unit, `panic="abort"`,
stripped. The result is ~545 KB with nothing to install alongside it.

## Environment

| Variable | Default | Meaning |
|----------|---------|---------|
| `WLD_ROOT` | `/var/lib/wld` | database, sources cache, build scratch |
| `WLD_DESTDIR` | `/` | where `wld install` puts files |
