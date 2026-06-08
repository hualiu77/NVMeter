import SwiftUI
import NVMeterCore

@main
struct NVMeterApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuView(model: model)
        } label: {
            Label(model.menuBarTitle, systemImage: model.menuBarSymbol)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var devices: [DeviceSnapshot] = []
    @Published var lastError: String?

    private var task: Task<Void, Never>?
    private var service: MonitoringService?

    init() { start() }

    var menuBarTitle: String {
        guard let top = devices.map(\.temperatureC).compactMap({ $0 }).max() else { return "—" }
        return "\(top)°"
    }

    var menuBarSymbol: String {
        switch devices.map(\.level).max() ?? .unknown {
        case .good: "thermometer.low"
        case .warning: "thermometer.medium"
        case .critical: "thermometer.high"
        case .unknown: "thermometer"
        }
    }

    func start() {
        task?.cancel()
        task = Task { [weak self] in
            do {
                let runner = try SmartctlRunner()
                let dir = try FileManager.default.url(
                    for: .applicationSupportDirectory, in: .userDomainMask,
                    appropriateFor: nil, create: true
                ).appendingPathComponent("NVMeter", isDirectory: true)
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let store = try HistoryStore(url: dir.appendingPathComponent("history.sqlite"))
                let svc = MonitoringService(runner: runner, store: store, interval: 300)
                await MainActor.run { self?.service = svc }
                while !Task.isCancelled {
                    do {
                        let results = try await svc.tickOnce()
                        await MainActor.run {
                            self?.devices = results.map(DeviceSnapshot.init)
                            self?.lastError = nil
                        }
                    } catch {
                        await MainActor.run { self?.lastError = String(describing: error) }
                    }
                    try? await Task.sleep(nanoseconds: 300 * 1_000_000_000)
                }
            } catch {
                await MainActor.run { self?.lastError = String(describing: error) }
            }
        }
    }
}

struct DeviceSnapshot: Identifiable {
    let id = UUID()
    let model: String
    let device: String
    let temperatureC: Int?
    let percentageUsed: Int?
    let level: HealthLevel
    let reasons: [String]

    init(info: SmartctlInfo, assessment: HealthAssessment) {
        self.model = info.model_name ?? "Unknown"
        self.device = info.device.name
        self.temperatureC = info.temperature?.current ?? info.nvme_smart_health_information_log?.temperature
        self.percentageUsed = info.nvme_smart_health_information_log?.percentage_used
        self.level = assessment.level
        self.reasons = assessment.reasons
    }

    init(_ pair: (SmartctlInfo, HealthAssessment)) { self.init(info: pair.0, assessment: pair.1) }
}

struct MenuView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("NVMeter").font(.headline)
            if let err = model.lastError {
                Text(err).font(.caption).foregroundStyle(.red).lineLimit(4)
            }
            if model.devices.isEmpty {
                Text("No devices detected yet…").foregroundStyle(.secondary)
            } else {
                ForEach(model.devices) { d in
                    DeviceRow(snapshot: d)
                    Divider()
                }
            }
            HStack {
                Button("Refresh") { model.start() }
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
        }
        .padding(16)
        .frame(width: 360)
    }
}

struct DeviceRow: View {
    let snapshot: DeviceSnapshot
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(snapshot.model).font(.subheadline).bold()
                Spacer()
                Text(snapshot.device).font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                if let t = snapshot.temperatureC { Label("\(t)°C", systemImage: "thermometer") }
                if let u = snapshot.percentageUsed { Label("Wear \(u)%", systemImage: "gauge") }
                Label(snapshot.level.rawValue.capitalized, systemImage: dot(for: snapshot.level))
                    .foregroundStyle(color(for: snapshot.level))
            }
            .font(.caption)
            if !snapshot.reasons.isEmpty {
                ForEach(snapshot.reasons, id: \.self) { r in
                    Text("• \(r)").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func dot(for level: HealthLevel) -> String {
        switch level {
        case .good: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .critical: "xmark.octagon.fill"
        case .unknown: "questionmark.circle"
        }
    }

    private func color(for level: HealthLevel) -> Color {
        switch level {
        case .good: .green
        case .warning: .yellow
        case .critical: .red
        case .unknown: .secondary
        }
    }
}
