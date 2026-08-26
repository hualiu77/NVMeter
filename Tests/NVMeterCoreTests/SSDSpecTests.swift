import XCTest
@testable import NVMeterCore

final class SSDSpecTests: XCTestCase {
    private let db = SSDSpecDatabase(specs: SSDSpecDatabase.builtInSeed)

    func testSeedMatchesCrucialP3ByModelCode() {
        // Both P3 and P3 Plus report a code containing "CT1000P3".
        let p3plus = db.lookup(model: "CT1000P3PSSD8")
        XCTAssertEqual(p3plus?.brand, "Crucial")
        XCTAssertEqual(p3plus?.tbw, 220)
        XCTAssertEqual(p3plus?.warranty_years, 5)
        XCTAssertEqual(db.lookup(model: "CT1000P3SSD8")?.tbw, 220)
    }

    func testCapacitySpecificMatch() {
        XCTAssertEqual(db.lookup(model: "CT2000P3PSSD8")?.tbw, 440)
        XCTAssertEqual(db.lookup(model: "Samsung SSD 990 PRO 2TB")?.tbw, 1200)
        XCTAssertEqual(db.lookup(model: "Samsung SSD 990 PRO 1TB")?.tbw, 600)
    }

    func testUnknownModelReturnsNil() {
        XCTAssertNil(db.lookup(model: "Totally Unknown Drive 9000"))
    }

    func testLongestTokenWins() {
        let custom = SSDSpecDatabase(specs: [
            SSDSpec(model_match: ["CT"], brand: "Generic", tbw: 1),
            SSDSpec(model_match: ["CT1000P3"], brand: "Crucial", tbw: 220),
        ])
        XCTAssertEqual(custom.lookup(model: "CT1000P3PSSD8")?.brand, "Crucial")
    }

    func testUsedEnduranceFraction() {
        let spec = SSDSpec(model_match: ["x"], brand: "x", tbw: 220)
        // 22 TB written of a 220 TBW rating = 10%.
        XCTAssertEqual(spec.usedEnduranceFraction(lifetimeWrittenBytes: 22_000_000_000_000)!, 0.10, accuracy: 0.001)
        XCTAssertNil(SSDSpec(model_match: ["x"], brand: "x", tbw: nil).usedEnduranceFraction(lifetimeWrittenBytes: 1))
    }

    func testSeedHasNoZeroOrNegativeTBW() {
        for spec in SSDSpecDatabase.builtInSeed {
            if let t = spec.tbw { XCTAssertGreaterThan(t, 0, "\(spec.series ?? spec.brand)") }
            XCTAssertFalse(spec.model_match.isEmpty)
        }
    }
}

final class WarrantyLinksTests: XCTestCase {
    func testKnownBrandResolvesToOfficialPage() {
        let t = WarrantyLinks.target(brand: "Crucial", model: "CT1000P3PSSD8")
        XCTAssertTrue(t.isOfficial)
        XCTAssertEqual(t.brandLabel, "Crucial")
        XCTAssertTrue(t.url.absoluteString.contains("crucial.com"))
        XCTAssertFalse(t.hasSerialLookup)   // Crucial has no online serial checker
    }

    func testSerialLookupBrandsAreFlagged() {
        XCTAssertEqual(WarrantyLinks.target(brand: "Seagate", model: "ZP1000GM30013").serial, .driveSerial)
        XCTAssertEqual(WarrantyLinks.target(brand: "Western Digital", model: "WD_BLACK SN770 1TB").serial, .driveSerial)
        XCTAssertEqual(WarrantyLinks.target(brand: "Samsung", model: "Samsung SSD 990 PRO 1TB").serial, .none)
    }

    func testAppleInternalGoesToCoverageCheckerWithMachineSerial() {
        let t = WarrantyLinks.target(brand: nil, model: "APPLE SSD AP0512Z")
        XCTAssertTrue(t.isOfficial)
        XCTAssertEqual(t.brandLabel, "Apple")
        XCTAssertEqual(t.serial, .machineSerial)
        XCTAssertTrue(t.url.absoluteString.contains("checkcoverage.apple.com"))
    }

    func testBrandInferredFromModelString() {
        let t = WarrantyLinks.target(brand: nil, model: "Samsung SSD 990 PRO 2TB")
        XCTAssertTrue(t.isOfficial)
        XCTAssertEqual(t.brandLabel, "Samsung")
    }

    func testUnknownBrandFallsBackToSearchWithoutSerial() {
        let serial = "S6XYZ123456"
        let t = WarrantyLinks.target(brand: "NoNameCorp", model: "MysteryDrive 1TB")
        XCTAssertFalse(t.isOfficial)
        XCTAssertFalse(t.url.absoluteString.contains(serial))  // never leak the serial into a URL
        XCTAssertTrue(t.url.absoluteString.contains("duckduckgo"))
    }
}
