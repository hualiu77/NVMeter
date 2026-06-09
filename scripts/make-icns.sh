#!/usr/bin/env bash
# Render design/logo/appicon.svg into an .iconset folder + AppIcon.icns
# using ImageMagick + Apple's iconutil. Run from repo root.
set -euo pipefail

SVG="design/logo/appicon.svg"
OUT_DIR="build/AppIcon.iconset"
ICNS="build/AppIcon.icns"

if ! command -v magick >/dev/null 2>&1; then
    echo "ERROR: ImageMagick not installed. brew install imagemagick" >&2
    exit 1
fi

mkdir -p "$OUT_DIR"
echo "Rendering $SVG into $OUT_DIR ..."

# Apple's required iconset sizes (each @1x and @2x).
# https://developer.apple.com/design/human-interface-guidelines/app-icons
for entry in \
    "16   icon_16x16        " \
    "32   icon_16x16@2x     " \
    "32   icon_32x32        " \
    "64   icon_32x32@2x     " \
    "128  icon_128x128      " \
    "256  icon_128x128@2x   " \
    "256  icon_256x256      " \
    "512  icon_256x256@2x   " \
    "512  icon_512x512      " \
    "1024 icon_512x512@2x   "
do
    read -r size name <<< "$entry"
    # Force sRGB output. ImageMagick with librsvg often produces
    # grayscale+alpha (8-bit color-type=4) PNGs for SVGs whose only
    # color comes from strokes, which makes the resulting icon render
    # as a pure black silhouette in the macOS notification banner.
    # `-colorspace sRGB -define png:color-type=6` forces full RGBA.
    magick -background none -density 600 "$SVG" \
           -resize "${size}x${size}" \
           -colorspace sRGB \
           -define png:color-type=6 \
           "PNG32:$OUT_DIR/${name}.png"
done

echo "Compiling $ICNS ..."
iconutil -c icns "$OUT_DIR" -o "$ICNS"

echo "OK · $ICNS"
ls -lh "$ICNS"
