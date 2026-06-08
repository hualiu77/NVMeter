import Foundation

public enum HealthLevel: String, Sendable, Codable, Comparable {
    case good, unknown, warning, critical
    private var rank: Int {
        switch self { case .good: 0; case .unknown: 1; case .warning: 2; case .critical: 3 }
    }
    public static func < (a: HealthLevel, b: HealthLevel) -> Bool { a.rank < b.rank }
}

public struct HealthAssessment: Sendable {
    public let level: HealthLevel
    public let score: Int
    public let reasons: [String]
}

public struct HealthScorer {
    public init() {}

    public func assess(_ info: SmartctlInfo) -> HealthAssessment {
        var reasons: [String] = []
        var level: HealthLevel = .good
        var score = 100

        if info.smart_status?.passed == false {
            reasons.append("SMART overall self-assessment FAILED")
            level = .critical
            score = 0
        }

        let temp = info.temperature?.current ?? info.nvme_smart_health_information_log?.temperature
        if let t = temp {
            switch t {
            case ...60: break
            case 61...69:
                reasons.append("Temperature \(t)°C is elevated")
                level = max(level, .warning); score -= 5
            case 70...79:
                reasons.append("Temperature \(t)°C is high")
                level = max(level, .warning); score -= 15
            default:
                reasons.append("Temperature \(t)°C is critical")
                level = max(level, .critical); score -= 30
            }
        }

        if let used = info.nvme_smart_health_information_log?.percentage_used {
            score -= max(0, used - 5)
            if used >= 90 {
                reasons.append("NAND wear at \(used)%")
                level = max(level, .critical)
            } else if used >= 70 {
                reasons.append("NAND wear at \(used)%")
                level = max(level, .warning)
            }
        }

        if let spare = info.nvme_smart_health_information_log?.available_spare,
           let threshold = info.nvme_smart_health_information_log?.available_spare_threshold {
            if spare <= threshold {
                reasons.append("Available spare \(spare)% at/below threshold \(threshold)%")
                level = max(level, .critical); score -= 25
            }
        }

        if let errs = info.nvme_smart_health_information_log?.media_errors, errs > 0 {
            reasons.append("\(errs) media/data integrity errors")
            level = max(level, .critical); score -= 20
        }

        return HealthAssessment(level: level, score: max(0, score), reasons: reasons)
    }
}

