# Wylde port spec — LFS ch.5 temporary tools and ch.6 system basics.
#
# Fields: category, name, version, source, description, license, build body
# (continuation lines start with a space). The generator computes sha256 from
# /mnt/lfs/sources, so checksums are always real.
#
# Every cross flag below is copied from LFS 12.4 — see build/01-toolchain.sh.

category=core name=bash version=5.3 source=https://ftpmirror.gnu.org/bash/bash-$version.tar.gz license=GPL-3.0-or-later description="GNU Bourne-again shell"
build=./configure --prefix=/usr \
                      --without-bash-malloc
     make
     make DESTDIR="$PKG" install
     ln -sv bash "$PKG/bin/sh"

category=core name=coreutils version=9.7 source=https://ftpmirror.gnu.org/coreutils/coreutils-$version.tar.xz license=GPL-3.0-or-later description="Basic file, shell and text utilities"
build=./configure --prefix=/usr \
                      --enable-install-program=hostname \
                      --enable-no-install-program=kill,uptime
     make
     make DESTDIR="$PKG" install
     mv -v "$PKG/usr/bin/chroot" "$PKG/usr/sbin"
     mkdir -pv "$PKG/usr/share/man/man8"
     mv -v "$PKG/usr/share/man/man1/chroot.1" "$PKG/usr/share/man/man8/chroot.8"
     sed -i 's/"1"/"8"/' "$PKG/usr/share/man/man8/chroot.8"

category=core name=diffutils version=3.12 source=https://ftpmirror.gnu.org/diffutils/diffutils-$version.tar.xz license=GPL-3.0-or-later description="Compare files and directories"
build=./configure --prefix=/usr gl_cv_func_strcasecmp_works=y
     make
     make DESTDIR="$PKG" install

category=core name=file version=5.46 source=https://github.com/file/file/archive/refs/tags/FILE5_46.tar.gz license=BSD-2-Clause description="Determine what type of data a file contains"
build=[ -f configure ] || autoreconf -fi
     mkdir build
     pushd build
       ../configure --disable-bzlib \
                    --disable-libseccomp \
                    --disable-xzlib \
                    --disable-zlib
       make
     popd
     ./configure --prefix=/usr
     make FILE_COMPILE=$(pwd)/build/src/file
     make DESTDIR="$PKG" install
     rm -fv "$PKG/usr/lib/libmagic.la"

category=core name=findutils version=4.10.0 source=https://ftp.gnu.org/gnu/findutils/findutils-$version.tar.xz license=GPL-3.0-or-later description="Walk directory trees and search for files"
build=./configure --prefix=/usr --localstatedir=/var/lib/locate --build=$(./build-aux/config.guess)
     make
     make DESTDIR="$PKG" install

category=core name=gawk version=5.3.2 source=https://ftp.gnu.org/gnu/gawk/gawk-$version.tar.xz license=GPL-3.0-or-later description="Pattern scanning and processing language, GNU awk"
build=sed -i 's/extras//' Makefile.in
     ./configure --prefix=/usr
     make
     make DESTDIR="$PKG" install

category=core name=grep version=3.12 source=https://ftp.gnu.org/gnu/grep/grep-$version.tar.xz license=GPL-3.0-or-later description="Print lines matching a pattern"
build=./configure --prefix=/usr
     make
     make DESTDIR="$PKG" install

category=core name=gzip version=1.14 source=https://ftp.gnu.org/gnu/gzip/gzip-$version.tar.gz license=GPL-3.0-or-later description="A GNU data compression program"
build=./configure --prefix=/usr
     make
     make DESTDIR="$PKG" install

category=core name=make version=4.4.1 source=https://ftp.gnu.org/gnu/make/make-$version.tar.gz license=GPL-3.0-or-later description="Remake targets automatically"
build=./configure --prefix=/usr
     make
     make DESTDIR="$PKG" install

category=core name=patch version=2.8 source=https://ftp.gnu.org/gnu/patch/patch-$version.tar.xz license=GPL-3.0-or-later description="Apply a diff to a file"
build=./configure --prefix=/usr
     make
     make DESTDIR="$PKG" install

category=core name=sed version=4.9 source=https://ftp.gnu.org/gnu/sed/sed-$version.tar.xz license=GPL-3.0-or-later description="GNU stream editor"
build=./configure --prefix=/usr
     make
     make DESTDIR="$PKG" install

category=core name=tar version=1.35 source=https://ftp.gnu.org/gnu/tar/tar-$version.tar.xz license=GPL-3.0-only description="Archiving utility"
build=./configure --prefix=/usr
     make
     make DESTDIR="$PKG" install

category=core name=xz version=5.8.1 source=https://github.com/tukaani-project/xz/releases/download/v$version/xz-$version.tar.xz license=0BSD description="Compressed file format .xz"
build=./configure --prefix=/usr \
                      --disable-static \
                      --docdir=/usr/share/doc/xz-5.8.1
     make
     make DESTDIR="$PKG" install
     rm -fv "$PKG/usr/lib/liblzma.la"

category=core name=m4 version=1.4.20 source=https://ftp.gnu.org/gnu/m4/m4-$version.tar.gz license=GPL-3.0-or-later description="GNU M4 macro processor"
build=./configure --prefix=/usr
     make
     make DESTDIR="$PKG" install

category=core name=ncurses version=6.6 source=https://invisible-island.net/archives/ncurses/current/ncurses-$version-20260926.tgz license=MIT description="Library for text-based user interfaces"
build=mkdir build
     pushd build
       ../configure --prefix="$PKG"/tools AWK=gawk
       make -C include
       make -C progs tic
       install progs/tic "$PKG"/tools/bin
     popd
     ./configure --prefix=/usr \
                      --mandir=/usr/share/man \
                      --with-manpage-format=normal \
                      --with-shared \
                      --without-normal \
                      --with-cxx-shared \
                      --without-debug \
                      --without-ada \
                      --disable-stripping \
                      AWK=gawk
     make
     make DESTDIR="$PKG" install
     ln -sv libncursesw.so "$PKG/usr/lib/libncurses.so
     sed -e 's/^#if.*XOPEN.*$/#if 1/' -i "$PKG/usr/include/curses.h