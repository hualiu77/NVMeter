import XCTest
@testable import NVMeterCore

final class SmartctlProbeTests: XCTestCase {
    private func decode(_ json: String) -> SmartctlInfo {
        try! JSONDecoder().decode(SmartctlInfo.self, from: Data(json.utf8))
    }

    private var withSmart: SmartctlInfo {
        decode("""
        {"device": {"name": "/dev/disk2", "type": "sat", "protocol": "ATA"},
         "smart_status": {"passed": true},
         "temperature": {"current": 38}}
        """)
    }

    private var envelopeOnly: SmartctlInfo {
        // smartctl opened the device but returned no health payload — the
        // shape a wrong `-d` produces.
        decode("""
        {"device": {"name": "/dev/disk2", "type": "scsi", "protocol": "SCSI"}}
        """)
    }

    func testHasUsableSmartDiscriminates() {
        XCTAssertTrue(withSmart.hasUsableSmart)
        XCTAssertFalse(envelopeOnly.hasUsableSmart)
    }

    func testFirstWorkingReturnsFirstUsableCandidate() {
        let hit = SmartctlProbe.firstWorking(
            candidates: [["-d", "sat"], ["-d", "sat,16"], ["-d", "usbjmicron"]]
        ) { args in
            // Only the third candidate yields usable SMART.
            args == ["-d", "usbjmicron"] ? withSmart : envelopeOnly
        }
        XCTAssertEqual(hit?.args, ["-d", "usbjmicron"])
        XCTAssertTrue(hit?.info.hasUsableSmart ?? false)
    }

    func testFirstWorkingRejectsEnvelopeOnlyResponses() {
        // Every candidate "opens" but none reads SMART → no match.
        let hit = SmartctlProbe.firstWorking(candidates: [["-d", "sat"], ["-d", "sat,16"]]) { _ in
            self.envelopeOnly
        }
        XCTAssertNil(hit)
    }

    func testFirstWorkingNilWhenAllProbesFailToOpen() {
        let hit = SmartctlProbe.firstWorking { _ in nil }
        XCTAssertNil(hit)
    }

    func testStandardLadderIsNonEmptyAndStartsWithSat() {
        XCTAssertEqual(SmartctlProbe.typeLadder.first, ["-d", "sat"])
        XCTAssertGreaterThanOrEqual(SmartctlProbe.typeLadder.count, 6)
    }
}
