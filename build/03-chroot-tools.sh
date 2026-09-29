#!/bin/bash
# Wylde — LFS 12.4 ch. 7.6-7.11: temporary tools (inside the chroot, as root)
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
    exit 1
  fi
}

stage gettext <<'EOF'
set -e
cd /sources
rm -rf gettext-0.26
tar -xf gettext-0.26.tar.xz
cd gettext-0.26
./configure --disable-shared
make
cp -v gettext-tools/src/{msgfmt,msgmerge,xgettext} /usr/bin
EOF

stage bison <<'EOF'
set -e
cd /sources
rm -rf bison-3.8.2
tar -xf bison-3.8.2.tar.xz
cd bison-3.8.2
./configure --prefix=/usr \
            --docdir=/usr/share/doc/bison-3.8.2
make
make install
EOF

stage perl <<'EOF'
set -e
cd /sources
rm -rf perl-5.42.0
tar -xf perl-5.42.0.tar.xz
cd perl-5.42.0
sh Configure -des                                         \
    -D prefix=/usr                                        \
    -D vendorprefix=/usr                                  \
    -D useshrplib                                         \
    -D privlib=/usr/lib/perl5/5.42/core_perl               \
    -D archlib=/usr/lib/perl5/5.42/core_perl               \
    -D sitelib=/usr/lib/perl5/5.42/site_perl               \
    -D sitearch=/usr/lib/perl5/5.42/site_perl              \
    -D vendorlib=/usr/lib/perl5/5.42/vendor_perl           \
    -D vendorarch=/usr/lib/perl5/5.42/vendor_perl
make
make install
EOF

stage python <<'EOF'
set -e
cd /sources
rm -rf Python-3.13.7
tar -xf Python-3.13.7.tar.xz
cd Python-3.13.7
# NOTE: the ssl module and anything else needing OpenSSL/ctypes deps is skipped
# here and rebuilt in 04-bootcritical.sh once those libraries exist.
./configure --prefix=/usr       \
            --enable-shared     \
            --without-ensurepip \
            --without-static-libpython
make
make install
EOF

stage texinfo <<'EOF'
set -e
cd /sources
rm -rf texinfo-7.2
tar -xf texinfo-7.2.tar.xz
cd texinfo-7.2
./configure --prefix=/usr
make
make install
EOF

stage util-linux <<'EOF'
set -e
cd /sources
rm -rf util-linux-2.41.1
tar -xf util-linux-2.41.1.tar.xz
cd util-linux-2.41.1
mkdir -pv /var/lib/hwclock
./configure --libdir=/usr/lib     \
            --runstatedir=/run    \
            --disable-chfn-chsh   \
            --disable-login       \
            --disable-nologin     \
            --disable-su          \
            --disable-setpriv     \
            --disable-runuser     \
            --disable-pylibmount  \
            --disable-static      \
            --disable-liblastlog2 \
            --without-python      \
            ADJTIME_PATH=/var/lib/hwclock/adjtime \
            --docdir=/usr/share/doc/util-linux-2.41.1
make
make install
EOF

echo "[$(date +%H:%M:%S)] CHROOT_TOOLS_DONE" >> "$LOGDIR/build.log"
