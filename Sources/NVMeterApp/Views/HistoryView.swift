import SwiftUI
import Charts
import NVMeterCore

struct HistoryView: View {
    @ObservedObject var model: AppModel
    @State private var selectedDevice: String = ""
    @State private var range: Range = .day
    @State private var samples: [HealthSample] = []
    @State private var isLoading = false

    enum Range: String, CaseIterable, Identifiable {
        case day = "24 h", week = "7 d", month = "30 d"
        var id: String { rawValue }
        var seconds: TimeInterval {
            switch self {
            case .day: 24 * 3600
            case .week: 7 * 24 * 3600
            case .month: 30 * 24 * 3600
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            content
        }
        .frame(minWidth: 640, minHeight: 480)
        .onAppear { selectInitialDevice() }
        .onChange(of: selectedDevice) { _, _ in Task { await load() } }
        .onChange(of: range) { _, _ in Task { await load() } }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: Theme.Spacing.l) {
            Picker(LR("Drive"), selection: $selectedDevice) {
                ForEach(devicePickerOptions, id: \.self) { path in
                    Text(deviceLabel(for: path)).tag(path)
                }
            }
            .frame(minWidth: 200)

            Picker(LR("Range"), selection: $range) {
                ForEach(Range.allCases) { r in
                    Text(r.rawValue).tag(r)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 220)

            Spacer()

            if isLoading {
                ProgressView().controlSize(.small)
            }
            Text(String(localized: "\(filteredSamples.count) samples", bundle: localizationBundle))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(Theme.Spacing.m)
    }

    private var devicePickerOptions: [String] {
        let live = model.devices.filter { !$0.isBlocked }.map(\.devicePath)
        return live.isEmpty ? [""] : live
    }

    private func deviceLabel(for path: String) -> String {
        if let match = model.devices.first(where: { $0.devicePath == path }) {
            return "\(match.modelName) · \(path)"
        }
        return path
    }

    private func selectInitialDevice() {
        if selectedDevice.isEmpty, let first = devicePickerOptions.first {
            selectedDevice = first
            Task { await load() }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        samples = await model.history(devicePath: selectedDevice, limit: 5000)
    }

    private var filteredSamples: [HealthSample] {
        let cutoff = Date().addingTimeInterval(-range.seconds)
        return samples.filter { $0.timestamp >= cutoff }.reversed()
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if selectedDevice.isEmpty {
            empty(L("No drives to chart yet."))
        } else if filteredSamples.isEmpty {
            empty(L("No samples for this range yet — NVMeter polls every 5 minutes."))
        } else {
            ScrollView {
                VStack(spacing: Theme.Spacing.l) {
                    chartSection(
                        title: L("Temperature"),
                        unit: "°C",
                        values: filteredSamples.compactMap { s in s.temperatureC.map { (s.timestamp, Double($0)) } },
                        accent: .red
                    )
                    chartSection(
                        title: L("Wear (NAND % used)"),
                        unit: "%",
                        values: filteredSamples.compactMap { s in s.percentageUsed.map { (s.timestamp, Double($0)) } },
                        accent: .orange
                    )
                    wearProjectionNote
                    chartSection(
                        title: L("Lifetime writes"),
                        unit: "TB",
                        values: filteredSamples.compactMap { s in s.dataUnitsWritten.map { (s.timestamp, Double($0) * 500_000 / 1e12) } },
                        accent: Theme.Brand.primary
                    )
                }
                .padding(Theme.Spacing.l)
            }
        }
    }

    // MARK: - Wear projection (linear extrapolation of locally-stored history)

    /// Uses the FULL retained history (not the visible range) so the line is
    /// fit over as much data as we have.
    @ViewBuilder
    private var wearProjectionNote: some View {
        if let p = WearTrendAnalyzer.analyze(samples: samples) {
            switch p.status {
            case .projected(let date, let perYear):
                projectionRow(
                    icon: "calendar.badge.clock", tint: .orange,
                    headline: String(localized: "At the current rate, wear reaches \(p.target)% around \(date.formatted(.dateTime.year().month())).", bundle: localizationBundle),
                    detail: String(localized: "Now at \(p.currentPercent)%, climbing about \(String(format: "%.1f", perYear))% per year over the last \(Int(p.spanDays)) days. Most drives keep working past \(p.target)% — it's the manufacturer's rated endurance, not a cliff.", bundle: localizationBundle)
                )
            case .flat:
                projectionRow(
                    icon: "checkmark.seal.fill", tint: .green,
                    headline: L("Wear is flat — no measurable NAND endurance used over the recorded history."),
                    detail: String(localized: "Holding at \(p.currentPercent)% across \(Int(p.spanDays)) days. Light enough use that there's nothing to project — or an Apple SSD, which reports wear only in coarse steps (watch lifetime writes instead).", bundle: localizationBundle)
                )
            case .insufficientData:
                EmptyView()    // stay quiet until there's enough history
            }
        }
    }

    private func projectionRow(icon: String, tint: Color, headline: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: icon).foregroundStyle(tint).imageScale(.small)
            VStack(alignment: .leading, spacing: 2) {
                Text(headline).font(.caption.weight(.medium))
                Text(detail).font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Layout.cardRadius).fill(tint == .green ? Color.green.opacity(0.07) : Color.orange.opacity(0.08)))
    }

    private func empty(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.largeTitle).foregroundStyle(.tertiary)
            Text(message).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func chartSection(
        title: String,
        unit: String,
        values: [(Date, Double)],
        accent: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                if let last = values.last {
                    Text(String(format: "%.2f \(unit)", last.1))
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            if values.isEmpty {
                Text(LR("No data for this metric."))
                    .font(.caption).foregroundStyle(.tertiary)
                    .padding(.vertical, 30)
            } else {
                Chart(values, id: \.0) { point in
                    LineMark(x: .value("Time", point.0), y: .value(title, point.1))
                        .foregroundStyle(accent)
                        .interpolationMethod(.monotone)
                    AreaMark(x: .value("Time", point.0), y: .value(title, point.1))
                        .foregroundStyle(accent.opacity(0.12))
                        .interpolationMethod(.monotone)
                }
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 5)) }
                .chartYAxis { AxisMarks(position: .leading) }
                .frame(height: 140)
            }
        }
        .padding(Theme.Spacing.m)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: Theme.Layout.cardRadius))
    }
}
