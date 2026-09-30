# Wylde port spec, part 2 — ch.7 tools and the libraries from ch.8.
#
# Same format as ports.spec. Staged installs (DESTDIR="$PKG"), host == target,
# so no cross flags. Patches are applied from the source URL, as the book does.

# ---------------------------------------------------------------- ch.7 tools

category=core name=gettext version=0.26 source=https://ftp.gnu.org/gnu/gettext/gettext-$version.tar.xz license=GPL-3.0-or-later description="GNU internationalization utilities and runtime" depends="ncurses"
build=./configure --disable-shared
     make
     cp -v gettext-tools/src/msgfmt gettext-tools/src/msgmerge gettext-tools/src/xgettext /usr/bin

category=core name=bison version=3.8.2 source=https://ftp.gnu.org/gnu/bison/bison-$version.tar.xz license=GPL-3.0-or-later description="GNU parser generator"
build=./configure --prefix=/usr --docdir=/usr/share/doc/bison-3.8.2
     make
     make DESTDIR="$PKG" install

category=core name=perl version=5.42.0 source=https://github.com/Perl/perl5/archive/refs/tags/v$version.tar.gz license=Artistic-1.0-Perl OR GPL-1.0-or-later description="Practical Extraction and Report Language" depends="curl"
build=sh Configure -des                                         \
                      -D prefix=/usr                            \
                      -D vendorprefix=/usr                      \
                      -D useshrplib                             \
                      -D privlib=/usr/lib/perl5/5.42/core_perl  \
                      -D archlib=/usr/lib/perl5/5.42/core_perl  \
                      -D sitelib=/usr/lib/perl5/5.42/site_perl  \
                      -D sitearch=/usr/lib/perl5/5.42/site_perl \
                      -D vendorlib=/usr/lib/perl5/5.42/vendor_perl \
                      -D vendorarch=/usr/lib/perl5/5.42/vendor_perl
     make
     make install
     # the port stages into $PKG, not the live system
     rm -rf /usr/lib/perl5

category=core name=python version=3.13.7 source=https://www.python.org/ftp/python/$version/Python-$version.tar.xz license=PSF-2.0 description="Python 3 programming language interpreter" depends="zlib openssl ncurses"
build=./configure --prefix=/usr       \
                      --enable-shared \
                      --without-ensurepip
     make
     make DESTDIR="$PKG" install
     find "$PKG" -name '*.so' -exec strip --strip-unneeded {} + 2>/dev/null || true

category=core name=texinfo version=7.2 source=https://ftp.gnu.org/gnu/texinfo/texinfo-$version.tar.xz license=GPL-3.0-or-later description="System for producing Info documentation"
build=./configure --prefix=/usr
     make
     make DESTDIR="$PKG" install

category=core name=util-linux version=2.41.1 source=https://mirrors.edge.kernel.org/pub/linux/utils/util-linux/v$version/util-linux-$version.tar.xz license=GPL-2.0-or-later LGPL-2.1-or-later BSD-3-Clause MIT description="Standard system utilities" depends="ncurses"
build=mkdir -pv "$PKG/var/lib/hwclock"
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
     make DESTDIR="$PKG" install

# ------------------------------------------------------------- ch.8 libraries

category=core name=zlib version=1.3.1 source=https://zlib.net/fossils/zlib-$version.tar.gz license=Zlib description="Compression library used by many packages"
build=./configure --prefix=/usr
     make
     make DESTDIR="$PKG" install
     rm -fv "$PKG/usr/lib/libz.a"

category=core name=bzip2 version=1.0.8 source=https://sourceware.org/pub/bzip2/bzip2-$version.tar.gz license=bzip2-1.0.6 description="High-quality data compressor" depends=zlib
build=patch -Np1 -i https://www.linuxfromscratch.org/patches/lfs/12.4/bzip2-1.0.8-install_docs-1.patch
     sed -i 's@\(ln -s -f \)$(PREFIX)/bin/@\1@' Makefile
     sed -i "s@(PREFIX)/man@(PREFIX)/share/man@g" Makefile
     make -f Makefile-libbz2_so
     make clean
     make
     make PREFIX=/usr DESTDIR="$PKG" install
     cp -av libbz2.so.* "$PKG/usr/lib"
     ln -sv libbz2.so.1.0.8 "$PKG/usr/lib/libbz2.so"
     cp -v bzip2-shared "$PKG/usr/bin/bzip2"
     for i in bzcat bunzip2; do ln -sfv bzip2 "$PKG/usr/bin/$i"; done
     rm -fv "$PKG/usr/lib/libbz2.a"

category=core name=zstd version=1.5.7 source=https://github.com/facebook/zstd/releases/download/v$version/zstd-$version.tar.gz license=BSD-3-Clause OR GPL-2.0-only description="Fast lossless compression algorithm"
build=make prefix=/usr
     make prefix=/usr DESTDIR="$PKG" install
     rm -fv "$PKG/usr/lib/libzstd.a"

category=core name=pkgconf version=2.5.1 source=https://distfiles.dereferenced.org/pkgconf/pkgconf-$version.tar.gz license=ISC description="Package configuration utility" depends=zlib
build=./configure --prefix=/usr    \
                 --disable-static \
                 --docdir=/usr/share/doc/pkgconf-2.5.1
     make
     make DESTDIR="$PKG" install
     ln -sv pkgconf "$PKG/usr/bin/pkg-config"

category=build name=ninja version=1.13.1 source=https://github.com/ninja-build/ninja/archive/refs/tags/v$version.tar.gz license=Apache-2.0 description="Small build system with few dependencies" depends="python"
build=[ -f configure.py ] || autoreconf -fi
     sed -i '/int Guess/a \
int   j = 0;\
char* jobs = getenv( "NINJAJOBS" );\
if ( jobs != NULL ) j = atoi( jobs );\
if ( j > 0 ) return j;\
' src/ninja.cc
     python3 configure.py --bootstrap
     install -vm755 ninja "$PKG/usr/bin/ninja"

category=build name=bc version=7.1.0 source=https://github.com/gavinhoward/bc/archive/refs/tags/$version.tar.gz license=GPL-2.0-or-later description="GNU bc language interpreter for arbitrary precision arithmetic"
build=CC="gcc -std=c99" ./configure --prefix=/usr -G -O3 -r
     make
     make DESTDIR="$PKG" install

category=core name=attr version=2.5.2 source=https://download.savannah.nongnu.org/releases/attr/attr-$version.tar.gz license=LGPL-2.1-or-later description="Extended attributes filesystem tool"
build=./configure --prefix=/usr     \
                 --disable-static  \
                 --sysconfdir=/etc \
                 --docdir=/usr/share/doc/attr-2.5.2
     make
     make DESTDIR="$PKG" install

category=core name=acl version=2.3.2 source=https://download.savannah.nongnu.org/releases/acl/acl-$version.tar.xz license=LGPL-2.1-or-later description="Access control list utilities"
build=./configure --prefix=/usr    \
                 --disable-static \
                 --docdir=/usr/share/doc/acl-2.3.2
     make
     make DESTDIR="$PKG" install

category=core name=libcap version=2.76 source=https://www.kernel.org/pub/linux/libs/security/linux-privs/libcap2/libcap-$version.tar.xz license=LGPL-2.1-or-later BSD-3-Clause description="POSIX capabilities library and tools"
build=sed -i '/install -m.*STA/d' libcap/Makefile
     make prefix=/usr lib=lib
     make prefix=/usr lib=lib DESTDIR="$PKG" install

category=core name=libxcrypt version=4.4.38 source=https://github.com/besser82/libxcrypt/releases/download/v$version/libxcrypt-$version.tar.xz license=LGPL-2.1-or-later description="Modern libcrypt implementation with yescrypt" depends="attr"
build=./configure --prefix=/usr                 \
                 --enable-hashes=strong,glibc  \
                 --enable-obsolete-api=no      \
                 --disable-static              \
                 --disable-failure-tokens
     make
     make DESTDIR="$PKG" install
     make distclean
     ./configure --prefix=/usr                 \
                 --enable-hashes=strong,glibc  \
                 --enable-obsolete-api=glibc   \
                 --disable-static              \
                 --disable-failure-tokens
     make
     cp -av --remove-destination .libs/libcrypt.so.1* "$PKG/usr/lib"

category=build name=libelf version=0.193 source=https://sourceware.org/elfutils/elfutils-$version.tar.bz2 license=GPL-3.0-or-later LGPL-2.1-or-later description="libelf: reading ELF files, needed by the kernel's objtool" depends="zlib zstd"
build=./configure --prefix=/usr        \
                 --disable-debuginfod \
                 --enable-libdebuginfod=dummy
     make
     make -C libelf DESTDIR="$PKG" install
     install -vm644 config/libelf.pc "$PKG/usr/lib/pkgconfig"
     rm -fv "$PKG/usr/lib/libelf.a"

category=build name=gperf version=3.3 source=https://ftp.gnu.org/gnu/gperf/gperf-$version.tar.gz license=GPL-3.0-or-later description="Perfect hash function generator, used by bash and others"
build=./configure --prefix=/usr --docdir=/usr/share/doc/gperf-3.3
     make
     make DESTDIR="$PKG" install

category=build name=flex version=2.6.4 source=https://github.com/westes/flex/releases/download/v$version/flex-$version.tar.gz license=BSD-2-Clause description="Fast lexical analyser generator" depends="bison m4"
build=./configure --prefix=/usr            \
                 --docdir=/usr/share/doc/flex-2.6.4 \
                 --disable-static
     make
     make DESTDIR="$PKG" install
     ln -sv flex "$PKG/usr/bin/lex"

category=build name=autoconf version=2.72 source=https://ftp.gnu.org/gnu/autoconf/autoconf-$version.tar.xz license=GPL-3.0-or-later description="Generate configure scripts" depends="m4 perl"
build=./configure --prefix=/usr
     make
     make DESTDIR="$PKG" install

category=build name=automake version=1.18.1 source=https://ftp.gnu.org/gnu/automake/automake-$version.tar.xz license=GPL-3.0-or-later description="Generate Makefile.in files" depends="autoconf perl"
build=./configure --prefix=/usr --docdir=/usr/share/doc/automake-1.18.1
     make
     make DESTDIR="$PKG" install

category=build name=libtool version=2.5.4 source=https://ftp.gnu.org/gnu/libtool/libtool-$version.tar.xz license=GPL-2.0-or-later LGPL-2.1-or-later description="Portable shell to simplify the use of libraries" depends="m4"
build=./configure --prefix=/usr
     make
     make DESTDIR="$PKG" install
     rm -fv "$PKG/usr/lib/libltdl.a"

category=core name=openssl version=3.5.2 source=https://github.com/openssl/openssl/releases/download/openssl-$version/openssl-$version.tar.gz license=Apache-2.0 description="TLS and cryptography library" depends="zlib"
build=./config --prefix=/usr         \
              --openssldir=/etc/ssl \
              --libdir=lib          \
              shared                \
              zlib-dynamic
     make
     sed -i '/INSTALL_LIBS/s/libcrypto.a libssl.a//' Makefile
     make MANSUFFIX=ssl DESTDIR="$PKG" install
     find "$PKG" -name '*.so*' -exec strip --strip-unneeded {} + 2>/dev/null || true

category=apps name=procps version=4.0.5 source=https://sourceforge.net/projects/procps-ng/files/Production/procps-ng-$version/procps-ng-$version.tar.xz license=GPL-2.0-or-later description="Process utilities: ps, free, pgrep, sysctl" depends="ncurses"
build=./configure --prefix=/usr                    \
                 --docdir=/usr/share/doc/procps-ng-4.0.5 \
                 --disable-static                 \
                 --disable-kill                   \
                 --enable-watch8bit
     make
     make DESTDIR="$PKG" install

category=apps name=iproute2 version=6.16.0 source=https://mirrors.edge.kernel.org/pub/linux/utils/iproute2/iproute2-$version.tar.xz license=GPL-2.0-or-later description="Interface configuration and monitoring tools: ip, tc, ss" depends="bison flex"
build=sed -i /ARPD/d Makefile
     rm -fv man/man8/arpd.8
     make NETNS_RUN_DIR=/run
     make SBINDIR=/usr/sbin DESTDIR="$PKG" install

category=core name=e2fsprogs version=1.47.3 source=https://mirrors.edge.kernel.org/pub/linux/kernel/people/tytso/e2fsprogs/v$version/e2fsprogs-$version.tar.gz license=GPL-2.0-or-later BSD-3-Clause MIT description="Ext2/3/4 filesystem utilities: mkfs.ext4, fsck" depends="libcap openssl util-linux"
build=mkdir -v build
     cd       build
     ../configure --prefix=/usr       \
                  --sysconfdir=/etc   \
                  --enable-elf-shlibs \
                  --disable-libblkid  \
                  --disable-libuuid   \
                  --disable-uuidd     \
                  --disable-fsck
     make
     make DESTDIR="$PKG" install
     rm -fv "$PKG/usr/lib/libcom_err.a" "$PKG/usr/lib/libe2p.a" "$PKG/usr/lib/libext2fs.a" "$PKG/usr/lib/libss.a"
     gunzip -v "$PKG/usr/share/info/libext2fs.info.gz"
     install-info --dir-file="$PKG/usr/share/info/dir" "$PKG/usr/share/info/libext2fs.info"
     sed 's/metadata_csum_seed,//' -i "$PKG/etc/mke2fs.conf"

category=core name=shadow version=4.18.0 source=https://github.com/shadow-maint/shadow/releases/download/$version/shadow-$version.tar.gz license=ISC description="Password and account management tools" depends="attr acl libxcrypt"
build=sed -i 's/groups$(EXEEXT) //' src/Makefile.in
     sed -e 's:#ENCRYPT_METHOD DES:ENCRYPT_METHOD YESCRYPT:' \
         -e 's:/var/spool/mail:/var/mail:' \
         -i etc/login.defs
     touch /usr/bin/passwd
     ./configure --sysconfdir=/etc           \
                 --disable-static            \
                 --with-libbsd=no --without-libbsd \
                 --with-bcrypt --with-yescrypt \
                 --with-group-name-max-length=32 \
                 --without-libpam            \
                 --without-selinux           \
                 --disable-account-tools-setuid
     make
     make exec_prefix=/usr DESTDIR="$PKG" install
     # pwconv/grpconv would rewrite the live /etc files; the port does not
     cp -v "$PKG/etc/login.defs" /dev/null 2>/dev/null || true

category=core name=sysklogd version=2.7.2 source=https://github.com/torsten-ochsenknecht/sysklogd/archive/refs/tags/sysklogd-$version.tar.gz license=BSD-3-Clause description="System logger that reads kernel messages"
build=./configure --prefix=/usr      \
                 --sysconfdir=/etc  \
                 --runstatedir=/run \
                 --without-logger   \
                 --disable-static   \
                 --docdir=/usr/share/doc/sysklogd-2.7.2
     make
     make DESTDIR="$PKG" install

category=apps name=dhcpcd version=10.5.2 source=https://github.com/NetworkConfiguration/dhcpcd/archive/refs/tags/v$version.tar.gz license=ISC description="DHCPv4 and DHCPv6 client" depends="udev"
build=./configure --prefix=/usr --sysconfdir=/etc --runstatedir=/run --dbdir=/var/lib/dhcpcd
     make -j4
     make DESTDIR="$PKG" install
     mkdir -p "$PKG/var/lib/dhcpcd"
