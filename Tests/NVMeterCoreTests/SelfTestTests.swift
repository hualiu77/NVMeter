import XCTest
@testable import NVMeterCore

final class SelfTestTests: XCTestCase {
    private func decode(_ json: String) -> SmartctlInfo {
        try! JSONDecoder().decode(SmartctlInfo.self, from: Data(json.utf8))
    }

    // MARK: - NVMe

    func testNVMeRunningReportsProgress() {
        let info = decode("""
        {
          "device": {"name": "/dev/disk0", "type": "nvme", "protocol": "NVMe"},
          "nvme_self_test_log": {
            "current_self_test_operation": {"value": 2, "string": "Extended self-test in progress"},
            "current_self_test_completion_percent": 40,
            "table": []
          }
        }
        """)
        let st = info.selfTest
        XCTAssertEqual(st.state, .running)
        XCTAssertEqual(st.completionPercent, 40)
        XCTAssertTrue(info.supportsSelfTest)
    }

    func testNVMeIdleWithPassedEntry() {
        let info = decode("""
        {
          "device": {"name": "/dev/disk0", "type": "nvme", "protocol": "NVMe"},
          "nvme_self_test_log": {
            "current_self_test_operation": {"value": 0, "string": "No device self-test operation in progress"},
            "table": [
              {"self_test_code": {"value": 2, "string": "Extended"},
               "self_test_result": {"value": 0, "string": "Completed without error"},
               "power_on_hours": 1234}
            ]
          }
        }
        """)
        XCTAssertEqual(info.selfTest.state, .idle)
        let entry = info.selfTestLog.first
        XCTAssertEqual(entry?.passed, true)
        XCTAssertEqual(entry?.lifetimeHours, 1234)
        XCTAssertEqual(entry?.resultLabel, "Completed without error")
    }

    func testNVMeFailedEntry() {
        let info = decode("""
        {
          "device": {"name": "/dev/disk0", "type": "nvme", "protocol": "NVMe"},
          "nvme_self_test_log": {
            "current_self_test_operation": {"value": 0, "string": "idle"},
            "table": [
              {"self_test_code": {"value": 2, "string": "Extended"},
               "self_test_result": {"value": 7, "string": "Completed: failed segments"},
               "power_on_hours": 999}
            ]
          }
        }
        """)
        XCTAssertEqual(info.selfTestLog.first?.passed, false)
    }

    // MARK: - ATA

    func testATARunningDerivesPercentFromRemaining() {
        let info = decode("""
        {
          "device": {"name": "/dev/disk2", "type": "sat", "protocol": "ATA"},
          "ata_smart_data": {
            "self_test": {
              "status": {"value": 249, "string": "Self-test in progress", "remaining_percent": 30},
              "polling_minutes": {"short": 2, "extended": 80}
            }
          }
        }
        """)
        let st = info.selfTest
        XCTAssertEqual(st.state, .running)
        XCTAssertEqual(st.completionPercent, 70)
        XCTAssertEqual(info.extendedSelfTestMinutes, 80)
    }

    func testATAIdleWithLogEntry() {
        let info = decode("""
        {
          "device": {"name": "/dev/disk2", "type": "sat", "protocol": "ATA"},
          "ata_smart_data": {
            "self_test": {"status": {"value": 0, "string": "completed without error", "passed": true}}
          },
          "ata_smart_self_test_log": {
            "standard": {"table": [
              {"type": {"value": 2, "string": "Extended offline"},
               "status": {"value": 0, "string": "Completed without error", "passed": true},
               "lifetime_hours": 4242}
            ]}
          }
        }
        """)
        XCTAssertEqual(info.selfTest.state, .idle)
        let entry = info.selfTestLog.first
        XCTAssertEqual(entry?.passed, true)
        XCTAssertEqual(entry?.typeLabel, "Extended offline")
        XCTAssertEqual(entry?.lifetimeHours, 4242)
    }

    // MARK: - Unsupported

    func testNoSelfTestSubtreeIsUnknown() {
        let info = decode("""
        {"device": {"name": "/dev/disk9", "type": "scsi", "protocol": "SCSI"}}
        """)
        XCTAssertEqual(info.selfTest.state, .unknown)
        XCTAssertFalse(info.supportsSelfTest)
        XCTAssertTrue(info.selfTestLog.isEmpty)
    }
}
