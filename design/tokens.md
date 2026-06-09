# NVMeter Visual Tokens

Friendly-foundation + engineering accents. Lean on native macOS materials —
do not invent layouts that fight the system. Single brand color, system
semantic colors for health states.

## Brand

| Token | Value | Use |
|---|---|---|
| `brand.primary` | `#2BB1B8` (Apple `.cyan` adjacent) | Wordmark, logo fill, single accent stroke. Never for health states. |
| `brand.primary.dim` | `#1F8388` | Hover / pressed accents only |

Why cyan: distinct from green/yellow/red health colors, reads as
"diagnostic/medical" without being literal blue (Apple-default everything).

## Health states (system colors only)

| Token | macOS color | When |
|---|---|---|
| `health.good` | `.green` | All metrics within normal range |
| `health.warning` | `.orange` | Temp 60–79°C, wear ≥70%, spare near threshold |
| `health.critical` | `.red` | Temp ≥80°C, wear ≥90%, SMART overall FAILED, media errors |
| `health.unknown` | `.secondary` | SMART blocked / not yet read |
| `health.blocked` | `.orange` (info, not error) | macOS-blocked USB-SATA — friendly amber, not red |

## Typography (SwiftUI text styles, no custom fonts)

| Where | Style | Weight |
|---|---|---|
| Wordmark in header | `.title3` | `.bold` |
| Device model name | `.subheadline` | `.semibold` |
| Device path (`/dev/disk0`) | `.caption` monospaced | `.regular`, `.secondary` |
| Big metric (temp °C) | `.title2` monospaced digits | `.semibold` |
| Metric label ("Wear", "Spare") | `.caption2` | `.regular`, `.secondary` |
| Reason lines | `.caption2` | `.regular`, `.secondary` |

Always pass `.monospacedDigit()` to numbers so they don't dance as values
update.

## Spacing (8-pt grid)

| Token | pt | Use |
|---|---|---|
| `xs` | 4 | Inline between icon and label |
| `s` | 8 | Inside-card vertical rhythm |
| `m` | 12 | Between cards |
| `l` | 16 | Window padding |

## Window

| Attribute | Value |
|---|---|
| Width | 360pt fixed |
| Max height | 600pt (scroll past it) |
| Background | `.regularMaterial` (system blur, auto light/dark) |
| Card background | `.thinMaterial` on a `.regularMaterial` window — slight depth |
| Card radius | 10pt |
| Card padding | 12pt all sides |

## Menu bar

- Title: SF Symbol template image **or** icon + `35°` text, user-toggleable.
- Default ON (showing temperature) — the whole reason people install this.
- Symbol when no devices yet: `thermometer.medium`.
- Symbol when degraded: `exclamationmark.triangle.fill` (system orange via NSStatusItem tinting).

## Logo files

| File | Purpose | Format |
|---|---|---|
| `logo/mark.svg` | Standalone mark (M-pin), single brand color | SVG, 64×64 viewBox |
| `logo/mark-mono.svg` | Same shape, single-color template (currentColor) | SVG, 64×64 viewBox |
| `logo/wordmark.svg` | "NVMeter" wordmark with mark replacing the M | SVG, 320×80 viewBox |
| `logo/menubar.svg` | 16×16 simplified template, ≤3 visual elements | SVG, 16×16 viewBox |
| `logo/appicon.svg` | macOS app icon, rounded-square plate + mark | SVG, 1024×1024 viewBox |

All SVGs must:
- Be plain shapes (no embedded fonts; outline any text)
- Use `currentColor` in the mono variants so SwiftUI's `.foregroundStyle()` works
- Use `viewBox` only, no fixed width/height
