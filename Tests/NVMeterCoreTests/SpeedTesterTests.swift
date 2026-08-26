import XCTest
@testable import NVMeterCore

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = 0

    func increment() {
        lock.lock()
        storage += 1
        lock.unlock()
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

final class SpeedTesterTests: XCTestCase {

    func testRunProducesResultsAndCleansUp() async throws {
        let dir = FileManager.default.temporaryDirectory
        let perProfile: Int64 = 2 * 1024 * 1024   // 2 MiB — fast but real I/O
        let tester = SpeedTester()

        let progressFires = LockedCounter()
        let run = try await tester.run(
            directory: dir,
            totalBytesPerProfile: perProfile,
            temperatureSampler: { 42 },
            onProgress: { _, _, _, _ in progressFires.increment() }
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
        XCTAssertGreaterThanOrEqual(progressFires.value, 8)

        // Scratch file removed.
        let scratch = dir.appendingPathComponent(".nvmeter-speedtest.bin")
        XCTAssertFalse(FileManager.default.fileExists(atPath: scratch.path))
    }
}
