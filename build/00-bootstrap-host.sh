#!/bin/bash
# Wylde — host bootstrap
#
# Everything a clean machine needs before build/01-toolchain.sh can run:
#   - the lfs build user and its environment
#   - /mnt/lfs with the minimal layout
#   - the LFS 12.4 source tarballs, verified against the official md5sums
#
# Idempotent: safe to run on a machine that is already half-built.
set -e

LFS=${LFS:-/mnt/lfs}
LFS_VER=${LFS_VER:-12.4}
SOURCES=$LFS/sources
STATE=/var/lib/wylde-bootstrap

log() { echo "[bootstrap] $*"; }
die() { echo "[bootstrap] fatal: $*" >&2; exit 1; }

[ "$(id -u)" = 0 ] || die "must run as root"
log "$(uname -srm), $(awk -F: '/^VERSION_ID/{print $2}' /etc/os-release 2>/dev/null | tr -d '\"')"

# ---------------------------------------------------------------- build user

if ! id lfs >/dev/null 2>&1; then
    log "creating the lfs user"
    groupadd lfs 2>/dev/null || true
    useradd -s /bin/bash -g lfs -m -k /dev/null lfs
fi

log "writing the lfs login environment"
cat > /home/lfs/.bash_profile << 'PROFILE'
exec env -i HOME=/home/lfs TERM=$TERM PS1='\u:\w\$ ' \
  LFS=/mnt/lfs \
  LC_ALL=POSIX \
  LFS_TGT=$(uname -m)-lfs-linux-gnu \
  PATH=/mnt/lfs/tools/bin:/usr/bin \
  CONFIG_SITE=/mnt/lfs/usr/share/config.site \
  /bin/bash
PROFILE
cat > /home/lfs/.bashrc << 'BASHRC'
set +h
umask 022
LFS=/mnt/lfs
LC_ALL=POSIX
LFS_TGT=$(uname -m)-lfs-linux-gnu
PATH=/usr/bin
if [ ! -L /bin ]; then PATH=/bin:$PATH; fi
PATH=$LFS/tools/bin:$PATH
CONFIG_SITE=$LFS/usr/share/config.site
export LFS LC_ALL LFS_TGT PATH CONFIG_SITE
BASHRC
chown lfs:lfs /home/lfs/.bash_profile /home/lfs/.bashrc

# host requirement from the book: /bin/sh must be bash, not dash
if [ ! "$(readlink -f /bin/sh)" = "$(readlink -f /bin/bash)" ]; then
    log "pointing /bin/sh at bash (LFS requirement)"
    ln -sf bash /bin/sh
fi

# -------------------------------------------------------------------- layout

log "creating $LFS"
mkdir -pv "$LFS"/{etc,var} "$LFS/usr"/{bin,lib,sbin} "$LFS/tools" "$SOURCES"
for i in bin lib sbin; do
    [ -L "$LFS/$i" ] || ln -sv usr/$i "$LFS/$i"
done
case $(uname -m) in
    x86_64) mkdir -pv "$LFS/lib64" ;;
esac
chown -R lfs:lfs "$LFS"

# ------------------------------------------------------------------- sources

mkdir -p "$STATE"
WGET_LIST=$STATE/wget-list
MD5SUMS=$STATE/md5sums

if [ ! -s "$WGET_LIST" ]; then
    log "fetching the LFS $LFS_VER source list"
    curl -fsSL "https://www.linuxfromscratch.org/lfs/downloads/$LFS_VER/wget-list" -o "$WGET_LIST"
    curl -fsSL "https://www.linuxfromscratch.org/lfs/downloads/$LFS_VER/md5sums" -o "$MD5SUMS"
fi
[ -s "$WGET_LIST" ] || die "could not fetch the source list"
[ -s "$MD5SUMS" ] || die "could not fetch md5sums"

total=$(grep -c . "$WGET_LIST")
have=$(find "$SOURCES" -type f \( -name '*.tar.*' -o -name '*.patch' -o -name '*.diff' \) | wc -l)
log "sources: $have of $total already present"

if [ "$have" -lt "$total" ]; then
    log "downloading the missing sources (this takes a while)"
    missing=$STATE/wget-missing
    : > "$missing"
    while read -r url; do
        [ -n "$url" ] || continue
        name=${url##*/}
        [ -f "$SOURCES/$name" ] || echo "$url" >> "$missing"
    done < "$WGET_LIST"
    log "$(grep -c . "$missing") files to fetch"
    # four parallel streams: the mirrors throttle a single connection
    split -n l/4 "$missing" "$STATE/part-"
    for part in "$STATE"/part-*; do
        wget -q --input-file="$part" --directory-prefix="$SOURCES" --continue &
    done
    wait
fi

log "verifying checksums"
( cd "$SOURCES" && md5sum -c "$MD5SUMS" --quiet ) || die "source verification failed"
chown -R lfs:lfs "$SOURCES"

log "host is ready: build/01-toolchain.sh can run now"
