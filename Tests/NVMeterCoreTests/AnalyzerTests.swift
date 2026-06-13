import XCTest
@testable import NVMeterCore

final class WearTrendAnalyzerTests: XCTestCase {
    private func sample(_ daysAgo: Double, _ wear: Int, now: Date) -> HealthSample {
        HealthSample(
            id: nil, deviceName: "/dev/disk0", serial: nil,
            timestamp: now.addingTimeInterval(-daysAgo * 86_400),
            temperatureC: 40, percentageUsed: wear, availableSpare: 100,
            mediaErrors: 0, dataUnitsWritten: 0, healthLevel: "good"
        )
    }

    func testInsufficientDataWhenFewSamples() {
        let now = Date()
        let s = [sample(1, 10, now: now), sample(0, 11, now: now)]
        let p = WearTrendAnalyzer.analyze(samples: s, now: now)
        XCTAssertEqual(p?.status, .insufficientData)
    }

    func testFlatWhenWearUnchanged() {
        let now = Date()
        let s = (0..<30).map { sample(Double(29 - $0), 5, now: now) }
        let p = WearTrendAnalyzer.analyze(samples: s, now: now)
        XCTAssertEqual(p?.status, .flat)
        XCTAssertEqual(p?.currentPercent, 5)
    }

    func testProjectsForwardOnRisingWear() {
        let now = Date()
        // 0% → 10% over 100 days = 0.1 %/day → 900 more days to reach 100%.
        let s = (0...100).map { day in sample(Double(100 - day), day / 10, now: now) }
        let p = WearTrendAnalyzer.analyze(samples: s, now: now)
        guard case let .projected(date, perYear)? = p?.status else {
            return XCTFail("expected a projection, got \(String(describing: p?.status))")
        }
        let daysOut = date.timeIntervalSince(now) / 86_400
        XCTAssertEqual(daysOut, 900, accuracy: 60)     // ~900 days to 100%
        XCTAssertEqual(perYear, 36.5, accuracy: 5)     // 0.1%/day × 365
    }
}

final class SlowdownAnalyzerTests: XCTestCase {
    private func s(_ elapsed: Double, _ mbps: Double, _ temp: Int?) -> SpeedSample {
        SpeedSample(elapsed: elapsed, profileID: "seq1m-q8t1-write", isRead: false,
                    mbPerSec: mbps, temperatureC: temp)
    }

    func testSteadyWhenSpeedHolds() {
        let samples = (0..<12).map { s(Double($0), 1000 + Double($0 % 3) * 10, 45) }
        let v = SlowdownAnalyzer.analyzeSequentialWrite(samples)
        XCTAssertEqual(v?.cause, .steady)
    }

    func testThermalWhenHotAtTheEnd() {
        // Fast and cool, then slow and hot.
        var samples = (0..<6).map { s(Double($0), 2000, 50 + $0) }
        samples += (6..<12).map { s(Double($0), 900, 72) }
        let v = SlowdownAnalyzer.analyzeSequentialWrite(samples)
        XCTAssertEqual(v?.cause, .thermal)
        XCTAssertGreaterThan(v?.dropFraction ?? 0, 0.2)
    }

    func testSLCCacheWhenCoolButDropping() {
        var samples = (0..<6).map { _ in s(0, 3000, 48) }
        samples += (6..<12).map { _ in s(0, 800, 50) }
        for i in samples.indices { samples[i] = s(Double(i), samples[i].mbPerSec, samples[i].temperatureC) }
        let v = SlowdownAnalyzer.analyzeSequentialWrite(samples)
        XCTAssertEqual(v?.cause, .slcCache)
    }

    func testInconclusiveWithoutTemperature() {
        var samples = (0..<6).map { s(Double($0), 3000, nil) }
        samples += (6..<12).map { s(Double($0), 800, nil) }
        let v = SlowdownAnalyzer.analyzeSequentialWrite(samples)
        XCTAssertEqual(v?.cause, .inconclusive)
    }

    func testNilWhenTooFewSamples() {
        XCTAssertNil(SlowdownAnalyzer.analyzeSequentialWrite([s(0, 1000, 40)]))
    }
}
