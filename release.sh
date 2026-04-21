#!/usr/bin/env bash
# Build all release artifacts into dist/ and print the gh release command.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
VERSION="1.0.0"
DIST="$ROOT/dist"

mkdir -p "$DIST"

echo "=== Building Android APK ==="
cd "$ROOT/android_app"
./gradlew assembleDebug --quiet
APK_SRC="app/build/outputs/apk/debug/app-debug.apk"
cp "$APK_SRC" "$DIST/claude-voice_${VERSION}.apk"
echo "[OK] APK: $DIST/claude-voice_${VERSION}.apk"
cd "$ROOT"

echo ""
echo "=== Building Termux deb ==="
dpkg-deb --build "$ROOT/packages/claude-voice/staging" "$DIST/claude-voice_${VERSION}-1_all.deb"
echo "[OK] Termux deb: $DIST/claude-voice_${VERSION}-1_all.deb"

echo ""
echo "=== Building PC server deb ==="
bash "$ROOT/packages/claude-voice-server/build.sh" "$DIST"

echo ""
echo "=== Copying install.sh ==="
cp "$ROOT/install.sh" "$DIST/install.sh"
echo "[OK] install.sh copied"

echo ""
echo "=== dist/ contents ==="
ls -lh "$DIST"

echo ""
echo "=== To publish, run: ==="
echo "  gh release create v${VERSION} \\"
echo "    $DIST/claude-voice_${VERSION}.apk \\"
echo "    $DIST/claude-voice_${VERSION}-1_all.deb \\"
echo "    $DIST/claude-voice-server_${VERSION}_all.deb \\"
echo "    $DIST/install.sh \\"
echo "    --title \"Claude Voice Integration v${VERSION}\" \\"
echo "    --notes \"See README.md for installation instructions.\""
