#!/bin/bash
# Wylde — dhcpcd (DHCP client) and network boot integration
# dhcpcd is a BLFS package, not in the LFS wget-list; source is the GitHub
# release tarball (v10.5.2).
set -e
export LFS=/mnt/lfs
export LOGDIR=${LOGDIR:-/tmp/wylde-build}
mkdir -p "$LOGDIR"

stage() {
  echo "[$(date +%H:%M:%S)] START $1" >> "$LOGDIR/build.log"
  if chroot "$LFS" /usr/bin/env -i \
        HOME=/root TERM=dumb PS1='(wylde) #' \
        PATH=/usr/bin:/usr/sbin MAKEFLAGS="-j$(nproc)" \
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

stage dhcpcd <<'XEOF'
set -e
cd /sources
rm -rf dhcpcd-10.5.2
tar -xf dhcpcd-10.5.2.tar.gz
cd dhcpcd-10.5.2
./configure --prefix=/usr --sysconfdir=/etc --runstatedir=/run --dbdir=/var/lib/dhcpcd
make -j4
make install
# keep hooks minimal: no config or resolvconf rewriting, dhcpcd only does DHCP
mkdir -p /etc/dhcpcd.conf.d
cat > /etc/dhcpcd.conf << "CONF"
# Begin /etc/dhcpcd.conf
# Wylde: plain DHCP client. No hostname mangling, no hooks.
nohook lookup-hostname
nohook resolvconf
nohook resolvconf.conf
nohook libaudit
nohook ntpd
# End /etc/dhcpcd.conf
CONF
mkdir -p /var/lib/dhcpcd
dhcpcd --version 2>&1 | head -1
echo DHCPCD_OK
XEOF

# dhcpcd drops privileges to its own user
stage dhcpcd-user <<'XEOF'
set -e
groupadd -r dhcpcd 2>/dev/null || true
useradd -r -g dhcpcd -d /var/lib/dhcpcd -s /usr/bin/false dhcpcd 2>/dev/null || true
mkdir -p /var/lib/dhcpcd
chown dhcpcd:dhcpcd /var/lib/dhcpcd
id dhcpcd
XEOF

stage network-boot <<'XEOF'
set -e
cat > /etc/sysconfig/network << "CONF"
# Begin /etc/sysconfig/network
# Wylde: DHCP only. Static addresses go in rc.d/ipv4-static as usual.
DHCP=yes
CONF

# The LFS network script runs /etc/rc.d/ipv4-static; provide a DHCP one and
# point the script at it. ipv4-static is a no-op when the interface is already
# configured, so the sequence stays the book's.
cat > /etc/rc.d/ipv4 << "CONF"
#!/bin/sh
# Begin /etc/rc.d/ipv4
. /etc/sysconfig/network

case "$DHCP" in
    yes)
        echo -n "Starting DHCP client... "
        dhcpcd -4 -q -t 10 -b 2>&1
        ;;
    *)
        echo "Starting IPv4... "
        /etc/rc.d/ipv4-static
        ;;
esac
# End /etc/rc.d/ipv4
CONF
chmod +x /etc/rc.d/ipv4
rm -f /etc/rc.d/ipv4-dhcp

# stop DHCP on shutdown
cat > /etc/rc.d/ipv4-down << "CONF"
#!/bin/sh
# Begin /etc/rc.d/ipv4-down
echo -n "Stopping DHCP client... "
dhcpcd -x 2>&1
# End /etc/rc.d/ipv4-down
CONF
chmod +x /etc/rc.d/ipv4-down

# the boot script already sources /etc/rc.d/ipv4 and runs ipv4-down on stop,
# but make sure the symlinks exist in every runlevel that uses them
for rl in 2 3 4 5; do
  ln -sf ../ipv4       /etc/rc.d/rc$rl.d/S20network
  ln -sf ../ipv4-down  /etc/rc.d/rc$rl.d/K80network
done
rm -f /etc/rc.d/rc2.d/S20ipv4 /etc/rc.d/rc3.d/S20ipv4 /etc/rc.d/rc4.d/S20ipv4 /etc/rc.d/rc5.d/S20ipv4
ls -l /etc/rc.d/rc3.d/ | grep -E 'network|ipv4'
echo NETWORK_BOOT_OK
XEOF

echo "[$(date +%H:%M:%S)] DHCPCD_DONE" >> "$LOGDIR/build.log"
