import Foundation

/// Result of polling one device: smartctl data + scored health + system facts.
public struct DeviceReport: Sendable {
    public let info: SmartctlInfo
    public let assessment: HealthAssessment
    public let facts: DeviceFacts
}

public actor MonitoringService {
    private let runner: SmartctlRunner
    private let scorer = HealthScorer()
    private let probe = SystemProbe()
    private let store: HistoryStore
    private let interval: TimeInterval

    public init(runner: SmartctlRunner, store: HistoryStore, interval: TimeInterval = 300) {
        self.runner = runner
        self.store = store
        self.interval = interval
    }

    public func tickOnce() async throws -> [DeviceReport] {
        let scanned = try runner.scan()
        var results: [DeviceReport] = []
        for d in scanned {
            guard let info = try? runner.info(device: d.name) else { continue }
            let assessment = scorer.assess(info)
            let facts = await probe.probe(devicePath: d.name, info: info)

            let sample = HealthSample(
                id: nil,
                deviceName: info.device.name,
                serial: info.serial_number,
                timestamp: Date(),
                temperatureC: info.temperature?.current ?? info.nvme_smart_health_information_log?.temperature,
                percentageUsed: info.nvme_smart_health_information_log?.percentage_used,
                availableSpare: info.nvme_smart_health_information_log?.available_spare,
                mediaErrors: info.nvme_smart_health_information_log?.media_errors,
                dataUnitsWritten: info.nvme_smart_health_information_log?.data_units_written,
                healthLevel: assessment.level.rawValue
            )
            try? store.insert(sample)
            results.append(DeviceReport(info: info, assessment: assessment, facts: facts))
        }
        try? store.prune()
        return results
    }
}
