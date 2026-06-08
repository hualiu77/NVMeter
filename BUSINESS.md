# Open-Core Boundary — NVMeter

NVMeter is built **open-core**: the application most people will ever need is and
will remain free and open source, while a small set of advanced features may
be offered as a paid Pro build.

This document is a **public, version-controlled commitment**: any change here
requires a PR, and any narrowing of the "free forever" list is treated as a
breaking change to the community's trust.

## Free forever (AGPL-3.0)

These features are guaranteed to remain free and open source. They will not
be removed from the OSS build, gated behind a paywall, or feature-flagged off.

- Read full SMART / NVMe health for any device `smartctl` can talk to.
- Real-time temperature, wear (`percentage_used`), available spare, media errors.
- Menu-bar live indicator with temperature.
- Local history retention (7 days) in SQLite.
- Manual short / extended self-test trigger.
- Open community bridge-chip database (CC0 — separate repo).
- Local notifications when a drive exceeds user-configured thresholds.
- Manual JSON / CSV export of all locally stored data.

## May be Pro (closed-source, optional, paid)

These are *additive* features that go beyond personal use of one machine.
They are independently developed and do **not** subtract anything from the
free build.

- Long-term trend storage and charts (>30 days).
- Cross-machine cloud / iCloud sync.
- Outbound alerting (email, Slack, Webhook, push).
- ML-based failure prediction trained on aggregated SMART telemetry.
- Multi-machine team / MSP dashboards (likely a separate SaaS).
- PDF compliance reports.
- Priority support.

## What we will not do

- We will not add telemetry, ads, or "phone-home" code to the OSS build.
- We will not change the OSS license to something more restrictive.
- We will not take an existing free feature and move it to Pro.
- We will not stop maintaining the OSS build in favor of Pro.

## How licensing makes this possible

- The application is **AGPL-3.0**: anyone may use, modify, and self-host it,
  but anyone who modifies it must publish their changes under the same
  license. This means a competitor cannot fork NVMeter and sell a closed-source
  derivative.
- All contributors sign a [CLA](CLA.md) granting the maintainer the right to
  also distribute the contributed code under a separate commercial license.
  Combined with AGPL on the public side, this is what allows the Pro build
  to exist without violating any contributor's expectations.
- The compatibility database lives in a separate **CC0** repository so it is
  permanently in the public domain, usable by anyone (including competing
  tools), and never the leverage by which we extract money from users.

If you ever see this project drift from the commitments above, please open
an issue. The whole point of writing them down is that we can be held to them.
