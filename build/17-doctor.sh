#!/bin/bash
# wylde-doctor — system health and advisor
#
# Built with the host rustc as a static musl binary so the same artifact runs in
# the live environment and on an installed system.
set -e

SRC_DIR=$(cd "$(dirname "$0")/.." && pwd)
OUT=$SRC_DIR/target
LOGDIR=${LOGDIR:-/tmp/wylde-build}
mkdir -p "$OUT" "$LOGDIR"

log() { echo "[doctor] $*"; }

command -v rustup >/dev/null || { log "rustup not found"; exit 1; }
rustup target list --installed | grep -q x86_64-unknown-linux-musl || {
    log "adding the musl target"
    rustup target add x86_64-unknown-linux-musl
}

cd "$SRC_DIR/src/doctor"
log "running the unit tests"
cargo test --quiet 2>&1 | tee "$LOGDIR/doctor-test.log"

log "building the release binary"
cargo build --release --target x86_64-unknown-linux-musl 2>&1 | tee "$LOGDIR/doctor-build.log"

install -m755 target/x86_64-unknown-linux-musl/release/wylde-doctor "$OUT/wylde-doctor"
log "built $(du -h "$OUT/wylde-doctor" | cut -f1) at $OUT/wylde-doctor"