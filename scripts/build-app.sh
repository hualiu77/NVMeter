#!/usr/bin/env bash
# Build NVMeter.app from scratch: release binary, embed smartctl, write
# Info.plist with current version, copy AppIcon, code-sign with hardened
# runtime + entitlements, and emit a versioned .zip ready for notarization.
#
# Run from repo root:    bash scripts/build-app.sh
# Override version:      VERSION=0.2.0 bash scripts/build-app.sh
#
# Env knobs:
#   SIGN_ID    — Developer ID Application certificate name
#   VERSION    — short version string (e.g. 0.1.0)
#   BUILD_NUM  — bundle build number (default: git rev-count)
#   SKIP_SIGN  — set to 1 to produce an unsigned .app for local testing

set -euo pipefail

# ── Config ────────────────────────────────────────────────────────────────
SIGN_ID="${SIGN_ID:-Developer ID Application: Hua Liu (38H257A346)}"
VERSION="${VERSION:-0.1.0}"
BUILD_NUM="${BUILD_NUM:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
APP_NAME="NVMeter"
BUNDLE_ID="app.nvmeter.NVMeter"
SMARTCTL_SRC="/opt/homebrew/bin/smartctl"

BUILD_DIR="build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"

echo "──────────────────────────────────────────────────────────"
echo " NVMeter $VERSION ($BUILD_NUM)"
echo " Sign:   $SIGN_ID"
echo "──────────────────────────────────────────────────────────"

# ── 1 · Compile release binary ────────────────────────────────────────────
echo "[1/7] swift build --configuration release"
swift build --configuration release -Xswiftc -O -Xswiftc -whole-module-optimization

BIN=".build/release/NVMeterApp"
[[ -f "$BIN" ]] || { echo "build failed: $BIN missing" >&2; exit 1; }

# ── 2 · Verify embedded smartctl exists ───────────────────────────────────
echo "[2/7] verify smartctl source"
if [[ ! -f "$SMARTCTL_SRC" ]]; then
    echo "ERROR: $SMARTCTL_SRC missing. brew install smartmontools" >&2
    exit 1
fi
SMARTCTL_REAL="$(readlink -f "$SMARTCTL_SRC" 2>/dev/null || perl -MCwd -e "print Cwd::abs_path('$SMARTCTL_SRC')")"
echo "       smartctl → $SMARTCTL_REAL"

# ── 3 · Build .app skeleton ───────────────────────────────────────────────
echo "[3/7] assemble $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

# Binary + embedded smartctl
cp "$BIN"           "$APP_DIR/Contents/MacOS/NVMeterApp"
cp "$SMARTCTL_REAL" "$APP_DIR/Contents/MacOS/smartctl"
chmod +x "$APP_DIR/Contents/MacOS/NVMeterApp" "$APP_DIR/Contents/MacOS/smartctl"

# Info.plist (substitute placeholders)
sed -e "s/__SHORT_VERSION__/$VERSION/" \
    -e "s/__BUILD_NUMBER__/$BUILD_NUM/" \
    Resources/Info.plist.tmpl > "$APP_DIR/Contents/Info.plist"
plutil -lint "$APP_DIR/Contents/Info.plist" >/dev/null

# Bundled GPLv2 notice for the embedded smartctl (compliance)
mkdir -p "$APP_DIR/Contents/Resources/licenses"
cat > "$APP_DIR/Contents/Resources/licenses/smartmontools-NOTICE.txt" <<'EOF'
This application bundles an unmodified copy of `smartctl` from the
smartmontools project (https://www.smartmontools.org/), licensed under
the GNU General Public License v2.0 or later. The corresponding source
code is available from the upstream URL above; a copy of GPL-2.0 is
included alongside this file.
EOF
# Fetch GPL-2.0 text if we don't have it locally cached
LICENSE_CACHE="$BUILD_DIR/.gpl-2.0-cache.txt"
if [[ ! -s "$LICENSE_CACHE" ]]; then
    curl -fsSL "https://raw.githubusercontent.com/licenses/license-templates/master/templates/gpl2.txt" \
         -o "$LICENSE_CACHE" 2>/dev/null || true
fi
if [[ -s "$LICENSE_CACHE" ]]; then
    cp "$LICENSE_CACHE" "$APP_DIR/Contents/Resources/licenses/smartmontools-LICENSE.txt"
fi

# ── 4 · Icon ──────────────────────────────────────────────────────────────
echo "[4/7] icon"
# Always re-render: cheap (~1s) and avoids stale color profiles.
swift scripts/render-icns.swift
cp "$BUILD_DIR/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"

# ── 5 · Code sign ─────────────────────────────────────────────────────────
if [[ "${SKIP_SIGN:-0}" == "1" ]]; then
    echo "[5/7] SKIP_SIGN=1 — leaving unsigned"
else
    echo "[5/7] code sign (hardened runtime, embedded smartctl first)"

    # Sign the embedded smartctl FIRST. Nested executables must be signed
    # before the enclosing bundle, otherwise codesign on the bundle errors
    # with 'resource fork, Finder information, or similar detritus'.
    codesign --force --options runtime --timestamp \
             --sign "$SIGN_ID" \
             "$APP_DIR/Contents/MacOS/smartctl"

    # Sign the main binary and the bundle with our entitlements.
    codesign --force --options runtime --timestamp \
             --entitlements Resources/NVMeter.entitlements \
             --sign "$SIGN_ID" \
             "$APP_DIR/Contents/MacOS/NVMeterApp"

    codesign --force --options runtime --timestamp \
             --entitlements Resources/NVMeter.entitlements \
             --sign "$SIGN_ID" \
             "$APP_DIR"

    echo "       verify"
    codesign --verify --deep --strict --verbose=2 "$APP_DIR" 2>&1 | tail -6
fi

# ── 6 · Zip for notarization ──────────────────────────────────────────────
echo "[6/7] zip for notarization"
ZIP="$BUILD_DIR/${APP_NAME}-${VERSION}.zip"
rm -f "$ZIP"
( cd "$BUILD_DIR" && /usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_NAME.app" "$(basename "$ZIP")" )

# ── 7 · Summary ───────────────────────────────────────────────────────────
echo "[7/7] done"
echo
echo "  App:       $APP_DIR"
echo "  Zip:       $ZIP   ($(du -sh "$ZIP" | cut -f1))"
echo
echo "Next steps:"
echo "  • Test locally:      open '$APP_DIR'"
if [[ "${SKIP_SIGN:-0}" != "1" ]]; then
    echo "  • Notarize:          xcrun notarytool submit '$ZIP' \\"
    echo "                          --apple-id <your-apple-id> \\"
    echo "                          --team-id 38H257A346 \\"
    echo "                          --password <app-specific-password> \\"
    echo "                          --wait"
    echo "  • Staple:            xcrun stapler staple '$APP_DIR'"
fi
