# NVMeterPro — Reserved for Commercial Modules

This directory is reserved for **closed-source Pro features** that are *not*
distributed under the AGPL-3.0 license that governs the rest of this repository.

**Do not commit proprietary source code here in the public repo.** This folder
is intentionally empty in the public repository so the open-core boundary is
visible from day one.

The mainline build (`swift build`) does **not** depend on this target. Pro
features are loaded dynamically at runtime when the user installs the
commercial build downloaded from <https://nvmeter.app> (placeholder).

See [BUSINESS.md](../../BUSINESS.md) at the repo root for the open-core
boundary policy: which features stay free forever, which are Pro, and how we
commit to never relicensing community-contributed code.
