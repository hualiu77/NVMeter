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

    init(info: SmartctlInfo, assessment: HealthAssessment) {
        self.modelName = info.model_name ?? "Unknown device"
        self.devicePath = info.device.name
        self.temperatureC = info.temperature?.current
            ?? info.nvme_smart_health_information_log?.temperature
        self.percentageUsed = info.nvme_smart_health_information_log?.percentage_used
        self.level = assessment.level
        self.reasons = assessment.reasons
    }

    init(_ pair: (SmartctlInfo, HealthAssessment)) {
        self.init(info: pair.0, assessment: pair.1)
    }
}

struct DeviceCard: View {
    let snapshot: DeviceSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            header
            metrics
            if !snapshot.reasons.isEmpty { reasons }
        }
        .padding(Theme.Layout.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: Theme.Layout.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Layout.cardRadius)
                .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
            Circle()
                .fill(Theme.color(for: snapshot.level))
                .frame(width: 8, height: 8)
                .offset(y: -1)
            Text(snapshot.modelName)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Spacer(minLength: Theme.Spacing.s)
            Text(snapshot.devicePath)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        }
    }

    private var metrics: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.l) {
            if let t = snapshot.temperatureC {
                metric(value: "\(t)°", unit: "C", label: "Temperature")
            }
            if let u = snapshot.percentageUsed {
                metric(value: "\(u)", unit: "%", label: "Wear")
            }
            Spacer(minLength: 0)
            levelPill
        }
    }

    private func metric(value: String, unit: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(value)
                    .font(.title2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.primary)
                Text(unit)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Text(label)
                .font(.caption2)
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

    private var reasons: some View {
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

#Preview {
    VStack(spacing: Theme.Spacing.m) {
        DeviceCard(snapshot: .preview(
            name: "APPLE SSD AP0512Z", path: "/dev/disk0",
            temp: 35, used: 0, level: .good, reasons: []
        ))
        DeviceCard(snapshot: .preview(
            name: "CT1000P3PSSD8", path: "/dev/disk6",
            temp: 73, used: 8, level: .warning,
            reasons: ["Temperature 73°C is high"]
        ))
        DeviceCard(snapshot: .preview(
            name: "Samsung 980 Pro 2TB", path: "/dev/disk7",
            temp: 84, used: 92, level: .critical,
            reasons: ["NAND wear at 92%", "Temperature 84°C is critical"]
        ))
    }
    .padding()
    .frame(width: Theme.Layout.windowWidth)
}

extension DeviceSnapshot {
    static func preview(
        name: String, path: String,
        temp: Int?, used: Int?, level: HealthLevel, reasons: [String]
    ) -> DeviceSnapshot {
        // SwiftUI previews only — bypass the normal init via reflection-free
        // direct field assignment using a small helper init below.
        DeviceSnapshot(
            modelName: name, devicePath: path,
            temperatureC: temp, percentageUsed: used,
            level: level, reasons: reasons
        )
    }

    private init(
        modelName: String, devicePath: String,
        temperatureC: Int?, percentageUsed: Int?,
        level: HealthLevel, reasons: [String]
    ) {
        self.modelName = modelName
        self.devicePath = devicePath
        self.temperatureC = temperatureC
        self.percentageUsed = percentageUsed
        self.level = level
        self.reasons = reasons
    }
}
