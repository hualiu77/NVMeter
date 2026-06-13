import Foundation

/// Explains a sequential-write speed drop the way only a tool that records
/// temperature alongside throughput can: was it thermal throttling, or the
/// SLC write-cache filling up? Pure speed benchmarks can't tell these apart;
/// NVMeter's temperature track is exactly what disambiguates them.
public struct SlowdownVerdict: Sendable, Equatable {
    public enum Cause: Sendable, Equatable {
        case steady               // speed held — no meaningful drop
        case thermal              // throttled by heat
        case slcCache             // SLC/pSLC cache exhausted, fell to native NAND
        case inconclusive         // dropped, but the temperature track can't say why
    }

    public let cause: Cause
    public let dropFraction: Double     // 0…1, peak → sustained tail
    public let peakMBps: Double
    public let sustainedMBps: Double
    public let maxTempC: Int?
    public let tempRiseC: Int?          // max − min over the write
}

public enum SlowdownAnalyzer {
    /// A drop smaller than this is normal jitter — report "steady".
    static let steadyThreshold = 0.12
    /// At/above this temperature we attribute the drop to throttling.
    static let thermalCeilingC = 70
    /// A rise this large during the write, ending warm, also reads as thermal.
    static let thermalRiseC = 12

    /// Analyze the sequential-write portion of a run's live samples.
    /// Returns nil when there aren't enough sequential-write samples to judge.
    public static func analyzeSequentialWrite(_ samples: [SpeedSample]) -> SlowdownVerdict? {
        let seq = samples.filter { $0.profileID.hasPrefix("seq1m") && !$0.isRead && $0.mbPerSec > 0 }
        guard seq.count >= 4 else { return nil }

        let peak = seq.map(\.mbPerSec).max() ?? 0
        guard peak > 0 else { return nil }
        let tail = seq.suffix(max(1, seq.count / 4))
        let sustained = tail.map(\.mbPerSec).reduce(0, +) / Double(tail.count)
        let drop = (peak - sustained) / peak

        let temps = seq.compactMap(\.temperatureC)
        let maxTemp = temps.max()
        let rise = (temps.max().flatMap { mx in temps.min().map { mx - $0 } })

        let cause: SlowdownVerdict.Cause
        if drop <= steadyThreshold {
            cause = .steady
        } else if let mt = maxTemp, mt >= thermalCeilingC || (mt >= 60 && (rise ?? 0) >= thermalRiseC) {
            cause = .thermal
        } else if maxTemp != nil {
            // Temperature stayed moderate while speed fell — the classic
            // SLC-cache cliff (write buffer full, now writing to slow NAND).
            cause = .slcCache
        } else {
            // No temperature track (e.g. USB bridge) — can't disambiguate.
            cause = .inconclusive
        }

        return SlowdownVerdict(
            cause: cause,
            dropFraction: drop,
            peakMBps: peak,
            sustainedMBps: sustained,
            maxTempC: maxTemp,
            tempRiseC: rise
        )
    }
}
