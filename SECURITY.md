# Security policy

NVMeter reads from `/dev/disk*` and shells out to `smartctl`. Although it does
not write to disks, please report security issues responsibly.

## Reporting

Email `security@nvmeter.app` (placeholder) with subject `[NVMeter security]`.
Include:

- Affected version (`swift run NVMeterApp --version` or build SHA)
- macOS version
- Steps to reproduce
- Impact assessment

Please **do not** open a public GitHub issue for security-relevant problems
until we have shipped a fix.

## Disclosure

We aim to confirm within 72 hours, ship a patch within 14 days, and credit
you publicly unless you ask otherwise.

## Out of scope

- Issues caused by a tampered or non-upstream `smartctl` binary.
- Permission prompts (the app requires user authorization to read raw disks).
- Crashes from clearly-malformed external `drivedb` YAML files.
