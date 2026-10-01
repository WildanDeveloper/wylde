#!/bin/bash
# Wylde — autotools + GRUB 2.12 (roadmap 1e)
set -e
export LFS=/mnt/lfs
export LOGDIR=${LOGDIR:-/tmp/wylde-build}
mkdir -p "$LOGDIR"

stage() {
  echo "[$(date +%H:%M:%S)] START $1" >> "$LOGDIR/build.log"
  if chroot "$LFS" /usr/bin/env -i \
        HOME=/root TERM=dumb PS1='(wylde) #' \
        PATH=/usr/bin:/usr/sbin MAKEFLAGS="-j$(nproc)" TESTSUITEFLAGS="-j$(nproc)" \
        /bin/bash -s > "$LOGDIR/$1.log" 2>&1 <<INNER
$(cat)
INNER
  then
    echo "[$(date +%H:%M:%S)] DONE $1" >> "$LOGDIR/build.log"
  else
    echo "[$(date +%H:%M:%S)] FAIL $1 — see $LOGDIR/$1.log" >> "$LOGDIR/build.log"
    tail -n 25 "$LOGDIR/$1.log" >&2 || true
    exit 1
  fi
}

stage gperf <<'EOF'
set -e
cd /sources
rm -rf gperf-3.3
tar -xf gperf-3.3.tar.gz
cd gperf-3.3
./configure --prefix=/usr --docdir=/usr/share/doc/gperf-3.3
make
make install
EOF

stage libtool <<'EOF'
set -e
cd /sources
rm -rf libtool-2.5.4
tar -xf libtool-2.5.4.tar.xz
cd libtool-2.5.4
./configure --prefix=/usr
make
make install
rm -fv /usr/lib/libltdl.a
EOF

stage autoconf <<'EOF'
set -e
cd /sources
rm -rf autoconf-2.72
tar -xf autoconf-2.72.tar.xz
cd autoconf-2.72
./configure --prefix=/usr
make
make install
EOF

stage automake <<'EOF'
set -e
cd /sources
rm -rf automake-1.18.1
tar -xf automake-1.18.1.tar.xz
cd automake-1.18.1
./configure --prefix=/usr --docdir=/usr/share/doc/automake-1.18.1
make
make install
EOF

stage grub <<'EOF'
set -e
cd /sources
rm -rf grub-2.12
tar -xf grub-2.12.tar.xz
cd grub-2.12
unset {C,CPP,CXX,LD}FLAGS
echo depends bli part_gpt > grub-core/extra_deps.lst
./configure --prefix=/usr     \
            --sysconfdir=/etc \
            --disable-efiemu  \
            --disable-werror
make
make install
mv -v /etc/bash_completion.d/grub /usr/share/bash-completion/completions
EOF

echo "[$(date +%H:%M:%S)] GRUB_DONE" >> "$LOGDIR/build.log"
