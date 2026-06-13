import Foundation
import SwiftUI
import NVMeterCore

/// Drives the speed-test window: resolves a writable scratch location for
/// the chosen drive, runs the benchmark, streams live throughput +
/// temperature to the UI, and persists each run for history comparison.
@MainActor
final class SpeedTestModel: ObservableObject {
    // Live state during a run
    @Published var isRunning = false
    @Published var currentProfileLabel: String?
    @Published var currentIsRead = false
    @Published var fraction: Double = 0           // within the current profile
    @Published var liveMBps: Double = 0
    @Published var liveTemp: Int?
    @Published var liveSamples: [SpeedSample] = [] // for the live overlay chart
    @Published var completed: [ProfileResult] = [] // profiles finished so far

    // Result of the most recent run + history
    @Published var lastRun: SpeedTestRun?
    @Published var history: [SpeedRunRecord] = []
    @Published var error: String?

    // Configuration
    enum Size: Int, CaseIterable, Identifiable {
        case g1 = 1, g4 = 4, g16 = 16, g64 = 64
        var id: Int { rawValue }
        var bytes: Int64 { Int64(rawValue) * 1024 * 1024 * 1024 }
        var label: String { "\(rawValue) GiB" }
    }
    @Published var selectedSize: Size = .g1

    /// Device the window is currently pointed at.
    @Published var device: DeviceSnapshot?

    private let tester = SpeedTester()
    private let store: SpeedTestStore?
    private let runner: SmartctlRunner?
    private var runTask: Task<Void, Never>?
    private var runStart = Date()

    init() {
        runner = try? SmartctlRunner()
        store = Self.makeStore()
    }

    private static func makeStore() -> SpeedTestStore? {
        guard let support = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        ).appendingPathComponent("NVMeter", isDirectory: true) else { return nil }
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        return try? SpeedTestStore(url: support.appendingPathComponent("speedtest.sqlite"))
    }

    // MARK: - Device selection

    func select(_ device: DeviceSnapshot) {
        guard !isRunning else { return }
        self.device = device
        loadHistory(for: device.devicePath)
    }

    func loadHistory(for devicePath: String) {
        history = (try? store?.recent(devicePath: devicePath, limit: 50)) ?? []
    }

    // MARK: - Run lifecycle

    /// Estimated bytes that will be written to NAND this run (writes only).
    var estimatedWriteBytes: Int64 {
        // 4 of the 8 default profiles are writes.
        4 * selectedSize.bytes
    }

    var canRun: Bool {
        guard let device, !isRunning else { return false }
        return scratchDirectory(for: device) != nil
    }

    func start() {
        guard let device, !isRunning else { return }
        guard let dir = scratchDirectory(for: device) else {
            error = L("This drive has no writable volume to test on.")
            return
        }
        if let free = freeBytes(at: dir), free < selectedSize.bytes + (256 << 20) {
            error = L("Not enough free space on this drive for the selected test size.")
            return
        }

        error = nil
        isRunning = true
        fraction = 0
        liveMBps = 0
        liveTemp = nil
        liveSamples = []
        completed = []
        runStart = Date()

        let totalBytes = selectedSize.bytes
        let path = device.devicePath
        let args = device.facts.workingSmartctlArgs ?? []
        let runner = self.runner

        // Temperature sampler: a lightweight smartctl read each tick. Nil
        // for USB bridges macOS won't read SMART from — the test still runs,
        // just without the temperature overlay.
        let sampler: @Sendable () async -> Int? = {
            guard let runner, let info = try? runner.info(device: path, extraArgs: args) else { return nil }
            return info.temperature?.current ?? info.nvme_smart_health_information_log?.temperature
        }

        let start = runStart
        let onProgress: @Sendable (SpeedTestProfile, Double, Double, Int?) -> Void = { [weak self] profile, frac, mbps, temp in
            Task { @MainActor in
                guard let self else { return }
                self.currentProfileLabel = profile.label
                self.currentIsRead = profile.isRead
                self.fraction = frac
                self.liveMBps = mbps
                self.liveTemp = temp
                self.liveSamples.append(SpeedSample(
                    elapsed: Date().timeIntervalSince(start),
                    profileID: profile.id,
                    isRead: profile.isRead,
                    mbPerSec: mbps,
                    temperatureC: temp
                ))
            }
        }

        let deviceName = device.modelName
        runTask = Task { [weak self] in
            guard let self else { return }
            do {
                let run = try await self.tester.run(
                    directory: dir,
                    totalBytesPerProfile: totalBytes,
                    temperatureSampler: sampler,
                    onProgress: onProgress
                )
                await MainActor.run {
                    self.lastRun = run
                    self.completed = run.results
                    self.liveSamples = run.samples   // authoritative, complete
                    self.isRunning = false
                    try? self.store?.insert(run: run, deviceName: deviceName, devicePath: path)
                    self.loadHistory(for: path)
                }
            } catch is CancellationError {
                await MainActor.run { self.isRunning = false }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    self.isRunning = false
                }
            }
        }
    }

    func cancel() {
        runTask?.cancel()
    }

    // MARK: - Scratch location

    private func scratchDirectory(for device: DeviceSnapshot) -> URL? {
        let fm = FileManager.default
        let sub = "nvmeter-speedtest"

        // Internal Apple SSD: the caches dir lives on it, and we can't
        // write to "/". So benchmark via caches.
        if device.facts.bus == .internalNVMe {
            if let caches = try? fm.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true) {
                let dir = caches.appendingPathComponent("NVMeter").appendingPathComponent(sub)
                if (try? fm.createDirectory(at: dir, withIntermediateDirectories: true)) != nil { return dir }
            }
        }

        // External drives: write into the first mount point that accepts a directory.
        for mp in device.facts.mountPoints {
            let dir = URL(fileURLWithPath: mp).appendingPathComponent(sub)
            if (try? fm.createDirectory(at: dir, withIntermediateDirectories: true)) != nil { return dir }
        }
        return nil
    }

    private func freeBytes(at url: URL) -> Int64? {
        guard let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
              let free = values.volumeAvailableCapacityForImportantUsage else { return nil }
        return free
    }
}
