import SwiftUI
import NVMeterCore

/// Runs the drive's built-in extended ("long") SMART self-test and shows
/// live progress + a local history of past results. This is the one health
/// check `smartctl` can do that pure monitoring can't: it asks the drive to
/// exercise its own media and report pass/fail.
struct SelfTestView: View {
    @ObservedObject var model: AppModel
    @StateObject private var test = SelfTestModel()

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    if test.device == nil {
                        emptyState
                    } else if test.isRunning {
                        runningCard
                        explanationCard
                    } else if let device = test.device, !device.supportsSelfTest {
                        unsupportedCard
                    } else {
                        explanationCard
                        if let err = test.error {
                            Text(err).font(.caption).foregroundStyle(.red)
                        }
                    }
                    if !test.history.isEmpty {
                        historySection
                    }
                }
                .padding(Theme.Spacing.l)
            }
        }
        .frame(minWidth: 520, minHeight: 460)
        .onAppear(perform: selectInitial)
    }

    // MARK: - Device selection

    private var selectableDevices: [DeviceSnapshot] {
        model.devices.filter { !$0.isBlocked && $0.raw != nil }
    }

    private func selectInitial() {
        if test.device == nil, let first = selectableDevices.first {
            test.select(first)
        }
    }

    private var toolbar: some View {
        HStack(spacing: Theme.Spacing.m) {
            Picker(LR("Drive"), selection: Binding(
                get: { test.device?.devicePath ?? "" },
                set: { path in
                    if let d = selectableDevices.first(where: { $0.devicePath == path }) { test.select(d) }
                }
            )) {
                ForEach(selectableDevices.map(\.devicePath), id: \.self) { path in
                    if let d = selectableDevices.first(where: { $0.devicePath == path }) {
                        Text(d.modelName).tag(path)
                    }
                }
            }
            .frame(minWidth: 220)
            .disabled(test.isRunning)

            Spacer()

            if test.isRunning {
                Button(role: .destructive) { test.abort() } label: { Text(LR("Stop test")) }
            } else {
                Button { test.start() } label: {
                    Label(LR("Start extended test"), systemImage: "stethoscope")
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.Brand.primary)
                .disabled(!test.canRun)
            }
        }
        .padding(Theme.Spacing.m)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "stethoscope").font(.largeTitle).foregroundStyle(.tertiary)
            Text(LR("No SMART-capable drive selected.")).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 40)
    }

    // MARK: - Unsupported

    private var unsupportedCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange).imageScale(.small)
                VStack(alignment: .leading, spacing: 2) {
                    Text(LR("This drive doesn't support self-tests"))
                        .font(.caption.weight(.medium)).foregroundStyle(.primary)
                    Text(LR("Apple's internal SSD (Apple Fabric NVMe) doesn't implement the device self-test command, so there's nothing to run here. Attach an NVMe drive through a Thunderbolt or USB enclosure to use this feature. Live SMART monitoring still works on every drive."))
                        .font(.caption2).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.orange.opacity(0.08)))
    }

    // MARK: - Running

    private var runningCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack {
                Text(LR("Extended self-test running")).font(.headline)
                Spacer()
                if let pct = test.status.completionPercent {
                    Text("\(pct)%").font(.title3.weight(.bold).monospacedDigit())
                        .foregroundStyle(Theme.Brand.primary)
                }
            }
            if let pct = test.status.completionPercent {
                ProgressView(value: Double(pct), total: 100).tint(Theme.Brand.primary)
            } else {
                ProgressView().progressViewStyle(.linear).tint(Theme.Brand.primary)
            }
            HStack(spacing: 10) {
                if let started = test.startedAt {
                    Label {
                        Text(started, format: .relative(presentation: .named))
                    } icon: { Image(systemName: "clock") }
                }
                if let est = test.estimatedMinutes {
                    Text(String(localized: "Estimated ~\(est) min total", bundle: localizationBundle))
                }
            }
            .font(.caption2).foregroundStyle(.secondary)

            Text(LR("The test runs on the drive itself — you can keep using your Mac, sleep it, or even quit NVMeter. Re-open this window to check progress."))
                .font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: Theme.Layout.cardRadius))
    }

    // MARK: - Explanation

    private var explanationCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "info.circle").foregroundStyle(.secondary).imageScale(.small)
                Text(LR("What the extended test does")).font(.subheadline.weight(.semibold))
            }
            Text(LR("The drive scans its entire media surface and read/verifies it, then reports pass or fail. It's the most thorough check short of a full surface scan, and it's read-only — your data is not touched. Expect minutes on a healthy NVMe SSD, longer on large or mechanical drives."))
                .font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let est = test.estimatedMinutes, !test.isRunning {
                Text(String(localized: "This drive estimates about \(est) minutes for the extended test.", bundle: localizationBundle))
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.04)))
    }

    // MARK: - History

    private var historySection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text(LR("Past results")).font(.headline)
            VStack(spacing: 0) {
                ForEach(Array(test.history.enumerated()), id: \.element.id) { index, record in
                    historyRow(record)
                        .padding(.vertical, 8)
                        .padding(.horizontal, Theme.Spacing.m)
                        .background(index.isMultiple(of: 2) ? Color.primary.opacity(0.03) : Color.clear)
                }
            }
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: Theme.Layout.cardRadius))
        }
    }

    private func historyRow(_ record: SelfTestRecord) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.m) {
            Image(systemName: resultIcon(record.passed))
                .foregroundStyle(resultColor(record.passed))
                .imageScale(.medium)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(record.resultLabel).font(.callout)
                HStack(spacing: 6) {
                    Text(record.startedAt, format: .dateTime.year().month().day().hour().minute())
                    if let h = record.lifetimeHours {
                        Text("·").foregroundStyle(.tertiary)
                        Text(String(localized: "at \(h) power-on hours", bundle: localizationBundle))
                    }
                }
                .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Text(resultLabel(record.passed))
                .font(.caption.weight(.medium))
                .foregroundStyle(resultColor(record.passed))
        }
    }

    private func resultIcon(_ passed: Bool?) -> String {
        switch passed {
        case .some(true):  "checkmark.seal.fill"
        case .some(false): "xmark.seal.fill"
        case .none:        "exclamationmark.triangle.fill"
        }
    }

    private func resultColor(_ passed: Bool?) -> Color {
        switch passed {
        case .some(true):  .green
        case .some(false): .red
        case .none:        .orange
        }
    }

    private func resultLabel(_ passed: Bool?) -> String {
        switch passed {
        case .some(true):  L("Passed")
        case .some(false): L("Failed")
        case .none:        L("Aborted")
        }
    }
}
