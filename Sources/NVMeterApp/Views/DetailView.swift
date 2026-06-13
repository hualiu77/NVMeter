import SwiftUI
import NVMeterCore

/// DriveDx-style full SMART attribute table, minus the theater:
/// no fake Current/Worst/Threshold triples for fields NVMe doesn't
/// threshold — raw value + human conversion + honest status instead.
struct DetailView: View {
    @ObservedObject var model: AppModel
    @State private var selectedPath: String = ""

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            content
        }
        .frame(minWidth: 560, minHeight: 480)
        .onAppear { selectInitial() }
    }

    // MARK: - Device selection

    private var selectableDevices: [DeviceSnapshot] {
        model.devices.filter { !$0.isBlocked && $0.raw != nil }
    }

    private var selected: DeviceSnapshot? {
        selectableDevices.first { $0.devicePath == selectedPath } ?? selectableDevices.first
    }

    private func selectInitial() {
        if selectedPath.isEmpty {
            selectedPath = model.detailRequestPath ?? selectableDevices.first?.devicePath ?? ""
            model.detailRequestPath = nil
        }
    }

    private var toolbar: some View {
        HStack(spacing: Theme.Spacing.m) {
            Picker(LR("Drive"), selection: $selectedPath) {
                ForEach(selectableDevices.map(\.devicePath), id: \.self) { path in
                    if let snap = selectableDevices.first(where: { $0.devicePath == path }) {
                        Text("\(snap.modelName) · \(path)").tag(path)
                    }
                }
            }
            .frame(minWidth: 260)

            Spacer()

            if let last = model.lastUpdated {
                Text(last, format: .relative(presentation: .named))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(Theme.Spacing.m)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if let snap = selected, let health = snap.raw?.nvme_smart_health_information_log {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    header(snap)
                    section(title: L("Pre-fail indicators"),
                            caption: L("Movement here predicts failure — back up immediately if any of these degrade."),
                            rows: preFailRows(snap: snap, h: health))
                    section(title: L("Life-span counters"),
                            caption: L("These grow with normal use; they describe age, not failure."),
                            rows: lifeSpanRows(snap: snap, h: health))
                    errorLogFooter(snap)
                }
                .padding(Theme.Spacing.l)
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "internaldrive")
                    .font(.largeTitle).foregroundStyle(.tertiary)
                Text(LR("No SMART-capable drive selected."))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func header(_ snap: DeviceSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(snap.modelName).font(.title3.weight(.bold))
                Spacer()
                Text(snap.devicePath).font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                if let brand = snap.facts.brand { Text(brand) }
                Text(snap.facts.capacityHuman)
                Text("·").foregroundStyle(.tertiary)
                Text(snap.facts.connectionLabel)
                if let args = snap.facts.workingSmartctlArgs, !args.isEmpty {
                    Text("·").foregroundStyle(.tertiary)
                    Text("smartctl \(args.joined(separator: " "))")
                        .font(.caption.monospaced())
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if snap.facts.argsDiscoveredByProbe, let args = snap.facts.workingSmartctlArgs {
                contributeBanner(snap: snap, args: args)
            }
        }
    }

    /// Shown when NVMeter's probe ladder (not the database) unlocked this
    /// enclosure — invites the user to catalogue it so others get SMART on
    /// the first try.
    private func contributeBanner(snap: DeviceSnapshot, args: [String]) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "lock.open.fill").foregroundStyle(.green).imageScale(.small)
            VStack(alignment: .leading, spacing: 2) {
                Text(LR("NVMeter unlocked this enclosure's SMART by probing — it's not in the community database yet."))
                    .font(.caption2)
                Button {
                    IssueReporter.contribute(for: snap, workingArgs: args)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "paperplane.fill").imageScale(.small)
                        Text(LR("Contribute it to the database"))
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.green)
                }
                .buttonStyle(.plain)
                .help(L("Opens a pre-filled GitHub issue with the working -d flags and your enclosure's USB identity so we can add it to NVMeter-drivedb."))
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.green.opacity(0.08)))
        .padding(.top, 4)
    }

    // MARK: - Rows

    private struct Row: Identifiable {
        let id: String        // stable: the English name
        let name: String
        let rawText: String
        let humanText: String?
        let ok: Bool
    }

    private func preFailRows(snap: DeviceSnapshot, h: SmartctlInfo.NVMeHealth) -> [Row] {
        var rows: [Row] = []
        if let spare = h.available_spare {
            let threshold = h.available_spare_threshold ?? 0
            rows.append(Row(
                id: "spare", name: L("Available spare"),
                rawText: "\(spare)%",
                humanText: String(format: L("threshold %lld%%") as String, threshold),
                ok: spare > threshold
            ))
        }
        if let errs = h.media_errors {
            rows.append(Row(id: "media", name: L("Media & data integrity errors"),
                            rawText: "\(errs)", humanText: nil, ok: errs == 0))
        }
        if let logEntries = h.num_err_log_entries {
            rows.append(Row(id: "errlog", name: L("Error information log entries"),
                            rawText: "\(logEntries)", humanText: nil, ok: logEntries == 0))
        }
        return rows
    }

    private func lifeSpanRows(snap: DeviceSnapshot, h: SmartctlInfo.NVMeHealth) -> [Row] {
        var rows: [Row] = []
        if let t = h.temperature {
            rows.append(Row(id: "temp", name: L("Composite temperature"),
                            rawText: "\(t) °C", humanText: nil, ok: t < 70))
        }
        if let sensors = h.temperature_sensors, sensors.count > 1 {
            for (i, s) in sensors.enumerated() {
                rows.append(Row(id: "tsensor\(i)", name: String(format: L("Temperature sensor %lld") as String, i + 1),
                                rawText: "\(s) °C", humanText: nil, ok: s < 70))
            }
        }
        if let used = h.percentage_used {
            rows.append(Row(id: "wear", name: L("Percentage used (NAND wear)"),
                            rawText: "\(used)%", humanText: nil, ok: used < 90))
        }
        if let read = h.data_units_read {
            rows.append(Row(id: "read", name: L("Data units read"),
                            rawText: formatNumber(read),
                            humanText: DeviceFacts.humanBytes(read * 500_000), ok: true))
        }
        if let written = h.data_units_written {
            rows.append(Row(id: "written", name: L("Data units written"),
                            rawText: formatNumber(written),
                            humanText: DeviceFacts.humanBytes(written * 500_000), ok: true))
        }
        if let hr = h.host_reads {
            rows.append(Row(id: "hostr", name: L("Host read commands"),
                            rawText: formatNumber(hr), humanText: nil, ok: true))
        }
        if let hw = h.host_writes {
            rows.append(Row(id: "hostw", name: L("Host write commands"),
                            rawText: formatNumber(hw), humanText: nil, ok: true))
        }
        if let busy = h.controller_busy_time {
            rows.append(Row(id: "busy", name: L("Controller busy time"),
                            rawText: formatNumber(busy),
                            humanText: String(format: L("%lld minutes") as String, busy), ok: true))
        }
        if let cycles = h.power_cycles {
            rows.append(Row(id: "cycles", name: L("Power cycles"),
                            rawText: "\(cycles)", humanText: nil, ok: true))
        }
        if let hours = h.power_on_hours {
            rows.append(Row(id: "hours", name: L("Power-on hours"),
                            rawText: formatNumber(Int64(hours)),
                            humanText: powerOnHuman(hours), ok: true))
        }
        if let unsafe = h.unsafe_shutdowns {
            rows.append(Row(id: "unsafe", name: L("Unsafe shutdowns"),
                            rawText: "\(unsafe)", humanText: nil, ok: true))
        }
        if let wt = h.warning_temp_time {
            rows.append(Row(id: "warntime", name: L("Time above warning temperature"),
                            rawText: String(format: L("%lld minutes") as String, wt),
                            humanText: nil, ok: wt == 0))
        }
        if let ct = h.critical_comp_time {
            rows.append(Row(id: "crittime", name: L("Time above critical temperature"),
                            rawText: String(format: L("%lld minutes") as String, ct),
                            humanText: nil, ok: ct == 0))
        }
        return rows
    }

    // MARK: - Section rendering

    private func section(title: String, caption: String, rows: [Row]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(caption).font(.caption2).foregroundStyle(.secondary)
            }
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.m) {
                        Image(systemName: row.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(row.ok ? .green : .orange)
                            .imageScale(.small)
                            .frame(width: 16)
                        Text(row.name)
                            .font(.callout)
                        Spacer(minLength: Theme.Spacing.m)
                        if let human = row.humanText {
                            Text(human)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(row.rawText)
                            .font(.callout.monospacedDigit())
                            .frame(minWidth: 90, alignment: .trailing)
                    }
                    .padding(.vertical, 7)
                    .padding(.horizontal, Theme.Spacing.m)
                    .background(index.isMultiple(of: 2) ? Color.primary.opacity(0.03) : Color.clear)
                }
            }
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: Theme.Layout.cardRadius))
        }
    }

    private func errorLogFooter(_ snap: DeviceSnapshot) -> some View {
        let count = snap.raw?.nvme_smart_health_information_log?.num_err_log_entries ?? 0
        return HStack(spacing: 6) {
            Image(systemName: count == 0 ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(count == 0 ? .green : .orange)
            if count == 0 {
                Text(LR("Error log checked — no entries. This drive has never logged an NVMe error."))
            } else {
                Text(String(localized: "Error log contains \(Int(count)) entries.", bundle: localizationBundle))
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.top, 2)
    }

    // MARK: - Formatting

    private func formatNumber(_ n: Int64) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    private func powerOnHuman(_ hours: Int) -> String {
        if hours < 48 { return String(format: L("%lld hours") as String, hours) }
        let days = Double(hours) / 24
        if days < 365 { return String(format: L("%lld days") as String, Int(days)) }
        return String(format: "%.1f years", days / 365)
    }
}
