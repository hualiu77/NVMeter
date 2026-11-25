import XCTest
@testable import NVMeterCore

final class EnclosureIssueReportTests: XCTestCase {
    private let os = OperatingSystemVersion(majorVersion: 14, minorVersion: 6, patchVersion: 1)

    func testBlockedReportContainsOnlyPublicBridgeDetails() throws {
        let bridge = try XCTUnwrap(EnclosureIssueReport.USBBridge(vendorID: 0x0bda, productID: 0x9210))
        let report = EnclosureIssueReport(outcome: .blocked, bridge: bridge, version: "0.4.0", os: os)
        XCTAssertEqual(report.title, "Enclosure report: SMART unavailable (USB 0bda:9210)")
        XCTAssertTrue(report.body.contains("could not read SMART"))
        XCTAssertTrue(report.body.contains("USB vendor:product ID:"))
        XCTAssertTrue(report.body.contains("0bda:9210"))
        XCTAssertTrue(report.body.contains("macOS 14.6.1"))
        XCTAssertFalse(report.body.contains("/dev/"))
        XCTAssertFalse(report.body.contains("diskutil"))
        XCTAssertFalse(report.body.contains("ioreg"))
    }

    func testMissingOrInvalidIdentityFailsClosed() {
        XCTAssertNil(EnclosureIssueReport.USBBridge(vendorID: nil, productID: 1))
        XCTAssertNil(EnclosureIssueReport.USBBridge(vendorID: 1, productID: nil))
        XCTAssertNil(EnclosureIssueReport.USBBridge(vendorID: -1, productID: 1))
        XCTAssertNil(EnclosureIssueReport.USBBridge(vendorID: 1, productID: 0x10000))
        let report = EnclosureIssueReport(outcome: .blocked, bridge: nil, version: "dev", os: os)
        XCTAssertEqual(report.title, "Enclosure report: SMART unavailable")
        XCTAssertTrue(report.body.contains("Add it manually if known"))
    }

    func testWorkingReportIncludesOnlyKnownProbeFlags() {
        let known = EnclosureIssueReport(outcome: .working(args: ["-d", "sat,16"]),
                                         bridge: nil, version: "dev", os: os)
        XCTAssertTrue(known.body.contains("-d sat,16"))
        let unrecognized = ["-d", "sat,16", "dummy-private-device-label"]
        let rejected = EnclosureIssueReport(outcome: .working(args: unrecognized),
                                            bridge: nil, version: "dev", os: os)
        XCTAssertTrue(rejected.body.contains("No recognized probe type"))
        XCTAssertFalse((rejected.title + rejected.body).contains(unrecognized[2]))
    }
}
