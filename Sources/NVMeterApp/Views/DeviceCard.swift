import SwiftUI
import NVMeterCore

struct DeviceSnapshot: Identifiable {
    let id = UUID()
    let modelName: String
    let devicePath: String
    let temperatureC: Int?
    let percentageUsed: Int?
    let level: HealthLevel
    let reasons: [String]
    let facts: DeviceFacts
    let isBlocked: Bool

    init(report: DeviceReport) {
        switch report {
        case .healthy(let info, let assessment, let facts):
            self.modelName = info.model_name ?? facts.modelHint ?? "Unknown device"
            self.devicePath = info.device.name
            self.temperatureC = info.temperature?.current
                ?? info.nvme_smart_health_information_log?.temperature
            self.percentageUsed = info.nvme_smart_health_information_log?.percentage_used
            self.level = assessment.level
            self.reasons = assessment.reasons
            self.facts = facts
            self.isBlocked = false
        case .blocked(let path, let facts):
            self.modelName = facts.modelHint ?? "External drive"
            self.devicePath = path
            self.temperatureC = nil
            self.percentageUsed = nil
            self.level = .unknown
            self.reasons = []
            self.facts = facts
            self.isBlocked = true
        }
    }
}

struct DeviceCard: View {
    let snapshot: DeviceSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            header
            subtitle
            if snapshot.facts.usageFraction != nil { capacityBar }
            if !snapshot.isBlocked { metrics }
            else { blockedNotice }
            connectionChip
            if !snapshot.reasons.isEmpty { reasonsBlock }
        }
        .padding(Theme.Layout.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: Theme.Layout.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Layout.cardRadius)
                .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
    }

    // MARK: - Sections

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
            Circle()
                .fill(snapshot.isBlocked ? Color.orange : Theme.color(for: snapshot.level))
                .frame(width: 8, height: 8)
                .offset(y: -1)
            Text(snapshot.modelName)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: Theme.Spacing.s)
            Text(snapshot.devicePath)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        }
    }

    private var subtitle: some View {
        HStack(spacing: 4) {
            if let brand = snapshot.facts.brand {
                Text(brand)
                Text("·").foregroundStyle(.tertiary)
            }
            Text(snapshot.facts.capacityHuman)
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var capacityBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.primary.opacity(0.10))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(usageColor)
                        .frame(width: geo.size.width * (snapshot.facts.usageFraction ?? 0))
                }
            }
            .frame(height: 6)

            HStack {
                if let usage = snapshot.facts.usageHuman {
                    Text(usage)
                }
                Spacer()
                if let frac = snapshot.facts.usageFraction {
                    Text("\(Int(frac * 100))%")
                        .monospacedDigit()
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    private var usageColor: Color {
        let f = snapshot.facts.usageFraction ?? 0
        if f >= 0.90 { return .red }
        if f >= 0.75 { return .orange }
        return Theme.Brand.primary
    }

    private var metrics: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.m) {
            if let t = snapshot.temperatureC {
                metric(value: "\(t)°", unit: "C", label: "Temp", help: helpTemp)
            }
            if let u = snapshot.percentageUsed {
                metric(value: "\(u)", unit: "%", label: "Wear", help: helpWear)
            }
            if let h = snapshot.facts.powerOnHuman {
                let parts = h.split(separator: " ", maxSplits: 1)
                metric(value: String(parts.first ?? ""),
                       unit: String(parts.dropFirst().first ?? ""),
                       label: "Power-on",
                       help: helpPowerOn)
            }
            if let w = snapshot.facts.lifetimeWrittenHuman {
                let parts = w.split(separator: " ", maxSplits: 1)
                metric(value: String(parts.first ?? ""),
                       unit: String(parts.dropFirst().first ?? ""),
                       label: "Written",
                       help: helpWritten)
            }
            Spacer(minLength: 0)
            levelPill
        }
    }

    private func metric(value: String, unit: String, label: String, help: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(value)
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.primary)
                Text(unit)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Text(label)
                .font(.system(size: 9).weight(.medium))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.4)
                .fixedSize()       // don't truncate the label
        }
        .help(help)                 // hover to see the explanation
    }

    // MARK: - Tooltip copy (Apple SSDs report SMART quirkily — call it out)

    private var isAppleInternal: Bool { snapshot.facts.bus == .internalNVMe }

    private var helpTemp: String {
        "Current drive temperature from SMART. Color thresholds are set in Settings → Thresholds."
    }

    private var helpWear: String {
        if isAppleInternal {
            return """
            Apple's NVMe controller reports wear in coarse integer steps and almost always shows 0% even after years of heavy use — Apple does not publish a TBW figure, so the firmware has no reliable denominator to compute against.

            Use the "Written" tile to gauge endurance instead.
            """
        }
        return "SSD's own estimate of NAND endurance used. 0% is brand new; 100% means the drive has reached its manufacturer-rated TBW. Most drives keep working past 100% — the warranty just no longer covers it."
    }

    private var helpPowerOn: String {
        if isAppleInternal {
            return """
            Cumulative time the Apple SSD has been in the active (S0) state.

            Sleep, Power Nap, and shutdown DO NOT count — so on a Mac that's rarely turned off, this number can lag wall-clock time substantially (it tracks "hours actively in use" more than "hours since manufacture").
            """
        }
        return "Cumulative hours the drive has been powered on since manufacture. Shutdown breaks this counter; sleep with the drive still powered does not."
    }

    private var helpWritten: String {
        """
        Total bytes the host has written to NAND since manufacture. Compare against the drive's TBW endurance rating to estimate remaining life — most consumer NVMe drives are rated for 200–1200 TBW per terabyte of capacity.

        On Apple SSDs this is the most reliable longevity signal, since the per-cent "wear" field is unreliable.
        """
    }

    private var levelPill: some View {
        HStack(spacing: 4) {
            Image(systemName: Theme.systemImage(for: snapshot.level))
                .imageScale(.small)
            Text(snapshot.level.rawValue.capitalized)
                .font(.caption.weight(.medium))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .foregroundStyle(Theme.color(for: snapshot.level))
        .background(
            Capsule().fill(Theme.color(for: snapshot.level).opacity(0.15))
        )
    }

    private var blockedNotice: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .imageScale(.small)
            VStack(alignment: .leading, spacing: 2) {
                Text("SMART pass-through blocked by macOS")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                Text("Most USB-SATA & USB-NVMe bridges can't expose SMART on macOS. Capacity and connection still shown.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.orange.opacity(0.08))
        )
    }

    private var connectionChip: some View {
        HStack(spacing: 4) {
            Image(systemName: connectionIcon)
                .imageScale(.small)
            Text(snapshot.facts.connectionLabel)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            Capsule().fill(Color.primary.opacity(0.05))
        )
    }

    private var connectionIcon: String {
        switch snapshot.facts.bus {
        case .internalNVMe: "internaldrive"
        case .thunderbolt:  "bolt.circle"
        case .usb:          "cable.connector"
        case .unknown:      "questionmark.circle"
        }
    }

    private var reasonsBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(snapshot.reasons, id: \.self) { reason in
                HStack(alignment: .top, spacing: 4) {
                    Text("•").foregroundStyle(.secondary)
                    Text(reason)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 2)
    }
}
