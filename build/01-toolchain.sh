#!/bin/bash
# Wylde — LFS 12.4 ch. 5: cross toolchain
# Runs as root; every stage is executed as the lfs user.
set -e
export LFS=/mnt/lfs
export LOGDIR=${LOGDIR:-/tmp/wylde-build}
mkdir -p "$LOGDIR"

stage() {   # stage <name> <script-file>
  echo "[$(date +%H:%M:%S)] START $1" >> "$LOGDIR/build.log"
  if su - lfs < "$2" > "$LOGDIR/$1.log" 2>&1; then
    echo "[$(date +%H:%M:%S)] DONE $1" >> "$LOGDIR/build.log"
  else
    echo "[$(date +%H:%M:%S)] FAIL $1 — see $LOGDIR/$1.log" >> "$LOGDIR/build.log"
    # the reason has to be visible where the failure is reported, not only in a
    # file nobody has open
    tail -n 25 "$LOGDIR/$1.log" >&2 || true
    exit 1
  fi
}

cat > /tmp/wylde-ch5-binutils1.sh <<'STAGE'
set -e
cd $LFS/sources
rm -rf binutils-2.45
tar -xf binutils-2.45.tar.xz
cd binutils-2.45
mkdir -v build
cd build
../configure --prefix=$LFS/tools \
             --with-sysroot=$LFS \
             --target=$LFS_TGT \
             --disable-nls \
             --enable-gprofng=no \
             --disable-werror \
             --enable-new-dtags \
             --enable-default-hash-style=gnu
make
make install
STAGE
stage binutils-pass1 /tmp/wylde-ch5-binutils1.sh

cat > /tmp/wylde-ch5-gcc1.sh <<'STAGE'
set -e
cd $LFS/sources
rm -rf gcc-15.2.0
tar -xf gcc-15.2.0.tar.xz
cd gcc-15.2.0
tar -xf ../mpfr-4.2.2.tar.xz
mv -v mpfr-4.2.2 mpfr
tar -xf ../gmp-6.3.0.tar.xz
mv -v gmp-6.3.0 gmp
tar -xf ../mpc-1.3.1.tar.gz
mv -v mpc-1.3.1 mpc
case $(uname -m) in
    x86_64)
        sed -e '/m64=/s/lib64/lib/' \
            -i.orig gcc/config/i386/t-linux64
    ;;
esac
mkdir -v build
cd       build
../configure                  \
    --target=$LFS_TGT         \
    --prefix=$LFS/tools       \
    --with-glibc-version=2.42 \
    --with-sysroot=$LFS       \
    --with-newlib             \
    --without-headers         \
    --enable-default-pie      \
    --enable-default-ssp      \
    --disable-nls             \
    --disable-shared          \
    --disable-multilib        \
    --disable-threads         \
    --disable-libatomic       \
    --disable-libgomp         \
    --disable-libquadmath     \
    --disable-libssp          \
    --disable-libvtv          \
    --disable-libstdcxx       \
    --enable-languages=c,c++
make
make install
cd ..
cat gcc/limitx.h gcc/glimits.h gcc/limity.h > \
  `dirname $($LFS_TGT-gcc -print-libgcc-file-name)`/include/limits.h
STAGE
stage gcc-pass1 /tmp/wylde-ch5-gcc1.sh

cat > /tmp/wylde-ch5-headers.sh <<'STAGE'
set -e
cd $LFS/sources
rm -rf linux-6.16.1
tar -xf linux-6.16.1.tar.xz
cd linux-6.16.1
make mrproper
make headers
find usr/include -type f ! -name '*.h' -delete
cp -rv usr/include $LFS/usr
STAGE
stage linux-headers /tmp/wylde-ch5-headers.sh

cat > /tmp/wylde-ch5-glibc.sh <<'STAGE'
set -e
cd $LFS/sources
rm -rf glibc-2.42
tar -xf glibc-2.42.tar.xz
cd glibc-2.42
case $(uname -m) in
    i?86)   ln -sfv ld-linux.so.2 $LFS/lib/ld-lsb.so.3
    ;;
    x86_64) ln -sfv ../lib/ld-linux-x86-64.so.2 $LFS/lib64
            ln -sfv ../lib/ld-linux-x86-64.so.2 $LFS/lib64/ld-lsb-x86-64.so.3
    ;;
esac
patch -Np1 -i ../glibc-2.42-fhs-1.patch
mkdir -v build
cd       build
echo "rootsbindir=/usr/sbin" > configparms
../configure                             \
    --prefix=/usr                        \
    --host=$LFS_TGT                      \
    --build=$(../scripts/config.guess)   \
    --disable-nscd                       \
    libc_cv_slibdir=/usr/lib             \
    --enable-kernel=5.4
make
make DESTDIR=$LFS install
sed '/RTLDLIST=/s@/usr@@g' -i $LFS/usr/bin/ldd
echo 'int main(){}' | $LFS_TGT-gcc -x c - -v -Wl,--verbose &> dummy.log
readelf -l a.out | grep ': /lib'
grep -E -o "$LFS/lib.*/S?crt[1in].*succeeded" dummy.log
grep -B3 "^ $LFS/usr/include" dummy.log
grep 'SEARCH.*/usr/lib' dummy.log | sed 's|; |\n|g'
grep "/lib.*/libc.so.6 " dummy.log
grep found dummy.log
rm -v a.out dummy.log
STAGE
stage glibc /tmp/wylde-ch5-glibc.sh

cat > /tmp/wylde-ch5-libstdcpp.sh <<'STAGE'
set -e
cd $LFS/sources/gcc-15.2.0
rm -rf build
mkdir -v build
cd       build
../libstdc++-v3/configure      \
    --host=$LFS_TGT            \
    --build=$(../config.guess) \
    --prefix=/usr              \
    --disable-multilib         \
    --disable-nls              \
    --disable-libstdcxx-pch    \
    --with-gxx-include-dir=/tools/$LFS_TGT/include/c++/15.2.0
make
make DESTDIR=$LFS install
rm -fv $LFS/usr/lib/lib{stdc++{,exp,fs},supc++}.la
STAGE
stage libstdcpp /tmp/wylde-ch5-libstdcpp.sh
rm -rf $LFS/sources/gcc-15.2.0

# --- the remaining temporary tools, all with the same shape ---
simple_stage() {  # simple_stage <name> <tarball> <dirglob> <configure-flags...>
  local name=$1 tarball=$2 dirglob=$3; shift 3
  cat > /tmp/wylde-ch5-$name.sh <<STAGE
set -e
cd \$LFS/sources
# remove the previous unpacked tree, never the tarball: "rm -rf bash-*" also
# matches bash-5.3.tar.gz, and the archive is the one thing that cannot be
# fetched again for free
find . -maxdepth 1 -type d -name "$dirglob" -exec rm -rf {} +
tar -xf $tarball
# "cd bash-*" matches the unpacked directory *and* the tarball next to it, and
# cd then refuses two arguments. Ask for a directory explicitly.
source_dir=$(find . -maxdepth 1 -type d -name "$dirglob" | head -1)
[ -n "$source_dir" ] || { echo "no directory matching $dirglob after unpacking $tarball" >&2; exit 1; }
cd "$source_dir"
$*
STAGE
  stage "$name" /tmp/wylde-ch5-$name.sh
  ( cd "$LFS/sources" && find . -maxdepth 1 -type d -name "$dirglob" -exec rm -rf {} + )
}

simple_stage m4 m4-1.4.20.tar.xz 'm4-1.4.20' './configure --prefix=/usr \
    --host=$LFS_TGT \
    --build=$(build-aux/config.guess)
make
make DESTDIR=$LFS install'

simple_stage ncurses ncurses-6.6.tar.gz 'ncurses-6.6' 'mkdir build
pushd build
  ../configure --prefix=$LFS/tools AWK=gawk
  make -C include
  make -C progs tic
  install progs/tic $LFS/tools/bin
popd
./configure --prefix=/usr                \
    --host=$LFS_TGT                      \
    --build=$(./config.guess)            \
    --mandir=/usr/share/man              \
    --with-manpage-format=normal         \
    --with-shared                        \
    --without-normal                     \
    --with-cxx-shared                    \
    --without-debug                      \
    --without-ada                        \
    --disable-stripping                  \
    AWK=gawk
make
make DESTDIR=$LFS install
ln -sv libncursesw.so $LFS/usr/lib/libncurses.so
sed -e "s/^#if.*XOPEN.*$/#if 1/" -i $LFS/usr/include/curses.h'

simple_stage bash bash-*.tar.gz 'bash-*' './configure --prefix=/usr                      \
    --build=$(sh support/config.guess) \
    --host=$LFS_TGT                    \
    --without-bash-malloc
make
make DESTDIR=$LFS install
ln -sv bash $LFS/bin/sh'

simple_stage coreutils coreutils-*.tar.xz 'coreutils-*' './configure --prefix=/usr                     \
    --host=$LFS_TGT                   \
    --build=$(build-aux/config.guess) \
    --enable-install-program=hostname \
    --enable-no-install-program=kill,uptime
make
make DESTDIR=$LFS install
mv -v $LFS/usr/bin/chroot              $LFS/usr/sbin
mkdir -pv $LFS/usr/share/man/man8
mv -v $LFS/usr/share/man/man1/chroot.1 $LFS/usr/share/man/man8/chroot.8
sed -i "s/\"1\"/\"8\"/"                    $LFS/usr/share/man/man8/chroot.8'

simple_stage diffutils diffutils-*.tar.xz 'diffutils-*' './configure --prefix=/usr   \
    --host=$LFS_TGT \
    gl_cv_func_strcasecmp_works=y \
    --build=$(./build-aux/config.guess)
make
make DESTDIR=$LFS install'

simple_stage file file-*.tar.gz 'file-*' 'mkdir build
pushd build
  ../configure --disable-bzlib      \
               --disable-libseccomp \
               --disable-xzlib      \
               --disable-zlib
  make
popd
./configure --prefix=/usr --host=$LFS_TGT --build=$(./config.guess)
make FILE_COMPILE=$(pwd)/build/src/file
make DESTDIR=$LFS install
rm -fv $LFS/usr/lib/libmagic.la'

simple_stage findutils findutils-*.tar.xz 'findutils-*' './configure --prefix=/usr                   \
    --localstatedir=/var/lib/locate \
    --host=$LFS_TGT                 \
    --build=$(build-aux/config.guess)
make
make DESTDIR=$LFS install'

simple_stage gawk gawk-*.tar.xz 'gawk-*' 'sed -i "s/extras//" Makefile.in
./configure --prefix=/usr   \
    --host=$LFS_TGT \
    --build=$(build-aux/config.guess)
make
make DESTDIR=$LFS install'

simple_stage grep grep-*.tar.xz 'grep-*' './configure --prefix=/usr   \
    --host=$LFS_TGT \
    --build=$(./build-aux/config.guess)
make
make DESTDIR=$LFS install'

simple_stage gzip gzip-*.tar.xz 'gzip-*' './configure --prefix=/usr --host=$LFS_TGT
make
make DESTDIR=$LFS install'

simple_stage make make-*.tar.gz 'make-*' './configure --prefix=/usr   \
    --host=$LFS_TGT \
    --build=$(build-aux/config.guess)
make
make DESTDIR=$LFS install'

simple_stage patch patch-*.tar.xz 'patch-*' './configure --prefix=/usr   \
    --host=$LFS_TGT \
    --build=$(build-aux/config.guess)
make
make DESTDIR=$LFS install'

simple_stage sed sed-*.tar.xz 'sed-*' './configure --prefix=/usr   \
    --host=$LFS_TGT \
    --build=$(build-aux/config.guess)
make
make DESTDIR=$LFS install'

simple_stage tar tar-*.tar.xz 'tar-*' './configure --prefix=/usr   \
    --host=$LFS_TGT \
    --build=$(build-aux/config.guess)
make
make DESTDIR=$LFS install'

simple_stage xz xz-*.tar.xz 'xz-*' './configure --prefix=/usr                     \
    --host=$LFS_TGT                   \
    --build=$(build-aux/config.guess) \
    --disable-static                  \
    --docdir=/usr/share/doc/xz-5.8.1
make
make DESTDIR=$LFS install
rm -fv $LFS/usr/lib/liblzma.la'

cat > /tmp/wylde-ch5-binutils2.sh <<'STAGE'
set -e
cd $LFS/sources
rm -rf binutils-2.45
tar -xf binutils-2.45.tar.xz
cd binutils-2.45
sed '6031s/$add_dir//' -i ltmain.sh
mkdir -v build
cd       build
../configure                   \
    --prefix=/usr              \
    --build=$(../config.guess) \
    --host=$LFS_TGT            \
    --disable-nls              \
    --enable-shared            \
    --enable-gprofng=no        \
    --disable-werror           \
    --enable-64-bit-bfd        \
    --enable-new-dtags         \
    --enable-default-hash-style=gnu
make
make DESTDIR=$LFS install
rm -fv $LFS/usr/lib/lib{bfd,ctf,ctf-nobfd,opcodes,sframe}.{a,la}
STAGE
stage binutils-pass2 /tmp/wylde-ch5-binutils2.sh
rm -rf $LFS/sources/binutils-2.45

cat > /tmp/wylde-ch5-gcc2.sh <<'STAGE'
set -e
cd $LFS/sources
rm -rf gcc-15.2.0
tar -xf gcc-15.2.0.tar.xz
cd gcc-15.2.0
tar -xf ../mpfr-4.2.2.tar.xz
mv -v mpfr-4.2.2 mpfr
tar -xf ../gmp-6.3.0.tar.xz
mv -v gmp-6.3.0 gmp
tar -xf ../mpc-1.3.1.tar.gz
mv -v mpc-1.3.1 mpc
case $(uname -m) in
    x86_64)
        sed -e '/m64=/s/lib64/lib/' \
            -i.orig gcc/config/i386/t-linux64
    ;;
esac
sed '/thread_header =/s/@.*@/gthr-posix.h/' \
    -i libgcc/Makefile.in libstdc++-v3/include/Makefile.in
mkdir -v build
cd       build
../configure                   \
    --build=$(../config.guess) \
    --host=$LFS_TGT            \
    --target=$LFS_TGT          \
    --prefix=/usr              \
    --with-build-sysroot=$LFS  \
    --enable-default-pie       \
    --enable-default-ssp       \
    --disable-nls              \
    --disable-multilib         \
    --disable-libatomic        \
    --disable-libgomp          \
    --disable-libquadmath      \
    --disable-libsanitizer     \
    --disable-libssp           \
    --disable-libvtv           \
    --enable-languages=c,c++   \
    LDFLAGS_FOR_TARGET=-L$PWD/$LFS_TGT/libgcc
make
make DESTDIR=$LFS install
ln -sv gcc $LFS/usr/bin/cc
STAGE
stage gcc-pass2 /tmp/wylde-ch5-gcc2.sh
rm -rf $LFS/sources/gcc-15.2.0

echo "[$(date +%H:%M:%S)] CHAPTER5_DONE" >> "$LOGDIR/build.log"
