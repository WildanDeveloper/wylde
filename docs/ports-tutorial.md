# Writing a Wylde port

A port is one directory with one file in it. The file is Bash, and `wld` reads
it for metadata and runs it for the build. No manifests in another format, no
template language, no generated files.

```
ports/
  core/
    htop/
      Pkgfile
  apps/
    git/
      Pkgfile
```

## The format

```bash
name=htop
version=3.4.1
description="Interactive process viewer"
license=GPL-2.0-or-later
source=https://github.com/htop-dev/htop/archive/refs/tags/$version.tar.gz
checksum(https://github.com/htop-dev/htop/archive/refs/tags/$version.tar.gz)=af9ec878...
patches=https://example.org/fix-1.patch
checksum(https://example.org/fix-1.patch)=9f1c2b...

build() {
    ./configure --prefix=/usr
    make
    make DESTDIR="$PKG" install
}
```

| Key | Meaning |
|---|---|
| `name` | package name, required |
| `version` | version string, required |
| `source` | one or more URLs; `$name` and `$version` expand |
| `checksum(<url>)` | sha256 of that URL, verified before the build |
| `patches` | patches downloaded and verified before the build |
| `depends` | free-form, for humans; `wld` does not resolve it yet |
| `description`, `license` | metadata |
| `build()` | the recipe, run verbatim |

Inside `build()`:

| Variable | Meaning |
|---|---|
| `$PKG` | staging root. Install here, not into `/` |
| `$DESTDIR` | where the staged tree will be copied afterwards |
| `$SRCDIR` | the unpacked source directory |
| `$PATCHDIR` | where downloaded patches live |

## Rules

1. **Never install into `/` directly.** Use `make DESTDIR="$PKG" install`. If a
   package's build insists on a hardcoded path, create the directory under
   `$PKG` first.
2. **Checksum every source and every patch.** A build that downloads something
   unverified is not reproducible. If a source has no checksum, say so with `-`
   and explain why in the port.
3. **No writes outside `$PKG`.** `wld remove` deletes exactly the files listed in
   the database, which are the files that were staged. Anything a build leaves
   behind outside `$PKG` becomes a file nobody tracks.
4. **Stay inside the staging root even for caches.** `CARGO_HOME`, `TMPDIR`,
   `XDG_CACHE_HOME` and friends should point into `$PKG` or `/tmp`.
5. **No `sudo`, no services, no network daemons** during a build. A build is not
   the place to start a process that outlives it.
6. **Deviations from the upstream instructions go in the recipe as comments**,
   next to the line they change, with the reason.

## Post-install tricks

Some packages install the same file many times (git ships ~180 copies of one
binary). Two tools are available:

```bash
# copy identical files into hardlinks: 750 MB becomes 4 MB
GITBIN="$PKG/usr/libexec/git-core/git"
SUM=$(sha256sum "$GITBIN" | cut -d' ' -f1)
SIZE=$(stat -c %s "$GITBIN")
for f in "$PKG"/usr/libexec/git-core/*; do
    [ -f "$f" ] || continue
    [ "$f" = "$GITBIN" ] && continue
    [ "$(stat -c %s "$f")" = "$SIZE" ] || continue
    [ "$(sha256sum "$f" | cut -d' ' -f1)" = "$SUM" ] || continue
    rm -f "$f" && ln "$GITBIN" "$f"
done
```

```bash
# strip the staged tree
find "$PKG" -name '*.so*' -exec strip --strip-unneeded {} + 2>/dev/null || true
```

## Testing a port

```bash
wld build <name>     # build and stage, install nothing
wld install <name>   # build, stage, install
wld info <name>      # what is installed, from which source
wld remove <name>    # delete exactly what was installed
```

`wld build` leaves the live system alone, so use it while iterating. `wld remove`
must return the system to exactly its previous state — if it does not, the
recipe wrote outside `$PKG`.

## Bulk changes

Ports that came from the LFS book are generated from `ports.spec`:

```bash
python3 tools/gen-ports.py ports.spec --fetch   # writes ports/*/Pkgfile
python3 tools/gen-ports.py ports.spec --check    # verify sources exist
```

The generator computes the sha256 of every source from the tarballs on disk, so
a generated port can never claim a checksum that does not match what it
downloads. Hand-written ports (kernel, toolchain, bootloader) are edited
directly.
