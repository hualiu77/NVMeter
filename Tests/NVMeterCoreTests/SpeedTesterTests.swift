import XCTest
@testable import NVMeterCore

final class SpeedTesterTests: XCTestCase {

    func testRunProducesResultsAndCleansUp() async throws {
        let dir = FileManager.default.temporaryDirectory
        let perProfile: Int64 = 2 * 1024 * 1024   // 2 MiB — fast but real I/O
        let tester = SpeedTester()

        var progressFires = 0
        let run = try await tester.run(
            directory: dir,
            totalBytesPerProfile: perProfile,
            temperatureSampler: { 42 },
            onProgress: { _, _, _, _ in progressFires += 1 }
        )

        // Full CrystalDiskMark suite = 4 patterns × (write + read) = 8.
        XCTAssertEqual(run.results.count, 8)

        // Every profile should have moved real bytes at a positive rate.
        for r in run.results {
            XCTAssertGreaterThan(r.mbPerSec, 0, "\(r.label) \(r.isRead ? "read" : "write") was 0 MB/s")
        }

        // Random profiles report IOPS, sequential ones don't.
        XCTAssertTrue(run.results.contains { $0.iops != nil })
        XCTAssertTrue(run.results.contains { $0.iops == nil })

        // 4 write passes × 2 MiB each.
        XCTAssertEqual(run.bytesWritten, 4 * perProfile)

        // Progress fired at least once per profile (final 100% tick).
        XCTAssertGreaterThanOrEqual(progressFires, 8)

        // Scratch file removed.
        let scratch = dir.appendingPathComponent(".nvmeter-speedtest.bin")
        XCTAssertFalse(FileManager.default.fileExists(atPath: scratch.path))
    }
}
