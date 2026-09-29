#!/bin/bash
# Wylde — boot-critical subset of LFS 12.4 ch. 8 (inside the chroot, as root).
# Order matters: libraries first, then the packages that need them.
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

# ldconfig config is created in ch. 9 of the book, but the shared library
# installs below already need it.
stage ldconfig <<'EOF'
set -e
mkdir -pv /etc/ld.so.conf.d
cat > /etc/ld.so.conf << "EOF"
# Begin /etc/ld.so.conf
/usr/local/lib
/usr/lib
# End /etc/ld.so.conf
EOF
EOF

stage bzip2 <<'EOF'
set -e
cd /sources
rm -rf bzip2-1.0.8
tar -xf bzip2-1.0.8.tar.gz
cd bzip2-1.0.8
patch -Np1 -i ../bzip2-1.0.8-install_docs-1.patch
sed -i 's@\(ln -s -f \)$(PREFIX)/bin/@\1@' Makefile
sed -i "s@(PREFIX)/man@(PREFIX)/share/man@g" Makefile
make -f Makefile-libbz2_so
make clean
make
make PREFIX=/usr install
cp -av libbz2.so.* /usr/lib
ln -sv libbz2.so.1.0.8 /usr/lib/libbz2.so
cp -v bzip2-shared /usr/bin/bzip2
for i in /usr/bin/bzcat /usr/bin/bunzip2; do ln -sfv bzip2 $i; done
rm -fv /usr/lib/libbz2.a
ldconfig
EOF

stage zlib <<'EOF'
set -e
cd /sources
rm -rf zlib-1.3.1
tar -xf zlib-1.3.1.tar.gz
cd zlib-1.3.1
./configure --prefix=/usr
make
make install
rm -fv /usr/lib/libz.a
ldconfig
EOF

# Python again: the ch. 7 build has no zlib/ctypes modules, which breaks meson.
stage python-full <<'EOF'
set -e
cd /sources
rm -rf Python-3.13.7
tar -xf Python-3.13.7.tar.xz
cd Python-3.13.7
./configure --prefix=/usr       \
            --enable-shared     \
            --without-ensurepip \
            --without-static-libpython
make
make install
python3 -c 'import zlib; print("zlib module OK")'
EOF

stage zstd <<'EOF'
set -e
cd /sources
rm -rf zstd-1.5.7
tar -xf zstd-1.5.7.tar.gz
cd zstd-1.5.7
make prefix=/usr
make prefix=/usr install
rm -fv /usr/lib/libzstd.a
ldconfig
EOF

stage pkgconf <<'EOF'
set -e
cd /sources
rm -rf pkgconf-2.5.1
tar -xf pkgconf-2.5.1.tar.xz
cd pkgconf-2.5.1
./configure --prefix=/usr    \
            --disable-static \
            --docdir=/usr/share/doc/pkgconf-2.5.1
make
make install
ln -sv pkgconf /usr/bin/pkg-config
EOF

stage ninja <<'EOF'
set -e
cd /sources
rm -rf ninja-1.13.1
tar -xf ninja-1.13.1.tar.gz
cd ninja-1.13.1
sed -i '/int Guess/a \
int   j = 0;\
char* jobs = getenv( "NINJAJOBS" );\
if ( jobs != NULL ) j = atoi( jobs );\
if ( j > 0 ) return j;\
' src/ninja.cc
python3 configure.py --bootstrap
install -vm755 ninja /usr/bin/
EOF

# meson: the book installs it with pip3, but the chroot Python has no pip
# (--without-ensurepip). Install from the source tree instead.
stage meson <<'EOF'
set -e
cd /sources
rm -rf meson-1.8.3
tar -xf meson-1.8.3.tar.gz
install -d /usr/lib/meson
cp -a meson-1.8.3/. /usr/lib/meson/
cat > /usr/bin/meson << "WRAP"
#!/usr/bin/env python3
import sys
sys.path.insert(0, "/usr/lib/meson")
from mesonbuild import mesonmain
sys.exit(mesonmain.main())
WRAP
chmod 755 /usr/bin/meson
install -vDm644 /usr/lib/meson/data/shell-completions/bash/meson \
  /usr/share/bash-completion/completions/meson
meson --version
EOF

stage libelf <<'EOF'
set -e
cd /sources
rm -rf elfutils-0.193
tar -xf elfutils-0.193.tar.bz2
cd elfutils-0.193
./configure --prefix=/usr        \
            --disable-debuginfod \
            --enable-libdebuginfod=dummy
make
make -C libelf install
install -vm644 config/libelf.pc /usr/lib/pkgconfig
rm -fv /usr/lib/libelf.a
ldconfig
EOF

stage bc <<'EOF'
set -e
cd /sources
rm -rf bc-7.0.3
tar -xf bc-7.0.3.tar.xz
cd bc-7.0.3
CC="gcc -std=c99" ./configure --prefix=/usr -G -O3 -r
make
make install
EOF

stage kmod <<'EOF'
set -e
cd /sources
rm -rf kmod-34.2
tar -xf kmod-34.2.tar.xz
cd kmod-34.2
mkdir -p build
cd       build
# -D openssl=disabled: Wylde does not sign kernel modules
meson setup --prefix=/usr .. --buildtype=release -D manpages=false -D openssl=disabled
ninja
ninja install
EOF

stage bison <<'EOF'
set -e
cd /sources
rm -rf bison-3.8.2
tar -xf bison-3.8.2.tar.xz
cd bison-3.8.2
./configure --prefix=/usr --docdir=/usr/share/doc/bison-3.8.2
make
make install
EOF

stage flex <<'EOF'
set -e
cd /sources
rm -rf flex-2.6.4
tar -xf flex-2.6.4.tar.gz
cd flex-2.6.4
./configure --prefix=/usr \
            --docdir=/usr/share/doc/flex-2.6.4 \
            --disable-static
make
make install
ln -sv flex   /usr/bin/lex
ln -sv flex.1 /usr/share/man/man1/lex.1
EOF

stage openssl <<'EOF'
set -e
cd /sources
rm -rf openssl-3.5.2
tar -xf openssl-3.5.2.tar.gz
cd openssl-3.5.2
./config --prefix=/usr         \
         --openssldir=/etc/ssl \
         --libdir=lib          \
         shared                \
         zlib-dynamic
make
sed -i '/INSTALL_LIBS/s/libcrypto.a libssl.a//' Makefile
make MANSUFFIX=ssl install
mv -v /usr/share/doc/openssl /usr/share/doc/openssl-3.5.2
cp -vfr doc/* /usr/share/doc/openssl-3.5.2
ldconfig
EOF

stage ncurses <<'EOF'
set -e
cd /sources
rm -rf ncurses-6.6-20260926
tar -xf ncurses-6.6-20260926.tgz
cd ncurses-6.6-20260926
# DEVIATION: the book pins ncurses-6.5-20250809.tgz, which no longer exists on
# any mirror. This is the current upstream snapshot; no patches are involved.
./configure --prefix=/usr           \
            --mandir=/usr/share/man \
            --with-shared           \
            --without-debug         \
            --without-normal        \
            --with-cxx-shared       \
            --enable-pc-files       \
            --with-pkg-config-libdir=/usr/lib/pkgconfig
make
make DESTDIR=$PWD/dest install
install -vm755 dest/usr/lib/libncursesw.so.6.6 /usr/lib
rm -v  dest/usr/lib/libncursesw.so.6.6
sed -e 's/^#if.*XOPEN.*$/#if 1/' -i dest/usr/include/curses.h
cp -av dest/* /
for lib in ncurses form panel menu ; do
  ln -sfv lib${lib}w.so /usr/lib/lib${lib}.so
  ln -sfv ${lib}w.pc    /usr/lib/pkgconfig/${lib}.pc
done
ln -sfv libncursesw.so /usr/lib/libcurses.so
cp -v -R doc -T /usr/share/doc/ncurses-6.6-20260926
make distclean
./configure --prefix=/usr         \
            --with-shared         \
            --without-normal      \
            --without-debug       \
            --without-cxx-binding \
            --with-abi-version=5
make sources libs
cp -av lib/lib*.so.5* /usr/lib
ldconfig
EOF

stage procps <<'EOF'
set -e
cd /sources
rm -rf procps-ng-4.0.5
tar -xf procps-ng-4.0.5.tar.xz
cd procps-ng-4.0.5
./configure --prefix=/usr \
            --docdir=/usr/share/doc/procps-ng-4.0.5 \
            --disable-static \
            --disable-kill \
            --enable-watch8bit
make
# 'make check' needs su, which the temporary util-linux does not provide
make install
EOF

stage iproute2 <<'EOF'
set -e
cd /sources
rm -rf iproute2-6.16.0
tar -xf iproute2-6.16.0.tar.xz
cd iproute2-6.16.0
sed -i /ARPD/d Makefile
rm -fv man/man8/arpd.8
make NETNS_RUN_DIR=/run/netns
make SBINDIR=/usr/sbin install
install -vDm644 COPYING README* -t /usr/share/doc/iproute2-6.16.0
EOF

stage e2fsprogs <<'EOF'
set -e
cd /sources
rm -rf e2fsprogs-1.47.3
tar -xf e2fsprogs-1.47.3.tar.gz
cd e2fsprogs-1.47.3
mkdir -v build
cd       build
../configure --prefix=/usr       \
             --sysconfdir=/etc   \
             --enable-elf-shlibs \
             --disable-libblkid  \
             --disable-libuuid   \
             --disable-uuidd     \
             --disable-fsck
make
make check || echo "WARNING: e2fsprogs make check reported failures (non-fatal)"
make install
rm -fv /usr/lib/{libcom_err,libe2p,libext2fs,libss}.a
gunzip -v /usr/share/info/libext2fs.info.gz
install-info --dir-file=/usr/share/info/dir /usr/share/info/libext2fs.info
makeinfo -o      doc/com_err.info ../lib/et/com_err.texinfo
install -v -m644 doc/com_err.info /usr/share/info
install-info --dir-file=/usr/share/info/dir /usr/share/info/com_err.info
sed 's/metadata_csum_seed,//' -i /etc/mke2fs.conf
EOF

stage sysvinit <<'EOF'
set -e
cd /sources
rm -rf sysvinit-3.14
tar -xf sysvinit-3.14.tar.xz
cd sysvinit-3.14
patch -Np1 -i ../sysvinit-3.14-consolidated-1.patch
make
make install
cd /sources
rm -rf lfs-bootscripts-20250827
tar -xf lfs-bootscripts-20250827.tar.xz
cd lfs-bootscripts-20250827
make install
for f in /etc/rc.d/*; do
  ln -sf "../init.d/$(basename "$f")" "$f"
done
EOF

echo "[$(date +%H:%M:%S)] BOOTCRITICAL_DONE" >> "$LOGDIR/build.log"
