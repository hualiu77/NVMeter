import SwiftUI
import NVMeterCore

@main
struct NVMeterApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuView(model: model)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var devices: [DeviceSnapshot] = []
    @Published var lastError: String?
    @Published var lastUpdated: Date?
    @Published var isRefreshing: Bool = false

    private var loopTask: Task<Void, Never>?
    private var service: MonitoringService?
    private let pollSeconds: UInt64 = 300

    init() { start() }

    // MARK: - Derived for menu bar
    var hottestTemp: Int? {
        devices.compactMap(\.temperatureC).max()
    }

    var hottestLevel: HealthLevel? {
        devices.map(\.level).max()
    }

    // MARK: - Lifecycle
    func start() {
        loopTask?.cancel()
        loopTask = Task { [weak self] in
            guard let self else { return }
            do {
                let runner = try SmartctlRunner()
                let supportDir = try FileManager.default.url(
                    for: .applicationSupportDirectory, in: .userDomainMask,
                    appropriateFor: nil, create: true
                ).appendingPathComponent("NVMeter", isDirectory: true)
                try FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
                let store = try HistoryStore(url: supportDir.appendingPathComponent("history.sqlite"))
                let svc = MonitoringService(runner: runner, store: store, interval: 300)
                await MainActor.run { self.service = svc }

                while !Task.isCancelled {
                    await self.tick()
                    try? await Task.sleep(nanoseconds: self.pollSeconds * 1_000_000_000)
                }
            } catch {
                await MainActor.run {
                    self.lastError = "Setup failed: \(error.localizedDescription)"
                }
            }
        }
    }

    func refreshNow() async {
        isRefreshing = true
        await tick()
        isRefreshing = false
    }

    private func tick() async {
        guard let svc = service else { return }
        do {
            let results = try await svc.tickOnce()
            self.devices = results.map(DeviceSnapshot.init)
            self.lastUpdated = Date()
            self.lastError = nil
        } catch {
            self.lastError = error.localizedDescription
        }
    }
}
