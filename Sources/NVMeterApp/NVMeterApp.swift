import SwiftUI
import NVMeterCore

@main
struct NVMeterApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var updater = UpdaterManager()

    var body: some Scene {
        MenuBarExtra {
            MenuView(model: model)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(updater: updater)
        }

        Window(LR("NVMeter — History"), id: "history") {
            HistoryView(model: model)
        }
        .defaultSize(width: 720, height: 540)

        Window(LR("NVMeter — Details"), id: "detail") {
            DetailView(model: model)
        }
        .defaultSize(width: 620, height: 640)

        Window(LR("NVMeter — Speed Test"), id: "speedtest") {
            SpeedTestView(model: model)
        }
        .defaultSize(width: 780, height: 920)

        Window(LR("NVMeter — Self-Test"), id: "selftest") {
            SelfTestView(model: model)
        }
        .defaultSize(width: 560, height: 620)
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var devices: [DeviceSnapshot] = []
    @Published var lastError: String?
    @Published var lastUpdated: Date?
    @Published var isRefreshing: Bool = false
    /// Set by a card click just before opening the detail window so the
    /// window opens focused on that drive. Consumed once by DetailView.
    var detailRequestPath: String?

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

    /// Highest NAND wear (`percentage_used`) across all SMART-capable drives.
    var highestWear: Int? {
        devices.compactMap(\.percentageUsed).max()
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
                let store = try HistoryStore(
                    url: supportDir.appendingPathComponent("history.sqlite"),
                    retentionDays: 30
                )
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

    /// Async accessor so views can pull SQLite history off the actor.
    func history(devicePath: String, limit: Int = 2000) async -> [HealthSample] {
        guard let svc = service else { return [] }
        return (try? await svc.history(devicePath: devicePath, limit: limit)) ?? []
    }

    private func tick() async {
        guard let svc = service else { return }
        do {
            let results = try await svc.tickOnce()
            self.devices = results.map { DeviceSnapshot(report: $0) }
            self.lastUpdated = Date()
            self.lastError = nil

            // Hand snapshots to the notifier with the user's current
            // threshold / enabled settings (read here so the Notifier
            // doesn't need its own @AppStorage plumbing).
            let defaults = UserDefaults.standard
            let settings = NotificationSettings(
                enabled: defaults.object(forKey: SettingsKeys.notificationsEnabled) as? Bool ?? true,
                warningC: defaults.object(forKey: SettingsKeys.warningTempC) as? Int ?? 60,
                criticalC: defaults.object(forKey: SettingsKeys.criticalTempC) as? Int ?? 70
            )
            await Notifier.shared.evaluate(self.devices, settings: settings)
        } catch {
            self.lastError = error.localizedDescription
        }
    }
}
