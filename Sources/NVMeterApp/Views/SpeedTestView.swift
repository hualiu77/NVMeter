import SwiftUI
import Charts
import NVMeterCore

struct SpeedTestView: View {
    @ObservedObject var model: AppModel
    @StateObject private var speed = SpeedTestModel()

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            ScrollView {
                VStack(spacing: Theme.Spacing.l) {
                    writeCostNotice
                    if speed.isRunning {
                        liveGauge
                    }
                    if !speed.liveSamples.isEmpty {
                        overlayChartCard
                    }
                    if let run = speed.lastRun, !speed.isRunning {
                        resultsCard(run.results)
                        slowdownAnalysis(run)
                    } else if !speed.isRunning && speed.liveSamples.isEmpty {
                        idleHint
                    }
                    if let err = speed.error {
                        Text(err).font(.caption).foregroundStyle(.red)
                    }
                    if !speed.isRunning {
                        historySection
                    }
                }
                .padding(Theme.Spacing.l)
            }
        }
        .frame(minWidth: 560, minHeight: 560)
        .onAppear(perform: selectInitial)
    }

    // MARK: - Toolbar

    private var selectableDevices: [DeviceSnapshot] {
        model.devices.filter { !$0.facts.mountPoints.isEmpty || $0.facts.bus == .internalNVMe }
    }

    private func selectInitial() {
        if speed.device == nil, let first = selectableDevices.first {
            speed.select(first)
        }
    }

    private var toolbar: some View {
        HStack(spacing: Theme.Spacing.m) {
            Picker(LR("Drive"), selection: Binding(
                get: { speed.device?.devicePath ?? "" },
                set: { path in
                    if let d = selectableDevices.first(where: { $0.devicePath == path }) { speed.select(d) }
                }
            )) {
                ForEach(selectableDevices.map(\.devicePath), id: \.self) { path in
                    if let d = selectableDevices.first(where: { $0.devicePath == path }) {
                        Text("\(d.modelName)").tag(path)
                    }
                }
            }
            .frame(minWidth: 200)
            .disabled(speed.isRunning)

            Picker(LR("Test size"), selection: $speed.selectedSize) {
                ForEach(SpeedTestModel.Size.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(width: 220)
            .disabled(speed.isRunning)

            Spacer()

            if speed.isRunning {
                Button(role: .destructive) { speed.cancel() } label: { Text(LR("Stop")) }
            } else {
                Button { speed.start() } label: {
                    Label(LR("Run test"), systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.Brand.primary)
                .disabled(!speed.canRun)
            }
        }
        .padding(Theme.Spacing.m)
    }

    // MARK: - Write-cost notice (honesty)

    private var writeCostNotice: some View {
        HStack(spacing: 6) {
            Image(systemName: "pencil.and.outline").imageScale(.small).foregroundStyle(.secondary)
            Text(String(localized: "This test writes about \(DeviceFacts.humanBytes(speed.estimatedWriteBytes)) to the drive. Larger sizes reveal SLC-cache and thermal slowdowns but add more wear.", bundle: localizationBundle))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.04)))
    }

    private var idleHint: some View {
        VStack(spacing: 8) {
            Image(systemName: "speedometer").font(.largeTitle).foregroundStyle(.tertiary)
            Text(LR("Pick a drive and size, then Run test.")).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 40)
    }

    // MARK: - Live gauge

    private var liveGauge: some View {
        VStack(spacing: Theme.Spacing.s) {
            HStack {
                Text(speed.currentProfileLabel ?? "—").font(.headline)
                Text(speed.currentIsRead ? LR("Read") : LR("Write"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(speed.currentIsRead ? Theme.Brand.primary : .orange)
                Spacer()
                if let t = speed.liveTemp {
                    Label("\(t)°C", systemImage: "thermometer").font(.callout).foregroundStyle(.red)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(String(format: "%.0f", speed.liveMBps))
                    .font(.system(size: 56, weight: .bold).monospacedDigit())
                    .foregroundStyle(Theme.Brand.primary)
                Text("MB/s").font(.title3).foregroundStyle(.secondary)
            }
            ProgressView(value: speed.fraction)
                .tint(Theme.Brand.primary)
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: Theme.Layout.cardRadius))
    }

    // MARK: - Overlay chart (the differentiator: speed + temperature)

    private var overlayChartCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(LR("Speed & temperature")).font(.headline)
                Spacer()
                HStack(spacing: 12) {
                    legendDot(Theme.Brand.primary, LR("Speed"))
                    legendDot(.red, LR("Temp"))
                }
                .font(.caption2).foregroundStyle(.secondary)
            }
            speedTempChart(speed.liveSamples, height: 200)
        }
        .padding(Theme.Spacing.m)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: Theme.Layout.cardRadius))
    }

    /// Speed line+area on the left axis, temperature dashed line mapped onto
    /// the same plot with a temperature scale on the right axis. Shared by
    /// the live view and every history card.
    private func speedTempChart(_ samples: [SpeedSample], height: CGFloat) -> some View {
        let maxSpeed = max(1, samples.map(\.mbPerSec).max() ?? 1)
        let tempTicks: [Double] = [30, 50, 70, 90]
        func tempToSpeed(_ t: Double) -> Double { t / 100.0 * maxSpeed }

        return Chart {
            ForEach(Array(samples.enumerated()), id: \.offset) { _, s in
                AreaMark(x: .value("t", s.elapsed), y: .value("MB/s", s.mbPerSec))
                    .foregroundStyle(Theme.Brand.primary.opacity(0.12))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("t", s.elapsed), y: .value("MB/s", s.mbPerSec))
                    .foregroundStyle(Theme.Brand.primary)
                    .interpolationMethod(.monotone)
                    .lineStyle(.init(lineWidth: 1.6))
            }
            ForEach(Array(samples.enumerated()), id: \.offset) { _, s in
                if let t = s.temperatureC {
                    LineMark(
                        x: .value("t", s.elapsed),
                        y: .value("temp", tempToSpeed(Double(t))),
                        series: .value("series", "temp")
                    )
                    .foregroundStyle(.red)
                    .interpolationMethod(.monotone)
                    .lineStyle(.init(lineWidth: 1.4, dash: [4, 3]))
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading)
            AxisMarks(position: .trailing, values: tempTicks.map(tempToSpeed)) { value in
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text("\(Int((v / maxSpeed) * 100))°")
                    }
                }
                AxisTick()
            }
        }
        .chartXAxis { AxisMarks(values: .automatic(desiredCount: 5)) }
        .frame(height: height)
    }

    private func legendDot(_ color: Color, _ label: LocalizedStringResource) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label)
        }
    }

    // MARK: - History comparison

    @ViewBuilder
    private var historySection: some View {
        if !speed.history.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                Text(LR("Previous runs")).font(.headline)
                ForEach(speed.history.prefix(6), id: \.startedAt) { record in
                    historyCard(record)
                }
            }
        }
    }

    private func historyCard(_ record: SpeedRunRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(record.startedAt, format: .dateTime.month().day().hour().minute())
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if let r = record.headlineRead, let w = record.headlineWrite {
                    Text(String(localized: "Read \(Int(r)) · Write \(Int(w)) MB/s", bundle: localizationBundle))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            speedTempChart(record.samples, height: 120)
        }
        .padding(Theme.Spacing.m)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: Theme.Layout.cardRadius))
    }

    // MARK: - Results bars (CrystalDiskMark style)

    private func resultsCard(_ results: [ProfileResult]) -> some View {
        let maxVal = max(1, results.map(\.mbPerSec).max() ?? 1)
        // Preserve suite order; group read+write under each label.
        var order: [String] = []
        for r in results where !order.contains(r.label) { order.append(r.label) }

        return VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text(LR("Results")).font(.headline)
            ForEach(order, id: \.self) { label in
                let read = results.first { $0.label == label && $0.isRead }
                let write = results.first { $0.label == label && !$0.isRead }
                VStack(alignment: .leading, spacing: 6) {
                    Text(label).font(.subheadline.weight(.semibold))
                    if let r = read { bar(LR("Read"), r.mbPerSec, maxVal, Theme.Brand.primary) }
                    if let w = write { bar(LR("Write"), w.mbPerSec, maxVal, .orange) }
                }
            }
        }
        .padding(Theme.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: Theme.Layout.cardRadius))
    }

    private func bar(_ tag: LocalizedStringResource, _ value: Double, _ maxValue: Double, _ color: Color) -> some View {
        HStack(spacing: Theme.Spacing.s) {
            Text(tag).font(.caption).foregroundStyle(.secondary).frame(width: 38, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(color.opacity(0.12))
                    Capsule().fill(color).frame(width: max(3, geo.size.width * (value / maxValue)))
                }
            }
            .frame(height: 18)
            Text(String(format: "%.0f", value))
                .font(.callout.monospacedDigit().weight(.medium))
                .frame(width: 70, alignment: .trailing)
        }
    }

    // MARK: - Slowdown analysis (only NVMeter can tell this story)

    @ViewBuilder
    private func slowdownAnalysis(_ run: SpeedTestRun) -> some View {
        // Look at the sequential write samples — the longest sustained load.
        let seqWrite = run.samples.filter { $0.profileID.hasPrefix("seq1m") && !$0.isRead && $0.mbPerSec > 0 }
        if seqWrite.count >= 4 {
            let peak = seqWrite.map(\.mbPerSec).max() ?? 0
            let tail = seqWrite.suffix(max(1, seqWrite.count / 4))
            let tailAvg = tail.map(\.mbPerSec).reduce(0, +) / Double(tail.count)
            let drop = peak > 0 ? (peak - tailAvg) / peak : 0
            let maxTemp = run.samples.compactMap(\.temperatureC).max()

            if drop > 0.20 {
                let reason: LocalizedStringResource = {
                    if let mt = maxTemp, mt >= 70 {
                        return LR("The drive reached \(mt)°C — thermal throttling is the likely cause.")
                    }
                    return LR("Temperature stayed moderate, so this is most likely the SLC write cache filling up.")
                }()
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).imageScale(.small)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "Sustained write speed dropped \(Int(drop * 100))% from its peak.", bundle: localizationBundle))
                            .font(.caption.weight(.medium))
                        Text(reason).font(.caption2).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.orange.opacity(0.08)))
            }
        }
    }
}
