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

# chown only what lives on the target filesystem. A rebuild host may have
# /proc, /sys and /dev bind-mounted under $LFS, and chown -R would then walk
# /proc/sys/net and print thousands of "operation not permitted" lines.
own_tree() {
    find "$1" -xdev \
        \( -path "$1/proc" -o -path "$1/sys" -o -path "$1/dev" -o -path "$1/run" \) -prune \
        -o -exec chown lfs:lfs {} + 2>/dev/null || true
}

[ "$(id -u)" = 0 ] || die "must run as root"

# A pin file whose last line lacks a newline loses that entry to every reader
# that does `while read`. Checked once here so the mistake cannot be committed.
for pin in "$PINNED/wget-list" "$PINNED/md5sums" "$PINNED/mirrors" "$PINNED/extra.list"; do
    [ -s "$pin" ] || continue
    if [ -n "$(tail -c1 "$pin")" ]; then
        die "$pin does not end with a newline — its last entry would be ignored"
    fi
done
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
own_tree "$LFS"

# ------------------------------------------------------------------- sources

mkdir -p "$STATE"
WGET_LIST=$STATE/wget-list
MD5SUMS=$STATE/md5sums
MIRRORS=$STATE/mirrors

# The pinned list in sources/ is what this system was actually built from and is
# the one the recipes expect: upstream republishes the LFS source list when a
# package is revised, which would silently change what CI compiles. Pin first,
# fall back to upstream only when the repo copy is missing.
PINNED=${PINNED_SOURCES:-$(cd "$(dirname "$0")/.." && pwd)/sources}

if [ -s "$PINNED/wget-list" ] && [ -s "$PINNED/md5sums" ]; then
    log "using the pinned source list from $PINNED"
    cp "$PINNED/wget-list" "$WGET_LIST"
    cp "$PINNED/md5sums" "$MD5SUMS"
else
    log "fetching the LFS $LFS_VER source list from upstream"
    curl -fsSL "https://www.linuxfromscratch.org/lfs/downloads/$LFS_VER/wget-list" -o "$WGET_LIST"
    curl -fsSL "https://www.linuxfromscratch.org/lfs/downloads/$LFS_VER/md5sums" -o "$MD5SUMS"
fi

# Sources the book does not ship (see sources/extra.list). Pinned by sha256 and
# fetched here, because a build script that assumes a tarball will otherwise
# fail on every clean machine.
EXTRA=$STATE/extra.list
if [ -s "$PINNED/extra.list" ]; then
    cp "$PINNED/extra.list" "$EXTRA"
else
    : > "$EXTRA"
fi

# Extra download locations for files whose home host is flaky. Same bytes, same
# checksum: a download is only accepted once its md5 matches sources/md5sums.
[ -s "$PINNED/mirrors" ] && cp "$PINNED/mirrors" "$MIRRORS" || : > "$MIRRORS"
[ -s "$WGET_LIST" ] || die "could not fetch the source list"
[ -s "$MD5SUMS" ] || die "could not fetch md5sums"

total=$(grep -c . "$WGET_LIST")

wanted() {
    # the basenames the book expects to find in the sources directory
    sed 's/#.*//' "$WGET_LIST" | awk 'NF {n=$0; sub(/.*\//,"",n); print n}' | sort -u
}

# md5 of a file that is present, or an empty string when it is absent or wrong.
# Existence is not enough: a truncated download would otherwise be accepted
# forever, and no retry could ever replace it.
have_md5() {
    [ -s "$SOURCES/$1" ] || return 0
    md5sum "$SOURCES/$1" 2>/dev/null | cut -d" " -f1
}

want_md5() {
    sed 's/^[ *]*//' "$MD5SUMS" | awk -v f="$1" '$2 == f {print $1; exit}'
}

have_count() {
    local found=0 name expected actual
    while read -r name; do
        expected=$(want_md5 "$name")
        actual=$(have_md5 "$name")
        [ -n "$expected" ] || { [ -n "$actual" ] && found=$((found + 1)); continue; }
        [ "$actual" = "$expected" ] && found=$((found + 1))
    done < <(wanted)
    echo "$found"
}

log "sources: $(have_count) of $(wanted | wc -l) already present"

# Downloads go through curl one file at a time with retries: mirrors reject or
# truncate concurrent connections, and a silently half-fetched tarball only shows
# up much later as a checksum error nobody can explain.
for pass in 1 2 3; do
    todo=$STATE/wget-todo.$pass
    : > "$todo"
    while read -r name; do
        expected=$(want_md5 "$name")
        actual=$(have_md5 "$name")
        if [ -n "$expected" ] && [ "$actual" != "$expected" ]; then
            # wrong bytes on disk: throw them away so the retry can work
            rm -f "$SOURCES/$name"
        fi
        [ -s "$SOURCES/$name" ] || echo "$name" >> "$todo"
    done < <(wanted)

    count=$(grep -c . "$todo" || true)
    [ "$count" -eq 0 ] && break
    log "pass $pass: fetching $count file(s)"

    # four at a time: enough to be quick, few enough to stay polite
    fetch_one() {
        local name=$1 expected url ok=1
        expected=$(want_md5 "$name")

        # the pinned url first, then any mirror listed for this file. A bash
        # array rather than a pipeline: a subshell cannot report success back.
        local -a urls=()
        url=$(grep -E "/${name}\$" "$WGET_LIST" | head -1)
        [ -n "$url" ] && urls+=("$url")
        if [ -s "$MIRRORS" ]; then
            while read -r mfile murl || [ -n "${mfile:-}" ]; do
                [ "$mfile" = "$name" ] && urls+=("$murl")
            done < "$MIRRORS"
        fi

        for url in "${urls[@]}"; do
            if ! curl -fsSL --retry 5 --retry-delay 3 --retry-all-errors \
                    -o "$SOURCES/$name.part" "$url" 2>/dev/null; then
                echo "  unreachable: $url" >&2
                rm -f "$SOURCES/$name.part"
                continue
            fi
            if [ -n "$expected" ] && [ "$(md5sum "$SOURCES/$name.part" | cut -d" " -f1)" != "$expected" ]; then
                echo "  wrong bytes from $url, trying the next source" >&2
                rm -f "$SOURCES/$name.part"
                continue
            fi
            mv "$SOURCES/$name.part" "$SOURCES/$name"
            echo "  got $name"
            ok=0
            break
        done

        [ "$ok" -eq 0 ] || { echo "  failed: $name" >&2; return 1; }
    }
    export -f fetch_one
    export SOURCES WGET_LIST
    xargs -a "$todo" -d '\n' -P 4 -I{} bash -c 'fetch_one "$@"' _ {} || true
done

# ---------------------------------------------------------------- extra files

if [ -s "$EXTRA" ]; then
    # url sha256 [local-name]: the local name is pinned too, because upstream
    # archive names change (v10.5.2.tar.gz is not a stable thing to build on)
    while read -r url expected localname || [ -n "${url:-}" ]; do
        case "$url" in \#*|"") continue ;; esac
        name=${localname:-${url##*/}}
        actual=""
        [ -s "$SOURCES/$name" ] && actual=$(sha256sum "$SOURCES/$name" | cut -d" " -f1)
        if [ "$actual" != "$expected" ]; then
            [ -n "$actual" ] && rm -f "$SOURCES/$name"
            log "fetching $name"
            if curl -fsSL --retry 5 --retry-delay 3 --retry-all-errors \
                    -o "$SOURCES/$name" "$url"; then
                actual=$(sha256sum "$SOURCES/$name" | cut -d" " -f1)
            fi
        fi
        if [ "$actual" != "$expected" ]; then
            die "$name could not be fetched or its sha256 does not match $expected"
        fi
        log "  $name verified"
    done < "$EXTRA"
fi

log "verifying checksums"
missing_md5=$STATE/missing-md5
: > "$missing_md5"
while read -r sum name; do
    case "$name" in \#*) continue ;; esac
    [ -s "$SOURCES/$name" ] || { echo "$name" >> "$missing_md5"; continue; }
    actual=$(md5sum "$SOURCES/$name" | cut -d' ' -f1)
    [ "$actual" = "$sum" ] || echo "$name (checksum mismatch)" >> "$missing_md5"
done < <(sed 's/^[ *]*//' "$MD5SUMS" | grep -E '^[0-9a-f]{32} ')

if [ -s "$missing_md5" ]; then
    log "sources that could not be fetched or verified:"
    sed 's/^/  /' "$missing_md5" >&2
    die "the source set is incomplete — retry, or fetch the files above by hand into $SOURCES"
fi

own_tree "$SOURCES"

log "host is ready: build/01-toolchain.sh can run now"
