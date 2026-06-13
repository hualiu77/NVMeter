# NVMeter

English | **[简体中文](README.zh-CN.md)**

[![Download](https://img.shields.io/github/v/release/hualiu77/NVMeter?label=Download%20DMG&style=for-the-badge&color=2BB1B8&logo=apple)](https://github.com/hualiu77/NVMeter/releases/latest)
&nbsp;
[![CI](https://github.com/hualiu77/NVMeter/actions/workflows/ci.yml/badge.svg)](https://github.com/hualiu77/NVMeter/actions/workflows/ci.yml)
[![License: AGPL v3](https://img.shields.io/badge/License-AGPL_v3-blue.svg)](LICENSE)
[![CLA assistant](https://cla-assistant.io/readme/badge/hualiu77/NVMeter)](https://cla-assistant.io/hualiu77/NVMeter)
[![Notarized](https://img.shields.io/badge/Notarized-Apple-success?logo=apple)](#install)

A native macOS menu-bar SMART monitor for internal and external NVMe/SATA SSDs.
Free and open source forever for personal use.

Website: **https://hualiu77.github.io/NVMeter/**

## Install

1. Download the latest [**NVMeter-x.y.z.dmg**](https://github.com/hualiu77/NVMeter/releases/latest) (signed with Developer ID and notarized by Apple — no Gatekeeper warnings).
2. Open the DMG, drag **NVMeter.app** into the **Applications** folder.
3. Launch from Spotlight (`⌘+Space → NVMeter`). A chip icon appears in your menu bar.

Requires **macOS 14 Sonoma or later** on an **Apple Silicon Mac**.

## Why

macOS has no first-party way to see your SSDs' temperature, wear, or remaining
spare. `smartctl` does the heavy lifting but is CLI-only, and most GUI options
on the Mac are closed-source or unmaintained. NVMeter is a thin, native
SwiftUI menu-bar app on top of `smartctl` that:

- Shows the hottest drive's temperature in your menu bar at all times.
- Reads full SMART/NVMe health for internal SSDs **and** external USB / Thunderbolt enclosures.
- Records a local history (SQLite) so you can spot trends.
- Warns you when a drive crosses temperature or wear thresholds — **no cloud, no telemetry**.
- Benchmarks read/write speed with a **temperature overlay** — the one thing pure speed tools can't do — so it can explain SLC-cache vs thermal slowdowns.

## Project values

1. **Personal use is free, forever.** The core monitoring app is AGPL-3.0 and will not be moved behind a paywall. See [BUSINESS.md](BUSINESS.md) for the open-core boundary.
2. **The community owns the device-compatibility database.** USB / Thunderbolt bridge-chip pass-through quirks live in a separate **public-domain (CC0)** repository: [NVMeter-drivedb](https://github.com/hualiu77/NVMeter-drivedb). Contributing a new enclosure is one YAML file, no Swift required.
3. **No telemetry, ever, in the open-source build.**

## Status

Current release: **[v0.3.0](https://github.com/hualiu77/NVMeter/releases/latest)** — disk speed test with temperature overlay.

| Layer | State |
|---|---|
| `smartctl` JSON wrapper | ✅ |
| Health scoring (temperature / wear / spare / media errors) | ✅ |
| SQLite history store (GRDB) | ✅ |
| Menu-bar SwiftUI shell with brand mark | ✅ |
| Per-drive capacity bar, brand, connection, dock-name detection | ✅ |
| Full SMART detail view (pre-fail / life-span groups) | ✅ |
| 24h / 7d / 30d trend charts (Swift Charts) | ✅ |
| Threshold-based system notifications | ✅ |
| **Disk speed test** (CrystalDiskMark-style) with temperature overlay + link-ceiling comparison | ✅ |
| Speed-drop attribution (thermal-throttle vs SLC-cache, read off the temperature track) | ✅ |
| Wear-trend projection (local linear extrapolation of stored history → "reaches N% around …") | ✅ |
| Configurable menu-bar metric (temperature / wear / health dot) | ✅ |
| Bridge-DB loader + runtime `-d` auto-retry | ✅ |
| Sparkle auto-update | ✅ |
| Signed (Developer ID) + Apple-notarized `.app` + `.dmg` | ✅ |
| **Extended (long) self-test runner** with live progress, result history + completion notification | ✅ |
| Pro modules (multi-machine, ML predict, cloud sync) | reserved |

## Known limitations

NVMeter is honest about what `smartctl` can and cannot do on macOS. Setting
expectations up front so you don't install it and feel cheated:

### ✅ Fully supported

- **Internal Apple SSD** (NVMe via Apple Fabric) — temperature, wear, spare, media errors.
- **Thunderbolt 3 / 4 / 5 NVMe enclosures and docks** — read as native PCIe, no quirk needed. Full NVMe smart-log.
- **USB-NVMe enclosures with cooperative bridge chips** (JMicron JMS583, ASMedia ASM2362, Realtek RTL9210, etc.) — typically work via `-d sat,16` or vendor-specific `-d` flags. See [`NVMeter-drivedb`](https://github.com/hualiu77/NVMeter-drivedb) for verified entries.

### ⚠️ Often blocked: USB-SATA enclosures and external HDDs

Many USB-SATA bridge chips refuse to pass SMART commands through on macOS,
returning `Operation not supported by device` regardless of which `-d`
argument is tried. This is **not** a NVMeter bug — it's a fundamental
limitation of macOS's user-space SCSI stack.

For context: Linux's kernel includes a generic SAT (SCSI/ATA Translation)
layer in `sd_mod` that handles most USB-SATA bridges transparently. macOS
has no equivalent. Closed-source tools like DriveDx work around this by
shipping their own `SATSMARTDriver` kernel extension, but kext requirements
on Apple Silicon (SIP disabled, Reduced Security boot, etc.) make this a
non-starter for an open, frictionless install. NVMeter does **not** ship a
kext.

Known macOS-blocked families include WD Elements / My Passport (`1058:25a3`
and relatives), most older Seagate Backup Plus, and various no-brand
USB-SATA enclosures. When NVMeter detects one, it shows a friendly
"SMART pass-through blocked by macOS — try an NVMe enclosure or use Linux"
message instead of a scary error.

### ⛔ Not supported

- **CD/DVD drives, MMC/SD card readers, RAID volumes.** Out of scope.
- **Drives behind hardware RAID controllers** that hide the underlying disks.
- **Disk images** (`disk4`, `disk5` style synthetic devices) — they have no underlying physical drive to query.

## Building from source

Requirements: macOS 14+ (Sonoma), Xcode 15+ / Swift 5.9+, `smartmontools` installed (`brew install smartmontools`).

```bash
git clone https://github.com/hualiu77/NVMeter.git
cd NVMeter
swift build
swift test
swift run NVMeterApp        # for development; shells out to /opt/homebrew/bin/smartctl
```

To build a signed, notarized `.app` + `.dmg` like the one on the Releases page:

```bash
# One-time keychain setup (creates an app-specific password on appleid.apple.com first):
xcrun notarytool store-credentials nvmeter-notarize \
    --apple-id "<your-apple-id>" --team-id <your-team-id>

# Then any release build is a single command:
NOTARIZE=1 MAKE_DMG=1 bash scripts/build-app.sh
```

This produces `build/NVMeter.app`, `build/NVMeter-<ver>.zip`, and `build/NVMeter-<ver>.dmg`, all signed with your Developer ID and stapled with Apple's notarization ticket. See `scripts/build-app.sh` for the full pipeline.

## Contributing

- **Adding support for a new USB/Thunderbolt enclosure?** Send a YAML PR to [NVMeter-drivedb](https://github.com/hualiu77/NVMeter-drivedb) — no Swift required. See its `CONTRIBUTING.md`.
- **Code changes?** See [CONTRIBUTING.md](CONTRIBUTING.md). All non-trivial PRs require a signed [CLA](CLA.md) so we can keep the open-core licensing options open without ever changing what's free.

## License

NVMeter is licensed under **AGPL-3.0-or-later** — see [LICENSE](LICENSE).

NVMeter embeds and depends on **smartmontools** (`smartctl`), licensed under
**GPL-2.0-or-later**. See [NOTICE](NOTICE) for full attribution and how to obtain
the corresponding source code.

This program is distributed in the hope that it will be useful, but
**WITHOUT ANY WARRANTY**; without even the implied warranty of MERCHANTABILITY
or FITNESS FOR A PARTICULAR PURPOSE. **NVMeter is not a substitute for backups.**
