#!/usr/bin/env bash
# Build a distributable .dmg from a signed/stapled .app.
# Usage: bash scripts/make-dmg.sh <NVMeter.app> <output.dmg>
set -euo pipefail

APP="${1:?missing app path}"
OUT="${2:?missing dmg output path}"
NAME="$(basename "$APP" .app)"

STAGING="$(mktemp -d)"
trap "rm -rf $STAGING" EXIT

cp -R "$APP" "$STAGING/"
# Drag-target affordance: an Applications alias in the DMG window.
ln -s /Applications "$STAGING/Applications"

# Use UDZO (zlib compression). hdiutil is the canonical Apple tool.
rm -f "$OUT"
hdiutil create -volname "$NAME" \
               -srcfolder "$STAGING" \
               -ov \
               -format UDZO \
               -fs HFS+ \
               "$OUT" >/dev/null

# Sign the DMG itself so Gatekeeper trusts the container.
SIGN_ID="${SIGN_ID:-Developer ID Application: Hua Liu (38H257A346)}"
if [[ "${SKIP_SIGN:-0}" != "1" ]]; then
    codesign --force --timestamp --sign "$SIGN_ID" "$OUT"
fi

echo "OK · $OUT ($(du -sh "$OUT" | cut -f1))"
