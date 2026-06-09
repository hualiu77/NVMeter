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

    init(report: DeviceReport) {
        self.modelName = report.info.model_name ?? "Unknown device"
        self.devicePath = report.info.device.name
        self.temperatureC = report.info.temperature?.current
            ?? report.info.nvme_smart_health_information_log?.temperature
        self.percentageUsed = report.info.nvme_smart_health_information_log?.percentage_used
        self.level = report.assessment.level
        self.reasons = report.assessment.reasons
        self.facts = report.facts
    }
}

struct DeviceCard: View {
    let snapshot: DeviceSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            header
            subtitle
            if snapshot.facts.usageFraction != nil { capacityBar }
            metrics
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
                .fill(Theme.color(for: snapshot.level))
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
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.l) {
            if let t = snapshot.temperatureC {
                metric(value: "\(t)°", unit: "C", label: "Temp")
            }
            if let u = snapshot.percentageUsed {
                metric(value: "\(u)", unit: "%", label: "Wear")
            }
            if let h = snapshot.facts.powerOnHuman {
                let parts = h.split(separator: " ", maxSplits: 1)
                metric(value: String(parts.first ?? ""),
                       unit: String(parts.dropFirst().first ?? ""),
                       label: "Power-on")
            }
            Spacer(minLength: 0)
            levelPill
        }
    }

    private func metric(value: String, unit: String, label: String) -> some View {
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
        }
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
