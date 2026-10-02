#!/bin/bash
# Wylde — udev (hotplug) and sysklogd, so the boot scripts stop failing
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

stage pyjinja <<'XEOF'
set -e
# jinja2 (pure Python) is needed by meson when configuring udev. The chroot has
# no pip and no DNS, so on a Debian host: copy /usr/lib/python3/dist-packages/
# {jinja2,markupsafe} into /usr/lib/python3.13/site-packages/ before this phase.
python3 -c 'import jinja2; print("jinja2", jinja2.__version__)'
XEOF

stage udev <<'XEOF'
set -e
cd /sources
rm -rf systemd-257.8
tar -xf systemd-257.8.tar.gz
cd systemd-257.8
sed -e 's/GROUP="render"/GROUP="video"/' \
    -e 's/GROUP="sgx", //' \
    -i rules.d/50-udev-default.rules.in
sed -i '/systemd-sysctl/s/^/#/' rules.d/99-systemd.rules.in
sed -e '/NETWORK_DIRS/s/systemd/udev/' \
    -i src/libsystemd/sd-network/network-util.h
mkdir -p build
cd       build
meson setup .. \
    --prefix=/usr \
    --buildtype=release \
    -D mode=release \
    -D dev-kvm-mode=0660 \
    -D link-udev-shared=false \
    -D logind=false \
    -D vconsole=false
export udev_helpers=$(grep "'name' :" ../src/udev/meson.build | \
    awk '{print $3}' | tr -d ",'" | grep -v 'udevadm')
ninja udevadm systemd-hwdb                                           \
    $(ninja -n | grep -Eo '(src/(lib)?udev|rules.d|hwdb.d)/[^ ]*')   \
    $(realpath libudev.so --relative-to .)                           \
    $udev_helpers
install -vm755 -d /usr/lib/udev/hwdb.d /usr/lib/udev/rules.d /usr/lib/udev/network
install -vm755 -d /etc/udev/hwdb.d /etc/udev/rules.d /etc/udev/network
install -vm755 -d /usr/lib/pkgconfig /usr/share/pkgconfig
install -vm755 udevadm                     /usr/bin/
install -vm755 systemd-hwdb                /usr/bin/udev-hwdb
# systemd 257 ships one binary: udevadm runs as a daemon when it is called
# through this name, which is what meson does upstream as well.
ln      -svfn  ../bin/udevadm              /usr/sbin/udevd
cp      -av    libudev.so.1.*               /usr/lib/
ln -sf libudev.so.1 /usr/lib/libudev.so
install -vm644 ../src/libudev/libudev.h      /usr/include/
install -vm644 src/libudev/*.pc             /usr/lib/pkgconfig/
install -vm644 src/udev/*.pc                /usr/share/pkgconfig/
install -vm644 ../src/udev/udev.conf         /etc/udev/
install -vm644 rules.d/* ../rules.d/README  /usr/lib/udev/rules.d/
install -vm644 $(find ../rules.d/*.rules \
    -not -name '*power-switch*')            /usr/lib/udev/rules.d/
install -vm644 hwdb.d/*  ../hwdb.d/{*.hwdb,README} /usr/lib/udev/hwdb.d/
install -vm755 $udev_helpers                /usr/lib/udev
install -vm644 ../network/99-default.link   /usr/lib/udev/network
unset udev_helpers
ldconfig
udevadm --version
echo UDEV_OK
XEOF

stage sysklogd <<'XEOF'
set -e
cd /sources
rm -rf sysklogd-2.7.2
tar -xf sysklogd-2.7.2.tar.gz
cd sysklogd-2.7.2
./configure --prefix=/usr      \
            --sysconfdir=/etc  \
            --runstatedir=/run \
            --without-logger   \
            --disable-static   \
            --docdir=/usr/share/doc/sysklogd-2.7.2
make
make install
cat > /etc/syslog.conf << "CONF"
# Begin /etc/syslog.conf
auth,authpriv.* -/var/log/auth.log
*.*;auth,authpriv.none -/var/log/sys.log
daemon.* -/var/log/daemon.log
kern.* -/var/log/kern.log
mail.* -/var/log/mail.log
user.* -/var/log/user.log
*.emerg *
# Do not open any internet ports.
secure_mode 2
# End /etc/syslog.conf
CONF
echo SYSKLOGD_OK
XEOF

echo "[$(date +%H:%M:%S)] UDEV_SYSLOG_DONE" >> "$LOGDIR/build.log"
