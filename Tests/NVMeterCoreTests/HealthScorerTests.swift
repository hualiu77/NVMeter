import XCTest
@testable import NVMeterCore

final class HealthScorerTests: XCTestCase {
    private func info(temp: Int? = nil, used: Int? = nil, spare: Int? = nil, threshold: Int? = nil, mediaErrors: Int? = nil, passed: Bool = true) -> SmartctlInfo {
        let json = """
        {
          "device": {"name": "/dev/disk0", "type": "nvme", "protocol": "NVMe"},
          "smart_status": {"passed": \(passed)},
          \(temp.map { "\"temperature\": {\"current\": \($0)}," } ?? "")
          "nvme_smart_health_information_log": {
            \(temp.map { "\"temperature\": \($0)," } ?? "")
            \(used.map { "\"percentage_used\": \($0)," } ?? "")
            \(spare.map { "\"available_spare\": \($0)," } ?? "")
            \(threshold.map { "\"available_spare_threshold\": \($0)," } ?? "")
            \(mediaErrors.map { "\"media_errors\": \($0)," } ?? "")
            "power_on_hours": 100
          }
        }
        """
        return try! JSONDecoder().decode(SmartctlInfo.self, from: Data(json.utf8))
    }

    func testHealthyDriveScoresHigh() {
        let a = HealthScorer().assess(info(temp: 35, used: 0, spare: 100, threshold: 5))
        XCTAssertEqual(a.level, .good)
        XCTAssertGreaterThanOrEqual(a.score, 95)
    }

    func testHotDriveWarns() {
        let a = HealthScorer().assess(info(temp: 75))
        XCTAssertEqual(a.level, .warning)
    }

    func testCriticalTemperature() {
        let a = HealthScorer().assess(info(temp: 90))
        XCTAssertEqual(a.level, .critical)
    }

    func testSpareBelowThreshold() {
        let a = HealthScorer().assess(info(spare: 4, threshold: 5))
        XCTAssertEqual(a.level, .critical)
    }

    func testSmartFailDominates() {
        let a = HealthScorer().assess(info(temp: 30, passed: false))
        XCTAssertEqual(a.level, .critical)
        XCTAssertEqual(a.score, 0)
    }

    func testMediaErrorsCritical() {
        let a = HealthScorer().assess(info(mediaErrors: 3))
        XCTAssertEqual(a.level, .critical)
    }
}
