#!/bin/bash
# Wylde desktop session
#
# Installs the session launcher, the compositor configuration and the service
# entry that starts a graphical login on tty7. Deliberately small: one script,
# one configuration file, one autostart.
set -e

SRC_DIR=$(cd "$(dirname "$0")/.." && pwd)
LFS=${LFS:-/mnt/lfs}
LOGDIR=${LOGDIR:-/tmp/wylde-build}
mkdir -p "$LOGDIR"

log() { echo "[desktop] $*"; }

log "installing the session launcher"
install -d "$LFS/usr/bin" "$LFS/usr/share/wylde"
install -m755 "$SRC_DIR/src/desktop/wylde-session" "$LFS/usr/bin/wylde-session"
install -m755 "$SRC_DIR/src/desktop/wylde-udev-start" "$LFS/usr/bin/wylde-udev-start"

log "installing the labwc configuration"
install -d "$LFS/etc/wylde/labwc"
install -m644 "$SRC_DIR/src/desktop/labwc/rc.xml" "$LFS/etc/wylde/labwc/rc.xml"
install -m644 "$SRC_DIR/src/desktop/labwc/autostart" "$LFS/usr/share/wylde/labwc-autostart"
install -m755 "$SRC_DIR/src/desktop/labwc/welcome" "$LFS/usr/bin/wylde-welcome"
# labwc looks for "autostart" next to the config it was given
ln -sf /usr/share/wylde/labwc-autostart "$LFS/etc/wylde/labwc/autostart"

log "declaring the session for display managers and logins"
install -d "$LFS/usr/share/wayland-sessions"
cat > "$LFS/usr/share/wayland-sessions/wylde.desktop" << 'DESKTOP'
[Desktop Entry]
Name=Wylde
Comment=Wylde Linux Wayland session
Exec=/usr/bin/wylde-session
Type=Application
DESKTOP

log "building the hardware database udev looks devices up in"
# Without hwdb.bin every hwdb lookup in the rules fails, so no device ever gets
# its ID_INPUT_* properties, and libinput reports a machine with no keyboard.
# The database is static data: build it once, not on every boot.
if [ -x "$LFS/usr/bin/udev-hwdb" ]; then
    chroot "$LFS" /usr/bin/udev-hwdb update 2>>"$LOGDIR/udev-hwdb.log" || {
        log "  udev-hwdb update failed — see $LOGDIR/udev-hwdb.log"
        exit 1
    }
    log "  hwdb: $(du -h "$LFS/etc/udev/hwdb.bin" | cut -f1)"
fi

log "the session probe: proof that the compositor serves clients"
# Built here, not shipped as a binary: it is thirty lines of C and a compiler,
# and a distro that cannot rebuild its own tools cannot claim to be one.
if [ -x /usr/bin/gcc ] || [ -x /usr/bin/cc ]; then
    if ( cd "$LFS" && /usr/bin/env -i PATH=/usr/bin:/usr/sbin \
        gcc -O2 -Wall -o "$LFS/usr/bin/wylde-session-probe" \
            "$LFS/tmp/wylde-session-probe.c" \
            $(pkg-config --cflags --libs wayland-client) ) 2>>"$LOGDIR/session-probe.log"; then
        log "  probe built"
    else
        log "  probe did not build (wayland-client missing?) — see $LOGDIR/session-probe.log"
    fi
    rm -f "$LFS/tmp/wylde-session-probe.c"
fi

log "the compositor must exist before the session can start"
[ -x "$LFS/usr/bin/labwc" ] || {
    log "labwc is not installed: wld install labwc"
    exit 1
}

# Both entries are rewritten rather than appended. This script runs on every
# publish, and a service file that grows a duplicate line per run starts the
# desktop once more each time — which looks exactly like a compositor that
# refuses to stay up.
install -d "$LFS/etc/wylde"
SERVICES=$LFS/etc/wylde/services
[ -f "$SERVICES" ] || printf '# One line per service: <name> <command>\n' > "$SERVICES"

log "hotplug has to be running before a session can see a keyboard"
sed -i -E '/^!?udev[[:space:]]/d' "$SERVICES"
cat >> "$SERVICES" << 'UDEV'
# Hotplug. Without a running daemon, libinput enumerates no input devices and
# the compositor refuses to start: nodes in /dev are not the same as devices
# udev knows about.
!udev          /usr/bin/wylde-udev-start
UDEV

log "adding the desktop service"
sed -i -E '/^!?desktop[[:space:]]/d' "$SERVICES"
cat >> "$SERVICES" << 'SERVICE'
# The graphical session, marked one-shot on purpose. init supervises daemons;
# a session is not a daemon. Restarting it behind a person's back leaves
# compositors nobody asked for, each holding a graphics port, and the next
# attempt fails for reasons that have nothing to do with the desktop.
!desktop        /usr/bin/wylde-session
SERVICE

log "services now: $(grep -cE '^!?[[:alnum:]]+[[:space:]]' "$SERVICES") entries"

# nothing above needs a recompile, but the file list has to be honest
log "done: session installed at $LFS/usr/bin/wylde-session"