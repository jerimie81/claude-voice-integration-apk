#!/usr/bin/env bash
# Build the claude-voice-server Debian package.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PKG_NAME="claude-voice-server"
VERSION="1.0.0"
STAGING="$SCRIPT_DIR/staging"
OUT_DIR="${1:-$SCRIPT_DIR/../../debs}"

mkdir -p "$OUT_DIR"

# Build staging tree
rm -rf "$STAGING"
cp -r "$SCRIPT_DIR/files" "$STAGING"
cp -r "$SCRIPT_DIR/DEBIAN" "$STAGING/DEBIAN"
chmod 755 "$STAGING/DEBIAN/postinst"
chmod 755 "$STAGING/opt/claude-voice-server/run-server.sh"

# Build .deb
dpkg-deb --build "$STAGING" "$OUT_DIR/${PKG_NAME}_${VERSION}_all.deb"
echo "[OK] Built: $OUT_DIR/${PKG_NAME}_${VERSION}_all.deb"
