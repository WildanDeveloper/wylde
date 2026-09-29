#!/bin/bash
# Wylde — shadow stack (login/su/passwd) + boot configuration files
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

stage libcap <<'EOF'
set -e
cd /sources
rm -rf libcap-2.76
tar -xf libcap-2.76.tar.xz
cd libcap-2.76
sed -i '/install -m.*STA/d' libcap/Makefile
make prefix=/usr lib=lib
make prefix=/usr lib=lib install
EOF

stage libxcrypt <<'EOF'
set -e
cd /sources
rm -rf libxcrypt-4.4.38
tar -xf libxcrypt-4.4.38.tar.xz
cd libxcrypt-4.4.38
./configure --prefix=/usr                \
            --enable-hashes=strong,glibc \
            --enable-obsolete-api=no     \
            --disable-static             \
            --disable-failure-tokens
make
make install
make distclean
./configure --prefix=/usr                \
            --enable-hashes=strong,glibc \
            --enable-obsolete-api=glibc  \
            --disable-static             \
            --disable-failure-tokens
make
cp -av --remove-destination .libs/libcrypt.so.1* /usr/lib
ldconfig
EOF

stage attr <<'EOF'
set -e
cd /sources
rm -rf attr-2.5.2
tar -xf attr-2.5.2.tar.gz
cd attr-2.5.2
./configure --prefix=/usr     \
            --disable-static  \
            --sysconfdir=/etc \
            --docdir=/usr/share/doc/attr-2.5.2
make
make install
ldconfig
EOF

stage acl <<'EOF'
set -e
cd /sources
rm -rf acl-2.3.2
tar -xf acl-2.3.2.tar.xz
cd acl-2.3.2
./configure --prefix=/usr    \
            --disable-static \
            --docdir=/usr/share/doc/acl-2.3.2
make
make install
ldconfig
EOF

stage shadow <<'EOF'
set -e
cd /sources
rm -rf shadow-4.18.0
tar -xf shadow-4.18.0.tar.xz
cd shadow-4.18.0
sed -i 's/groups$(EXEEXT) //' src/Makefile.in
find man -name Makefile.in -exec sed -i 's/groups\.1 / /'   {} \;
find man -name Makefile.in -exec sed -i 's/getspnam\.3 / /' {} \;
find man -name Makefile.in -exec sed -i 's/passwd\.5 / /'   {} \;
sed -e 's:#ENCRYPT_METHOD DES:ENCRYPT_METHOD YESCRYPT:' \
    -e 's:/var/spool/mail:/var/mail:'                   \
    -e '/PATH=/{s@/sbin:@@;s@/bin:@@}'                  \
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
make exec_prefix=/usr install
make -C man install-man
pwconv
grpconv
mkdir -p /etc/default
useradd -D --gid 999
sed -i '/MAIL/s/yes/no/' /etc/default/useradd
ldconfig
EOF

stage boot-config <<'EOF'
set -e
# LFS 12.4 ch. 9, adapted: the serial console line is a Wylde addition
# (visible in qemu, usable over slow links, and for debugging).
cat > /etc/inittab << "CONF"
# Begin /etc/inittab
id:3:initdefault:
si::sysinit:/etc/rc.d/init.d/rc S
l0:0:wait:/etc/rc.d/init.d/rc 0
l1:S1:wait:/etc/rc.d/init.d/rc 1
l2:2:wait:/etc/rc.d/init.d/rc 2
l3:3:wait:/etc/rc.d/init.d/rc 3
l4:4:wait:/etc/rc.d/init.d/rc 4
l5:5:wait:/etc/rc.d/init.d/rc 5
l6:6:wait:/etc/rc.d/init.d/rc 6
ca:12345:ctrlaltdel:/sbin/shutdown -t1 -a -r now
su:S06:once:/sbin/sulogin
s1:1:respawn:/sbin/sulogin
s0:2345:respawn:/sbin/agetty --noclear ttyS0 115200 vt100
1:2345:respawn:/sbin/agetty --noclear tty1 9600
2:2345:respawn:/sbin/agetty tty2 9600
3:2345:respawn:/sbin/agetty tty3 9600
4:2345:respawn:/sbin/agetty tty4 9600
5:2345:respawn:/sbin/agetty tty5 9600
6:2345:respawn:/sbin/agetty tty6 9600
# End /etc/inittab
CONF

cat > /etc/issue << "CONF"
Wylde Linux 0.1-alpha
Kernel \r on \m (\l)

CONF

cat > /etc/securetty << "CONF"
console
tty1
tty2
tty3
tty4
tty5
tty6
ttyS0
CONF

cat > /etc/hostname << "CONF"
wylde
CONF

echo "0.1-alpha" > /etc/wylde-version

# GRUB: serial console for the bootloader and the kernel
mkdir -p /etc/default
cat > /etc/default/grub << "CONF"
# Wylde GRUB defaults
GRUB_TIMEOUT=3
GRUB_DISTRIBUTOR=wylde
GRUB_CMDLINE_LINUX_DEFAULT=""
GRUB_CMDLINE_LINUX="console=ttyS0,115200n8"
GRUB_TERMINAL_OUTPUT="console serial"
GRUB_SERIAL_COMMAND="serial --unit=0 --speed=115200 --word=8 --parity=no --stop=1"
CONF
EOF

echo "[$(date +%H:%M:%S)] SHADOW_DONE" >> "$LOGDIR/build.log"
