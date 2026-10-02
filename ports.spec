# Wylde port spec, part 2 — ch.7 tools and the libraries from ch.8.
#
# Same format as ports.spec. Staged installs (DESTDIR="$PKG"), host == target,
# so no cross flags. Patches are applied from the source URL, as the book does.

# ---------------------------------------------------------------- ch.7 tools

category=core name=gettext version=0.26 source=https://ftp.gnu.org/gnu/gettext/gettext-$version.tar.xz license=GPL-3.0-or-later description="GNU internationalization utilities and runtime" depends="ncurses"
# Stage everything through $PKG. Copying binaries straight into /usr/bin would
# install files the package database cannot track, so `wld remove` would leave
# them behind. autopoint is the reason this port exists: it generates the
# gettext files autogen.sh wants.
build=./configure --prefix=/usr --disable-shared --disable-java --disable-csharp --disable-nls
     make
     make DESTDIR="$PKG" install
     find "$PKG" -name '*.la' -delete

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

category=core name=util-linux version=2.41.1 source=https://www.kernel.org/pub/linux/utils/util-linux/v2.41/util-linux-$version.tar.xz license=GPL-2.0-or-later LGPL-2.1-or-later BSD-3-Clause MIT description="Standard system utilities" depends="ncurses"
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

category=build name=libelf version=0.193 source=https://sourceware.org/ftp/elfutils/$version/elfutils-$version.tar.bz2 license=GPL-3.0-or-later LGPL-2.1-or-later description="libelf: reading ELF files, needed by the kernel's objtool" depends="zlib zstd"
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

category=build name=autoconf version=2.72 source=https://ftp.gnu.org/gnu/autoconf/autoconf-$version.tar.xz license=GPL-3.0-or-later description="Generate configure scripts" depends="perl"
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

category=apps name=procps version=4.0.5 source=https://gitlab.com/procps-ng/procps/-/archive/v$version/procps-v$version.tar.gz license=GPL-2.0-or-later description="Process utilities: ps, free, pgrep, sysctl" depends="ncurses autoconf automake gettext" srcdir=procps-v$version
# The release tarball lives on SourceForge, which serves browsers only and
# cannot be fetched by a build system. The git snapshot is scriptable, so the
# configure script is generated here with autotools instead.
build=./autogen.sh
     ./configure --prefix=/usr                    \
                 --disable-static                 \
                 --disable-kill                   \
                 --enable-watch8bit
     make
     make DESTDIR="$PKG" install

category=apps name=iproute2 version=6.16.0 source=https://www.kernel.org/pub/linux/utils/net/iproute2/iproute2-$version.tar.xz license=GPL-2.0-or-later description="Interface configuration and monitoring tools: ip, tc, ss" depends="bison flex"
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

category=core name=sysklogd version=2.7.2 source=https://github.com/troglobit/sysklogd/releases/download/v$version/sysklogd-$version.tar.gz license=BSD-3-Clause description="System logger that reads kernel messages"
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

# Phase 4 needs autotools: some upstream projects (procps-ng among them) only
# publish git snapshots, so `configure` has to be generated here rather than
# downloaded. SourceForge serves browsers only, which is why the snapshot comes
# from the project's own GitLab. m4 and perl come from the base system.
category=build name=autoconf version=2.72 source=https://ftp.gnu.org/gnu/autoconf/autoconf-$version.tar.xz license=GPL-3.0-or-later description="Generates configure scripts from configure.ac" depends="perl"
build=./configure --prefix=/usr
     make
     make DESTDIR="$PKG" install

category=build name=automake version=1.17 source=https://ftp.gnu.org/gnu/automake/automake-$version.tar.xz license=GPL-3.0-or-later description="Generates Makefile.in files for projects using autotools" depends="autoconf perl"
build=./configure --prefix=/usr
     make
     make DESTDIR="$PKG" install

# ============================================================================
# Phase 4 — Wayland desktop
#
# Ordered so each package can be built on the ones above it. Mesa is not here
# yet: wlroots can render with pixman alone, which is enough for a session that
# has no GPU at all. Mesa and LLVM come after the compositor works.
# ============================================================================

category=graphics name=wayland-protocols version=1.49 source=https://deb.debian.org/debian/pool/main/w/wayland-protocols/wayland-protocols_$version.orig.tar.xz license=MIT description="Interface definitions every Wayland component shares" depends="meson ninja" srcdir=wayland-protocols-$version
build=meson setup build --prefix=/usr --buildtype=plain -Dtests=false
     ninja -C build
     DESTDIR="$PKG" ninja -C build install

category=graphics name=libdrm version=2.4.134 source=https://deb.debian.org/debian/pool/main/libd/libdrm/libdrm_$version.orig.tar.xz license=MIT description="Kernel modesetting interface: the display drivers' userspace library" depends="meson ninja" srcdir=libdrm-$version
build=meson setup build --prefix=/usr --buildtype=plain -Dtests=false -Dman-pages=disabled -Dinstall-test-programs=false
     ninja -C build
     DESTDIR="$PKG" ninja -C build install

category=graphics name=wayland version=1.26.0 source=https://deb.debian.org/debian/pool/main/w/wayland/wayland_$version.orig.tar.xz license=MIT description="The Wayland compositor and client library" depends="libdrm wayland-protocols meson ninja libffi" srcdir=wayland-$version
build=meson setup build --prefix=/usr --buildtype=plain -Dtests=false -Ddocumentation=false -Ddocbook_validation=false -Ddtd_validation=false
     ninja -C build
     DESTDIR="$PKG" ninja -C build install

category=graphics name=xkeyboard-config version=2.48 source=https://deb.debian.org/debian/pool/main/x/xkeyboard-config/xkeyboard-config_$version.orig.tar.xz license="MIT GPL-2.0-or-later OFL-1.1" description="Keyboard layouts and keymaps for X and Wayland" srcdir=xkeyboard-config-$version
build=meson setup build --prefix=/usr --buildtype=plain -Dnls=false -Dcompat-rules=false
     ninja -C build
     DESTDIR="$PKG" ninja -C build install

category=graphics name=libxkbcommon version=1.13.1 source=https://deb.debian.org/debian/pool/main/libx/libxkbcommon/libxkbcommon_$version.orig.tar.gz license=MIT description="Keyboard layout handling for Wayland" depends="xkeyboard-config xorgproto libxml2 meson ninja"
build=meson setup build --prefix=/usr --buildtype=plain -Denable-x11=false -Denable-wayland=false -Denable-docs=false
     ninja -C build
     DESTDIR="$PKG" ninja -C build install

category=graphics name=pixman version=0.46.2 source=https://www.cairographics.org/releases/pixman-$version.tar.gz license=MIT description="Pixel manipulation library; also the renderer's last resort without a GPU" depends="meson ninja"
build=meson setup build --prefix=/usr --buildtype=plain -Dgtk=disabled -Dlibpng=disabled -Dtests=disabled -Ddemos=disabled
     ninja -C build
     DESTDIR="$PKG" ninja -C build install

category=graphics name=libevdev version=1.13.7 source=https://deb.debian.org/debian/pool/main/libe/libevdev/libevdev_$version+dfsg.orig.tar.xz license=LGPL-2.1-or-later description="evdev input device access" depends="meson ninja" srcdir=libevdev-$version
build=meson setup build --prefix=/usr --buildtype=plain -Ddocumentation=disabled -Dtests=disabled
     ninja -C build
     DESTDIR="$PKG" ninja -C build install

category=graphics name=mtdev version=1.1.7 source=https://deb.debian.org/debian/pool/main/m/mtdev/mtdev_$version.orig.tar.gz license=LGPL-2.1-or-later description="Multitouch protocol library, a libinput dependency" depends="autoconf automake" srcdir=mtdev-$version
build=./configure --prefix=/usr --disable-static
     make
     make DESTDIR="$PKG" install
     find "$PKG" -name '*.la' -delete

category=graphics name=libinput version=1.28.1 source=https://deb.debian.org/debian/pool/main/libi/libinput/libinput_$version.orig.tar.gz license=LGPL-2.1-or-later description="Turns raw input events into touch, tablet and pointer gestures" depends="libevdev mtdev meson ninja"
build=meson setup build --prefix=/usr --buildtype=plain -Ddocumentation=false -Dtests=false -Dlibwacom=false -Ddebug-gui=false
     ninja -C build
     DESTDIR="$PKG" ninja -C build install

category=graphics name=libdisplay-info version=0.3.0 source=https://deb.debian.org/debian/pool/main/libd/libdisplay-info/libdisplay-info_$version.orig.tar.bz2 license=MIT description="Reads EDID and DisplayID so a compositor knows what a connector is" depends="meson ninja" srcdir=libdisplay-info-$version
build=meson setup build --prefix=/usr --buildtype=plain
     ninja -C build
     DESTDIR="$PKG" ninja -C build install

category=graphics name=hwdata version=0.411 source=https://deb.debian.org/debian/pool/main/h/hwdata/hwdata_$version.orig.tar.gz license="MIT GPL-2.0-or-later" description="Hardware ids, so a display gets a readable name" depends="meson ninja"
build=./configure --prefix=/usr --with-pciids=false
     make
     make DESTDIR="$PKG" install


category=graphics name=seatd version=0.9.3 source=https://git.sr.ht/~kennylevinsen/seatd/archive/$version.tar.gz license=MIT description="Session and seat management, which a Wayland compositor needs to hand out input and output access" depends="meson ninja"
build=meson setup build --prefix=/usr --buildtype=plain -Dman-pages=disabled -Dexamples=disabled
     ninja -C build
     DESTDIR="$PKG" ninja -C build install

category=build name=expat version=2.7.1 source=https://github.com/libexpat/libexpat/releases/download/R_2_7_1/expat-$version.tar.xz license=MIT description="XML parser used by the graphics stack" depends=""
build=./configure --prefix=/usr --disable-static --with-sysroot=/usr
     make
     make DESTDIR="$PKG" install
     find "$PKG" -name '*.la' -delete

category=build name=libffi version=3.5.2 source=https://github.com/libffi/libffi/releases/download/v$version/libffi-$version.tar.gz license=MIT description="Portable foreign function interface, needed by the Wayland scanner" depends=""
build=./configure --prefix=/usr --disable-static --disable-multi-os-directory
     make
     make DESTDIR="$PKG" install
     find "$PKG" -name '*.la' -delete

category=build name=xorgproto version=2024.1 source=https://www.x.org/releases/individual/proto/xorgproto-$version.tar.gz license="MIT" description="X11 protocol headers, still needed by some Wayland tooling" depends=""
build=./configure --prefix=/usr
     make
     make DESTDIR="$PKG" install
     find "$PKG" -name '*.la' -delete


category=build name=libxml2 version=2.14.5 source=https://download.gnome.org/sources/libxml2/2.14/libxml2-$version.tar.xz license=MIT description="XML parser; the Wayland server and labwc's menu both want it" depends="python"
build=./autogen.sh --prefix=/usr --without-python --with-html=man --with-modules
     make
     make DESTDIR="$PKG" install
     find "$PKG" -name '*.la' -delete

category=graphics name=mesa version=26.2.3 source=https://deb.debian.org/debian/pool/main/m/mesa/mesa_$version.orig.tar.xz license="MIT" description="The GL and EGL implementations, including the software rasteriser that lets a session start with no GPU" depends="libdrm expat zlib python meson ninja" srcdir=mesa-$version
# llvm is off: softpipe renders correctly on the CPU and costs a fraction of a
# full LLVM build. Turning llvmpipe on later is one line, not a rebuild of the
# desktop.
build=meson setup build --prefix=/usr --buildtype=plain -Dllvm=disabled -Dgallium-drivers=softpipe -Dvulkan-drivers= -Dgles2=enabled -Dgles1=disabled -Dopengl=true -Dglx=disabled -Dshared-glapi=enabled -Dplatforms=wayland -Dbuild-tests=false -Denable-glcpp-tests=false
     ninja -C build
     DESTDIR="$PKG" ninja -C build install

category=graphics name=wlroots version=0.18.2 source=https://deb.debian.org/debian/pool/main/w/wlroots/wlroots_0.18.2.orig.tar.bz2 license="MIT" description="The Wayland compositor library: everything a compositor needs, nothing it does not" depends="libdrm libdisplay-info hwdata libinput seatd libxkbcommon mesa pixman wayland wayland-protocols xorgproto meson ninja" srcdir=wlroots-0.18.2
# GLES2 rendering on Mesa's software rasteriser: the one path that works on a
# machine with no GPU at all, which is exactly where a first boot has to succeed.
# wlroots 0.18 is the newest release labwc 0.8.3 links against, and it has no
# pixman renderer either: Mesa's softpipe is what makes a GPU-less session work.
# Xwayland is off: Wylde does not pretend to be X11.
build=meson setup build --prefix=/usr --buildtype=plain -Dbackends=libinput,drm -Drenderers=gles2 -Dxwayland=disabled -Dsession=enabled -Dexamples=false
     ninja -C build
     DESTDIR="$PKG" ninja -C build install

category=graphics name=labwc version=0.8.3 source=https://deb.debian.org/debian/pool/main/l/labwc/labwc_0.8.3.orig.tar.gz license="MIT" description="A small, fast, scriptable Wayland compositor" depends="wlroots wayland libxkbcommon xorgproto seatd libdrm glib pango cairo meson ninja"
build=meson setup build --prefix=/usr --buildtype=plain -Dman-pages=disabled -Dnls=disabled -Dtest=disabled -Dsvg=disabled
     ninja -C build
     DESTDIR="$PKG" ninja -C build install

category=graphics name=foot version=1.28.0 source=https://deb.debian.org/debian/pool/main/f/foot/foot_$version.orig.tar.xz license="MIT" description="A small terminal emulator that speaks Wayland natively" depends="freetype fontconfig ncurses libpng meson ninja" srcdir=foot-$version
build=meson setup build --prefix=/usr --buildtype=plain -Dtests=false -Ddocs=false
     ninja -C build
     DESTDIR="$PKG" ninja -C build install

category=graphics name=freetype version=2.14.1 source=https://download.savannah.gnu.org/releases/freetype/freetype-$version.tar.xz license="FTL GPL-2.0-or-later" description="Font rasteriser: without it there is no readable text anywhere"
build=./configure --prefix=/usr --disable-static --with-zlib=yes --with-bzip2=yes
     make
     make DESTDIR="$PKG" install
     find "$PKG" -name '*.la' -delete

category=graphics name=libpng version=1.6.50 source=https://github.com/pnggroup/libpng/archive/refs/tags/v$version.tar.gz license="PNG" description="PNG codec, needed by the terminal and every screenshot tool" depends="zlib" srcdir=libpng-$version
# libpng still ships autotools at 1.6.50; meson arrived later. Staying with
# configure keeps the build free of a cmake bootstrap.
build=./configure --prefix=/usr --disable-static
     make
     make DESTDIR="$PKG" install
     find "$PKG" -name '*.la' -delete

category=graphics name=fontconfig version=2.17.1 source=https://deb.debian.org/debian/pool/main/f/fontconfig/fontconfig_$version.orig.tar.gz license="MIT" description="Finds and caches the fonts on the system" depends="expat freetype zlib"
# fontconfig 2.17 is a meson project; the autotools build is gone
build=meson setup build --prefix=/usr --buildtype=plain -Ddoc=disabled -Ddoc-txt=disabled -Ddoc-man=disabled -Dtests=disabled
     ninja -C build
     DESTDIR="$PKG" ninja -C build install
     # an empty cache directory: the real cache is written at first boot
     mkdir -p "$PKG/var/cache/fontconfig"

category=graphics name=weston version=16.0.0 source=https://deb.debian.org/debian/pool/main/w/weston/weston_$version.orig.tar.xz license="MIT" description="Reference Wayland compositor. Kept for one reason: its pixman backend renders with the CPU, so a session starts on a machine with no GPU at all" depends="wayland wayland-protocols libdrm pixman libinput libxkbcommon xorgproto expat libxml2 meson ninja" srcdir=weston-$version
build=meson setup build --prefix=/usr --buildtype=plain -Dbackend-drm=true -Dbackend-headless=true -Dbackend-wayland=false -Dbackend-x11=false -Dbackend-pipewire=false -Dbackend-rdp=false -Dbackend-vnc=false -Drenderer-gl=false -Drenderer-vulkan=false -Ddoc=false -Ddemo-clients=false -Dimage-jpeg=false -Dimage-webp=false -Dshell-desktop=false -Dcolor-management-lcms=false -Dperfetto=false -Dsystemd=false -Dshell-lua=false -Dsimple-clients= -Dshell-ivi=false -Dshell-kiosk=false -Dxwayland=false
     ninja -C build
     DESTDIR="$PKG" ninja -C build install

category=graphics name=cairo version=1.18.4 source=https://deb.debian.org/debian/pool/main/c/cairo/cairo_$version.orig.tar.xz license="LGPL-2.1-or-later MPL-1.1" description="2D drawing, the part of a desktop that draws even when there is no GPU" depends="pixman freetype fontconfig expat zlib libpng meson ninja" srcdir=cairo-$version
# image surface only: no X11, no EGL. A GPU-specific surface belongs to Mesa,
# and Mesa is a separate decision.
build=meson setup build --prefix=/usr --buildtype=plain -Dxlib=disabled -Dxlib-xcb=disabled -Dxcb=disabled -Dpng=enabled -Dquartz=disabled -Dglib=disabled -Dspectre=disabled -Ddwrite=disabled -Dtests=disabled
     ninja -C build
     DESTDIR="$PKG" ninja -C build install

category=build name=pyyaml version=6.0.3 source=https://github.com/yaml/pyyaml/archive/refs/tags/$version.tar.gz license=MIT description="YAML parser for Python; the base Python has no pip, so only the pure-Python part is installed" srcdir=pyyaml-$version
# Pure Python, and the base Python has no setuptools: unpack into the stdlib's
# own site-packages, which is already on sys.path.
build=mkdir -p "$PKG/usr/lib/python3.13/site-packages"
     cp -r "$SRCDIR/lib/yaml" "$PKG/usr/lib/python3.13/site-packages/"

category=build name=mako version=1.3.10 source=https://deb.debian.org/debian/pool/main/m/mako/mako_$version.orig.tar.gz license=MIT description="Template engine Python uses to generate Mesa's shader code"
build=mkdir -p "$PKG/usr/lib/python3.13/site-packages"
     cp -r "$SRCDIR/mako" "$PKG/usr/lib/python3.13/site-packages/"

category=build name=packaging version=25.0 source=https://github.com/pypa/packaging/archive/refs/tags/$version.tar.gz license="Apache-2.0 OR BSD-2-Clause" description="Version comparison for Python; Python 3.13 dropped distutils and mesa's build checks versions with it" srcdir=packaging-$version
build=mkdir -p "$PKG/usr/lib/python3.13/site-packages"
     cp -r "$SRCDIR/src/packaging" "$PKG/usr/lib/python3.13/site-packages/"


category=build name=pcre2 version=10.48 source=https://deb.debian.org/debian/pool/main/p/pcre2/pcre2_$version.orig.tar.gz license=BSD-3-Clause description="Regular expression library, needed by glib" depends=""
build=./configure --prefix=/usr --disable-static --enable-jit --enable-pcre2-16 --enable-pcre2-32 --enable-pcre2grep-jit
     make
     make DESTDIR="$PKG" install
     find "$PKG" -name '*.la' -delete

category=build name=glib version=2.84.4 source=https://download.gnome.org/sources/glib/2.84/glib-$version.tar.xz license=LGPL-2.1-or-later description="Foundational library for GNOME software; labwc's toolkit" depends="libffi pcre2 zlib meson ninja"
build=meson setup build --prefix=/usr --buildtype=plain -Dintrospection=disabled -Dtests=false -Dman-pages=disabled -Dglib_debug=disabled
     ninja -C build
     DESTDIR="$PKG" ninja -C build install


category=graphics name=pango version=1.56.4 source=https://download.gnome.org/sources/pango/1.56/pango-$version.tar.xz license=LGPL-2.1-or-later description="Text layout with shaping; a compositor draws text with it" depends="cairo glib harfbuzz fribidi meson ninja"
build=meson setup build --prefix=/usr --buildtype=plain -Dintrospection=disabled -Dbuild-testsuite=false
     ninja -C build
     DESTDIR="$PKG" ninja -C build install

category=graphics name=fribidi version=1.0.16 source=https://deb.debian.org/debian/pool/main/f/fribidi/fribidi_$version.orig.tar.xz license=LGPL-2.1-or-later description="Bidirectional text, so a non-Latin language is not mangled" depends="meson ninja"
build=meson setup build --prefix=/usr --buildtype=plain -Ddocs=false -Dtests=false
     ninja -C build
     DESTDIR="$PKG" ninja -C build install

category=graphics name=harfbuzz version=10.2.0 source=https://deb.debian.org/debian/pool/main/h/harfbuzz/harfbuzz_$version.orig.tar.xz license="MIT" description="Text shaping: without it letters do not connect" depends="freetype cairo glib meson ninja"
build=meson setup build --prefix=/usr --buildtype=plain -Dtests=disabled -Ddocs=disabled -Dintrospection=disabled -Dicu=disabled -Dgraphite=disabled -Dgobject=disabled
     ninja -C build
     DESTDIR="$PKG" ninja -C build install
