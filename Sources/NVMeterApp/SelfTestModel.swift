import Foundation
import SwiftUI
import NVMeterCore

/// Drives the self-test window: starts an extended ("long") SMART self-test
/// on the chosen drive, polls the drive for progress while it runs, and
/// persists each completed result. The test executes on the drive itself,
/// so it survives sleep, lid-close, and even quitting NVMeter — re-opening
/// the window resumes the live progress.
@MainActor
final class SelfTestModel: ObservableObject {
    @Published var device: DeviceSnapshot?
    @Published var status: SelfTestStatus = .unknown
    @Published var isRunning = false
    @Published var startedAt: Date?
    @Published var estimatedMinutes: Int?
    @Published var history: [SelfTestRecord] = []
    @Published var error: String?

    private let runner: SmartctlRunner?
    private let store: SelfTestStore?
    private var pollTask: Task<Void, Never>?
    /// The newest log entry observed when the current run began — lets us
    /// recognize a freshly-appended result even on drives that never report
    /// an explicit "running" state.
    private var baselineEntry: SelfTestLogEntry?
    private var sawRunning = false

    /// How often to ask the drive for progress. Extended tests run for
    /// minutes-to-hours, so a slow cadence is plenty and keeps smartctl
    /// subprocess spawns rare.
    private let pollInterval: UInt64 = 12

    init() {
        runner = try? SmartctlRunner()
        store = Self.makeStore()
    }

    private static func makeStore() -> SelfTestStore? {
        guard let support = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        ).appendingPathComponent("NVMeter", isDirectory: true) else { return nil }
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        return try? SelfTestStore(url: support.appendingPathComponent("selftest.sqlite"))
    }

    // MARK: - Device selection

    func select(_ device: DeviceSnapshot) {
        guard !isRunning else { return }
        pollTask?.cancel()
        self.device = device
        self.error = nil
        self.status = .unknown
        self.estimatedMinutes = nil
        loadHistory(for: device.devicePath)

        // One probe to learn the current status + estimate. If a test is
        // already running (started earlier, or by another tool), resume the
        // progress view instead of showing "idle".
        let path = device.devicePath
        let args = device.facts.workingSmartctlArgs ?? []
        guard let runner else { return }
        Task.detached { [weak self] in
            guard let info = try? runner.info(device: path, extraArgs: args) else { return }
            let st = info.selfTest
            let est = info.extendedSelfTestMinutes
            await MainActor.run { [weak self] in
                guard let self, self.device?.devicePath == path, !self.isRunning else { return }
                self.status = st
                self.estimatedMinutes = est
                if st.state == .running { self.resumePolling(path: path, args: args) }
            }
        }
    }

    func loadHistory(for devicePath: String) {
        history = (try? store?.recent(devicePath: devicePath, limit: 50)) ?? []
    }

    var canRun: Bool {
        guard let device, !isRunning, runner != nil else { return false }
        return !device.isBlocked && device.supportsSelfTest
    }

    // MARK: - Run lifecycle

    func start() {
        guard let device, canRun, let runner else { return }
        let path = device.devicePath
        let args = device.facts.workingSmartctlArgs ?? []

        error = nil
        sawRunning = false
        baselineEntry = currentNewestEntry()
        startedAt = Date()
        isRunning = true
        status = SelfTestStatus(state: .running, completionPercent: 0,
                                message: L("Starting extended self-test…"))

        pollTask = Task { [weak self] in
            do {
                try await Task.detached { try runner.startExtendedSelfTest(device: path, extraArgs: args) }.value
            } catch {
                await MainActor.run {
                    guard let self else { return }
                    self.error = (error as? SmartctlRunner.Error).map(Self.describe) ?? error.localizedDescription
                    self.isRunning = false
                    self.status = SelfTestStatus(state: .idle)
                }
                return
            }
            await self?.pollLoop(path: path, args: args)
        }
    }

    /// Re-attach the poll loop to a test that's already running on the drive
    /// (e.g. NVMeter was reopened mid-test).
    private func resumePolling(path: String, args: [String]) {
        guard !isRunning else { return }
        sawRunning = true
        baselineEntry = currentNewestEntry()
        startedAt = startedAt ?? Date()
        isRunning = true
        pollTask?.cancel()
        pollTask = Task { [weak self] in await self?.pollLoop(path: path, args: args) }
    }

    private func pollLoop(path: String, args: [String]) async {
        guard let runner else { return }
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: pollInterval * 1_000_000_000)
            if Task.isCancelled { break }

            guard let info = try? await Task.detached(operation: { try runner.info(device: path, extraArgs: args) }).value else {
                continue   // transient smartctl hiccup — keep polling
            }
            let st = info.selfTest
            let newest = info.selfTestLog.first

            await MainActor.run { [weak self] in
                guard let self, self.isRunning else { return }
                self.status = st
                if st.state == .running { self.sawRunning = true }
            }

            // Completion signals, in priority order:
            //   1) we saw it running and it's now idle, or
            //   2) a brand-new log entry appeared since we started.
            let finishedByState = (st.state == .idle && sawRunning)
            let finishedByLog = newest != nil && newest != baselineEntry
            if finishedByState || finishedByLog {
                await finalize(newest: newest, path: path)
                break
            }
        }
    }

    func abort() {
        guard let device, let runner, isRunning else { return }
        let path = device.devicePath
        let args = device.facts.workingSmartctlArgs ?? []
        pollTask?.cancel()
        Task.detached { try? runner.abortSelfTest(device: path, extraArgs: args) }
        isRunning = false
        status = SelfTestStatus(state: .idle, message: L("Self-test aborted."))
    }

    // MARK: - Finalization

    private func finalize(newest: SelfTestLogEntry?, path: String) async {
        isRunning = false
        status = SelfTestStatus(state: .idle, message: newest?.resultLabel)

        guard let device, device.devicePath == path else { return }
        let record = SelfTestRecord(
            deviceName: device.modelName,
            devicePath: path,
            serial: device.raw?.serial_number,
            startedAt: startedAt ?? Date(),
            finishedAt: Date(),
            resultLabel: newest?.resultLabel ?? L("Completed"),
            passed: newest?.passed,
            lifetimeHours: newest?.lifetimeHours
        )
        try? store?.insert(record)
        loadHistory(for: path)
        await Notifier.shared.selfTestFinished(
            deviceName: device.modelName,
            passed: newest?.passed,
            resultLabel: record.resultLabel
        )
    }

    private func currentNewestEntry() -> SelfTestLogEntry? {
        guard let device, let runner, !device.isBlocked else { return nil }
        let args = device.facts.workingSmartctlArgs ?? []
        return (try? runner.info(device: device.devicePath, extraArgs: args))?.selfTestLog.first
    }

    private static func describe(_ error: SmartctlRunner.Error) -> String {
        switch error {
        case .binaryNotFound: return L("smartctl not found. Install it with: brew install smartmontools")
        case .executionFailed(_, let msg): return msg.isEmpty ? L("smartctl could not start the self-test on this drive.") : msg
        case .decodeFailed: return L("Could not read the self-test status.")
        }
    }
}
