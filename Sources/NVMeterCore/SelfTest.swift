import Foundation

/// Live state of a drive's built-in self-test, normalized across the ATA
/// and NVMe reporting shapes so the UI doesn't care which kind of drive it
/// is looking at.
public struct SelfTestStatus: Sendable, Equatable {
    public enum State: String, Sendable {
        case idle        // no test running; `lastResult` (if any) holds the prior outcome
        case running
        case unknown     // device doesn't expose self-test status (e.g. macOS-blocked bridge)
    }

    public var state: State
    /// 0…100 best-effort completion while running. Nil when the drive
    /// reports progress only as a coarse "in progress".
    public var completionPercent: Int?
    /// Human one-liner straight from smartctl, e.g. "Extended self-test in progress".
    public var message: String?

    public init(state: State, completionPercent: Int? = nil, message: String? = nil) {
        self.state = state
        self.completionPercent = completionPercent
        self.message = message
    }

    public static let unknown = SelfTestStatus(state: .unknown)
}

/// One completed entry from the drive's self-test log.
public struct SelfTestLogEntry: Sendable, Equatable, Codable {
    public var typeLabel: String
    public var resultLabel: String
    /// True = passed, false = failed, nil = aborted / interrupted / unknown.
    public var passed: Bool?
    /// Drive power-on hours at which the test was recorded — the stable key
    /// that distinguishes a fresh result from one already in the log.
    public var lifetimeHours: Int?

    public init(typeLabel: String, resultLabel: String, passed: Bool?, lifetimeHours: Int?) {
        self.typeLabel = typeLabel
        self.resultLabel = resultLabel
        self.passed = passed
        self.lifetimeHours = lifetimeHours
    }
}

public extension SmartctlInfo {
    /// Live self-test status, reading whichever of the ATA / NVMe subtrees
    /// the drive populated.
    var selfTest: SelfTestStatus {
        // NVMe: current_self_test_operation.value == 0 means idle.
        if let nvme = nvme_self_test_log, let op = nvme.current_self_test_operation {
            if let v = op.value, v != 0 {
                return SelfTestStatus(
                    state: .running,
                    completionPercent: nvme.current_self_test_completion_percent,
                    message: op.string
                )
            }
            return SelfTestStatus(state: .idle, message: op.string)
        }

        // ATA: status.value in the 0xF0 range means "in progress".
        if let status = ata_smart_data?.self_test?.status {
            if let remaining = status.remaining_percent {
                return SelfTestStatus(
                    state: .running,
                    completionPercent: 100 - remaining,
                    message: status.string
                )
            }
            // Some smartctl builds signal in-progress only via value 0xF?.
            if let v = status.value, (0xF0...0xFF).contains(v) {
                return SelfTestStatus(state: .running, message: status.string)
            }
            return SelfTestStatus(state: .idle, message: status.string)
        }

        return .unknown
    }

    /// Completed self-test log entries, newest first.
    var selfTestLog: [SelfTestLogEntry] {
        if let table = nvme_self_test_log?.table {
            return table.compactMap { e in
                guard let result = e.self_test_result else { return nil }
                // NVMe result value 0 = completed OK; 5/6/7 = failed; 1–4 = aborted.
                let passed: Bool?
                switch result.value {
                case 0:        passed = true
                case 5, 6, 7:  passed = false
                default:       passed = nil
                }
                return SelfTestLogEntry(
                    typeLabel: e.self_test_code?.string ?? "Self-test",
                    resultLabel: result.string ?? "—",
                    passed: passed,
                    lifetimeHours: e.power_on_hours
                )
            }
        }
        if let table = ata_smart_self_test_log?.standard?.table {
            return table.map { e in
                SelfTestLogEntry(
                    typeLabel: e.type?.string ?? "Self-test",
                    resultLabel: e.status?.string ?? "—",
                    passed: e.status?.passed,
                    lifetimeHours: e.lifetime_hours
                )
            }
        }
        return []
    }

    /// Estimated minutes for an extended test, when the drive advertises it
    /// (ATA `polling_minutes.extended`). NVMe rarely reports this.
    var extendedSelfTestMinutes: Int? {
        ata_smart_data?.self_test?.polling_minutes?.extended
    }

    /// Whether this drive exposes a self-test interface at all.
    var supportsSelfTest: Bool {
        nvme_self_test_log != nil || ata_smart_data?.self_test != nil
    }
}
