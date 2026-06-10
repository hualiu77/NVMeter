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

# ".noindex" suffix keeps Spotlight from indexing the dev build artifact,
# which otherwise shows up in Launchpad/Spotlight as a second NVMeter.app
# next to the real /Applications copy.
BUILD_DIR="build.noindex"
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

# SwiftPM resource bundles (localizations live here). Without this copy
# the app falls back to the dev machine's absolute .build path — works
# on the dev Mac, crashes with fatalError everywhere else.
for bundle in .build/release/*.bundle; do
    [[ -d "$bundle" ]] && cp -R "$bundle" "$APP_DIR/Contents/Resources/"
done

# Sparkle.framework — the binary links it at @rpath, which Package.swift
# points at @executable_path/../Frameworks.
SPARKLE_FW=".build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
[[ -d "$SPARKLE_FW" ]] || { echo "ERROR: Sparkle.framework not found at $SPARKLE_FW" >&2; exit 1; }
mkdir -p "$APP_DIR/Contents/Frameworks"
cp -R "$SPARKLE_FW" "$APP_DIR/Contents/Frameworks/"
ls "$APP_DIR/Contents/Resources/" | grep -q "NVMeter_NVMeterApp.bundle" \
    || { echo "ERROR: resource bundle missing from app" >&2; exit 1; }

# Embed a snapshot of the community bridge database. Runtime lookup order
# is App Support override first, then this bundled copy (BridgeDatabase
# .loadDefault). Build proceeds without it if the sibling repo is absent,
# but warn loudly because blocked-device UX degrades.
DRIVEDB_DIR="${DRIVEDB_DIR:-../NVMeter-drivedb/bridges}"
if [[ -d "$DRIVEDB_DIR" ]]; then
    mkdir -p "$APP_DIR/Contents/Resources/bridges"
    rsync -a --include="*/" --include="*.yaml" --include="*.yml" --exclude="*" \
          "$DRIVEDB_DIR/" "$APP_DIR/Contents/Resources/bridges/"
    echo "       bridges: $(find "$APP_DIR/Contents/Resources/bridges" -name '*.y*ml' | wc -l | tr -d ' ') entries embedded"
else
    echo "WARNING: $DRIVEDB_DIR not found — app ships without bridge DB" >&2
fi

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
    echo "[5/7] code sign (hardened runtime, nested code first)"

    # Sparkle's nested executables must each carry our Developer ID +
    # hardened runtime for notarization. Per Sparkle's documented order:
    # XPC services → Autoupdate → Updater.app → the framework itself.
    FW="$APP_DIR/Contents/Frameworks/Sparkle.framework"
    codesign --force --options runtime --timestamp --sign "$SIGN_ID" \
             "$FW/Versions/B/XPCServices/Downloader.xpc"
    codesign --force --options runtime --timestamp --sign "$SIGN_ID" \
             "$FW/Versions/B/XPCServices/Installer.xpc"
    codesign --force --options runtime --timestamp --sign "$SIGN_ID" \
             "$FW/Versions/B/Autoupdate"
    codesign --force --options runtime --timestamp --sign "$SIGN_ID" \
             "$FW/Versions/B/Updater.app"
    codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$FW"

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

# ── 7 · Notarize + staple (opt-in) ────────────────────────────────────────
if [[ "${NOTARIZE:-0}" == "1" ]]; then
    PROFILE="${KEYCHAIN_PROFILE:-nvmeter-notarize}"
    echo "[7/8] notarize via keychain profile '$PROFILE'"
    xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait 2>&1 | tee "$BUILD_DIR/notarize.log"

    echo "       staple ticket"
    xcrun stapler staple "$APP_DIR"

    # Refresh the zip so it contains the stapled bundle (otherwise users
    # who unzip on a machine without internet will hit the Gatekeeper
    # "verifying" hang on first launch).
    rm -f "$ZIP"
    ( cd "$BUILD_DIR" && /usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_NAME.app" "$(basename "$ZIP")" )
fi

# ── 8 · Optional DMG (notarized + stapled) ────────────────────────────────
if [[ "${MAKE_DMG:-0}" == "1" ]]; then
    DMG="$BUILD_DIR/${APP_NAME}-${VERSION}.dmg"
    echo "[8/8] dmg"
    bash scripts/make-dmg.sh "$APP_DIR" "$DMG"

    if [[ "${NOTARIZE:-0}" == "1" ]]; then
        PROFILE="${KEYCHAIN_PROFILE:-nvmeter-notarize}"
        echo "       notarize dmg via '$PROFILE'"
        xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait 2>&1 | tee "$BUILD_DIR/notarize-dmg.log"
        xcrun stapler staple "$DMG"
    fi
fi

# Strip leftover Finder xattrs from the .app — they can confuse Gatekeeper.
xattr -cr "$APP_DIR" 2>/dev/null || true

# ── 9 · Appcast for Sparkle (opt-in, requires notarized zip) ──────────────
if [[ "${APPCAST:-0}" == "1" ]]; then
    echo "[9/9] generate appcast"
    GENERATE_APPCAST=".build/artifacts/sparkle/Sparkle/bin/generate_appcast"
    [[ -x "$GENERATE_APPCAST" ]] || { echo "ERROR: generate_appcast missing (swift build first)" >&2; exit 1; }

    # generate_appcast scans a directory of update archives, signs each
    # with the EdDSA key from the login keychain, and writes appcast.xml.
    APPCAST_DIR="$BUILD_DIR/appcast"
    mkdir -p "$APPCAST_DIR"
    cp "$ZIP" "$APPCAST_DIR/"

    "$GENERATE_APPCAST" \
        --download-url-prefix "https://github.com/hualiu77/NVMeter/releases/download/v${VERSION}/" \
        --maximum-deltas 0 \
        -o appcast.xml \
        "$APPCAST_DIR"

    echo "       appcast.xml updated — commit it to main so SUFeedURL serves it"
fi

# ── Summary ───────────────────────────────────────────────────────────────
echo
echo "  App:       $APP_DIR"
echo "  Zip:       $ZIP   ($(du -sh "$ZIP" | cut -f1))"
if [[ -f "$BUILD_DIR/${APP_NAME}-${VERSION}.dmg" ]]; then
    echo "  DMG:       $BUILD_DIR/${APP_NAME}-${VERSION}.dmg   ($(du -sh "$BUILD_DIR/${APP_NAME}-${VERSION}.dmg" | cut -f1))"
fi
echo
echo "Next steps:"
echo "  • Test locally:      open '$APP_DIR'"
if [[ "${NOTARIZE:-0}" != "1" && "${SKIP_SIGN:-0}" != "1" ]]; then
    echo "  • Notarize + DMG:    NOTARIZE=1 MAKE_DMG=1 bash scripts/build-app.sh"
fi
