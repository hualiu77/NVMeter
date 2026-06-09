import Foundation

/// Result of polling one device.
public enum DeviceReport: Sendable {
    /// smartctl read succeeded → full health data + system facts.
    case healthy(info: SmartctlInfo, assessment: HealthAssessment, facts: DeviceFacts)

    /// smartctl couldn't open the device (typical for USB-SATA / USB-NVMe
    /// bridges on macOS). We still surface the device in the UI with the
    /// non-SMART facts we *can* probe (capacity, mount, connection, brand).
    case blocked(devicePath: String, facts: DeviceFacts)

    public var devicePath: String {
        switch self {
        case .healthy(let info, _, _): info.device.name
        case .blocked(let path, _): path
        }
    }

    public var facts: DeviceFacts {
        switch self {
        case .healthy(_, _, let f): f
        case .blocked(_, let f): f
        }
    }
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
            let info = try? runner.info(device: d.name)
            let facts = await probe.probe(devicePath: d.name, info: info)

            if let info {
                let assessment = scorer.assess(info)
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
                results.append(.healthy(info: info, assessment: assessment, facts: facts))
            } else {
                // Don't surface system-level virtual drives that just happened
                // to slip past the scan filter. We require at least a capacity
                // OR a non-empty media hint to call something a "real" disk.
                if facts.capacityBytes > 0 || facts.modelHint != nil {
                    results.append(.blocked(devicePath: d.name, facts: facts))
                }
            }
        }
        try? store.prune()
        return results
    }
}
