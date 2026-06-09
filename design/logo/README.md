# NVMeter logo assets

Concept: a geometric **M** inside a rounded chip frame with a small
**M.2 key notch** cut from the right edge. Single brand color
`#2BB1B8` (cyan).

| File | Use | Canvas |
|---|---|---|
| `mark.svg` | Primary mark, brand color | 64×64 |
| `mark-mono.svg` | Single-color template (`currentColor`), embed in SwiftUI / docs | 64×64 |
| `menubar.svg` | macOS menu bar template icon, optimized for 16/32px | 16×16 |
| `wordmark.svg` | Mark + "NVMeter" text (for README / website / press) | 320×80 |
| `appicon.svg` | macOS app icon source (dark plate + mark) | 1024×1024 |

## Production export commands

```bash
# Menu bar PNGs (template image: 1× and 2×)
rsvg-convert -w 16 -h 16  menubar.svg > menubar@1x.png
rsvg-convert -w 32 -h 32  menubar.svg > menubar@2x.png

# App icon set (.icns) — all 10 required sizes
for sz in 16 32 64 128 256 512 1024; do
  rsvg-convert -w $sz   -h $sz   appicon.svg > AppIcon-$sz.png
  rsvg-convert -w $((sz*2)) -h $((sz*2)) appicon.svg > AppIcon-${sz}@2x.png
done
iconutil -c icns AppIcon.iconset   # after assembling into a .iconset folder
```

## Outline-on-export

`wordmark.svg` uses live SVG `<text>` with an Apple system-font stack.
Before publishing to a web page or `.png`, convert the text to outlined
paths so it renders identically on machines without SF Pro:

```bash
inkscape wordmark.svg --export-text-to-path --export-plain-svg \
         --export-filename=wordmark-outlined.svg
```

## License

These logo files are © 2026 NVMeter Authors. The repository's AGPL-3.0
license covers the SVG source. The trademark "NVMeter" and the visual
mark itself are **not** licensed by AGPL — see `NOTICE` at repo root.
