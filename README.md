# NVMeter

[![CI](https://github.com/hualiu77/NVMeter/actions/workflows/ci.yml/badge.svg)](https://github.com/hualiu77/NVMeter/actions/workflows/ci.yml)
[![License: AGPL v3](https://img.shields.io/badge/License-AGPL_v3-blue.svg)](LICENSE)
[![CLA assistant](https://cla-assistant.io/readme/badge/hualiu77/NVMeter)](https://cla-assistant.io/hualiu77/NVMeter)

A native macOS menu-bar SMART monitor for internal and external NVMe/SATA SSDs.
Free and open source forever for personal use.

> ⚠️ Early scaffold — not yet ready for end users. Bridges DB and CI in place;
> packaged `.app` not yet shipped.

## Why

macOS has no first-party way to see your SSDs' temperature, wear, or remaining
spare. `smartctl` does the heavy lifting but is CLI-only, and most GUI options
on the Mac are closed-source or unmaintained. NVMeter is a thin, native
SwiftUI menu-bar app on top of `smartctl` that:

- Shows the hottest drive's temperature in your menu bar at all times.
- Reads full SMART/NVMe health for internal SSDs **and** external USB / Thunderbolt enclosures.
- Records a local history (SQLite) so you can spot trends.
- Warns you when a drive crosses temperature or wear thresholds — **no cloud, no telemetry**.

## Project values

1. **Personal use is free, forever.** The core monitoring app is AGPL-3.0 and will not be moved behind a paywall. See [BUSINESS.md](BUSINESS.md) for the open-core boundary.
2. **The community owns the device-compatibility database.** USB / Thunderbolt bridge-chip pass-through quirks live in a separate **public-domain (CC0)** repository: [NVMeter-drivedb](https://github.com/hualiu77/NVMeter-drivedb). Contributing a new enclosure is one YAML file, no Swift required.
3. **No telemetry, ever, in the open-source build.**

## Status

| Layer | State |
|---|---|
| `smartctl` JSON wrapper | ✅ |
| Health scoring (temperature / wear / spare / media errors) | ✅ |
| SQLite history store (GRDB) | ✅ |
| Menu-bar SwiftUI shell | ✅ scaffold |
| Bridge-DB loader (YAML) | ✅ |
| Notifications + thresholds | ⏳ |
| Long self-test runner UI | ⏳ |
| Signed/notarized `.app` release | ⏳ |
| Pro modules (trends >30d, multi-machine, ML predict) | reserved |

## Building from source

Requirements: macOS 13+, Xcode 15+ / Swift 5.9+, `smartmontools` installed (`brew install smartmontools`).

```bash
git clone https://github.com/hualiu77/NVMeter.git
cd NVMeter
swift build
swift test
swift run NVMeterApp
```

The app shells out to `smartctl` from `/opt/homebrew/bin/smartctl` (Homebrew on Apple Silicon) or `/usr/local/bin/smartctl` (Intel). Released `.app` bundles will embed `smartctl` directly and ship the GPLv2 notice alongside.

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
