# Contributing to NVMeter

Thanks for considering a contribution!

## Where does my change belong?

| What you want to do | Where to send it |
|---|---|
| Add support for a USB / Thunderbolt enclosure | [NVMeter-drivedb](https://github.com/REPLACE_ME/NVMeter-drivedb) — one YAML file, **no Swift required** |
| Fix a bug in the app | this repo |
| Add a feature to the app | open an issue first to discuss whether it belongs in the OSS build or is out of scope |
| Add docs | this repo |

## CLA — required for code contributions

We use a Contributor License Agreement so that NVMeter can sustain itself
financially while remaining open source. By signing the CLA:

1. You keep full copyright of your contribution.
2. You grant the NVMeter maintainer the right to redistribute your contribution
   under (a) the project's current AGPL-3.0-or-later license, and
   (b) a separate commercial license, if and when a Pro build exists.
3. You explicitly do **not** grant rights to remove the AGPL-3.0 build, change
   its license to something more restrictive, or strip out free features in
   favor of paid ones. (See [BUSINESS.md](BUSINESS.md) for the open-core
   boundary commitments.)

The full CLA text is in [CLA.md](CLA.md). When you open your first PR, the
[CLA Assistant](https://cla-assistant.io) bot will ask you to sign — one click.

The CLA does **not** apply to one-line typo fixes, doc-only edits, or contributions to
the `NVMeter-drivedb` repository (which is CC0).

## Code style

- Swift formatting: follow Apple's [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/).
- Run `swift test` before pushing.
- Keep the AGPL boundary clean — do **not** put proprietary code in `Sources/NVMeterPro` or anywhere else in this public repo.

## Reporting bugs

Use the GitHub issue templates. For SMART-read bugs, include:

- Mac model + macOS version
- `system_profiler SPNVMeDataType SPUSBDataType SPThunderboltDataType`
- `smartctl --scan`
- `smartctl -a /dev/diskN` (the failing device)
