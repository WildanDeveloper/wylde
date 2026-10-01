# Pinned sources

`wget-list` and `md5sums` are the exact source set this system is built from.
They are pinned in the repository on purpose.

The book fetches whatever is listed on
`linuxfromscratch.org/downloads/<version>/`. That list is **republished** every
time upstream revises a package: patch files are added, snapshot names change,
tarballs are replaced. A build that reads the live list is therefore not
reproducible — the same commit can compile different code on different days, and
a CI failure becomes impossible to explain.

`build/00-bootstrap-host.sh` uses these files first and only falls back to
upstream when they are absent. Upgrading a package is a deliberate act:

1. change the version in `ports.spec` (and in the build script that unpacks it),
2. fetch the new tarball once,
3. update the line in `sources/wget-list`,
4. replace the matching line in `sources/md5sums` with the md5 you just computed,
5. build it, and only then commit.

## Deviations from the book

| Package | Book | Here | Why |
| --- | --- | --- | --- |
| ncurses | `ncurses-6.5-20250809.tgz` from `invisible-mirror.net` | `ncurses-6.6.tar.gz` from `ftp.gnu.org` | the mirror no longer exists, and the dated snapshots upstream keeps under `archives/ncurses/current/` are deleted after a few weeks. A tagged release never disappears. |

Every other package is taken from the book's list unchanged, at the version the
book names.