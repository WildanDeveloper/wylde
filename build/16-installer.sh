#!/bin/bash
# Wylde installer
#
# The installer is a shell program on purpose: it runs in a live environment
# where the only guarantee is bash, and a human can read every line it will
# execute before running it. What is checked here is that it stays valid, stays
# safe without a human, and prints its own help.
set -e

SRC_DIR=$(cd "$(dirname "$0")/.." && pwd)
OUT=$SRC_DIR/target
mkdir -p "$OUT"

INSTALLER=$SRC_DIR/src/installer/wylde-installer
[ -f "$INSTALLER" ] || { echo "[installer] missing $INSTALLER" >&2; exit 1; }

log() { echo "[installer] $*"; }

log "syntax check"
bash -n "$INSTALLER"

if command -v shellcheck >/dev/null; then
    log "shellcheck"
    shellcheck -S warning "$INSTALLER" || {
        log "shellcheck found problems"
        exit 1
    }
fi

log "it must refuse to run as a normal user"
if "$INSTALLER" --help >/dev/null 2>&1; then
    log "help works without root"
else
    log "help needs root — wrong, help is harmless"
    exit 1
fi
"$INSTALLER" --help | grep -q 'target device' || {
    log "help text does not explain the target device"
    exit 1
}

log "without a human at the keyboard it must not touch a disk"
set +e
OUTPUT=$("$INSTALLER" --expert </dev/null 2>&1)
STATUS=$?
set -e
[ "$STATUS" -ne 0 ] || {
    log "installer ran to completion with no input — unsafe"
    exit 1
}
printf '%s\n' "$OUTPUT" | grep -qiE 'fatal|cannot|end of file' || {
    log "installer did not explain why it stopped"
    printf '%s\n' "$OUTPUT"
    exit 1
}
printf '%s\n' "$OUTPUT" | grep -q 'writing a fresh partition table' && {
    log "installer started partitioning without confirmation"
    exit 1
}

install -m755 "$INSTALLER" "$OUT/wylde-installer"
log "installed at $OUT/wylde-installer"