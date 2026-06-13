# Changelog

All notable changes to NVMeter are documented here. Dates are in UTC.
This project follows [Semantic Versioning](https://semver.org/).

## [0.4.0] — Unreleased (in preparation)

Health-check depth, speed-test insight, and broader external-drive coverage.

### Added

- **Extended (long) self-test runner.** A dedicated window starts the drive's
  built-in `smartctl -t long` self-test, shows live progress, persists a local
  history of past results, and posts a system notification on completion. The
  test runs on the drive itself, so it survives sleep, lid-close, and quitting
  NVMeter — re-opening the window resumes the live progress.
- **Speed-drop attribution.** After a benchmark, NVMeter reads the temperature
  track alongside the throughput curve and tells you *why* sustained write
  speed fell: thermal throttling, SLC/pSLC cache exhaustion, or "held steady"
  when it didn't. When there's no temperature data it says so rather than
  guessing — the one thing pure speed tools can't do.
- **Wear-trend projection.** A local least-squares extrapolation of the stored
  SMART history estimates when NAND wear (`percentage_used`) will reach a
  threshold ("reaches N% around <date>"), shown under the History wear chart.
  Honest "flat" and "not enough data yet" states; no cloud, no model.
- **Configurable menu-bar metric.** Choose what the status item shows:
  temperature (hottest drive), wear (most-worn drive), or a health dot
  (worst assessable drive).
- **USB-SATA `-d` probe ladder.** When the default open and the community
  bridge-database lookup both fail, NVMeter automatically tries every smartctl
  translation mode (`sat`, `sat,16`, `usbjmicron`, `sntrealtek`, …) and uses
  the first that returns real SMART — unlocking cooperative USB bridges with
  no kernel extension. Results are cached; full failures are negatively cached
  and re-probed when a drive is re-attached.
- **Contribution flywheel.** When the probe ladder unlocks an enclosure that
  isn't in the community database yet, the detail view offers a one-click
  GitHub issue pre-filled with the working `-d` flags and the enclosure's USB
  identity, so it can be catalogued for everyone.

### Changed

- Blocked USB-SATA drives now show a concrete next step ("tried every
  translation mode automatically — for SMART, use a Thunderbolt enclosure")
  instead of a bare error.
- The menu-bar **health** dot now reflects only drives NVMeter can actually
  assess; an unreadable USB enclosure (status "unknown") no longer drags the
  dot to white while the real drives are healthy.

### Fixed

- Self-test no longer polls forever on drives that advertise the capability
  but reject the command. NVMeter detects the rejection at start time (e.g.
  `admin opcode 0x14 is not supported`, seen on some budget NVMe SSDs) and
  fails fast with a clear explanation. A grace window also stops cleanly if a
  drive accepts the command but never reports progress or a result.

### Notes

- Localized in English and Simplified Chinese.
- Tested across four real drives: Apple Fabric internal SSD, a Thunderbolt
  NVMe enclosure, and two macOS-blocked USB-SATA enclosures — verifying each
  failure mode is handled gracefully.
- Requires macOS 14 Sonoma or later on Apple Silicon.

## [0.3.0]

- Disk speed test (CrystalDiskMark-style) with a temperature overlay and
  link-ceiling comparison.

## [0.2.x]

- Full SMART detail view, runtime bridge-database `-d` retry, Sparkle
  auto-update, Simplified Chinese localization.
