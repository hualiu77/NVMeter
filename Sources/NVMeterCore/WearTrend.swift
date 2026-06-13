import Foundation

/// A projection of when a drive's NAND wear (`percentage_used`) will reach a
/// target threshold, derived from the locally-stored history by ordinary
/// least-squares regression. Purely local, no model — just a line through
/// the points the user already has. The honest companion to a paid
/// ML-prediction tier: it only speaks when the data actually supports a
/// projection.
public struct WearProjection: Sendable, Equatable {
    public enum Status: Sendable, Equatable {
        /// Wear is measurably climbing; `date` is when it reaches the target
        /// at the current rate, `perYearPercent` is the fitted slope ×365.
        case projected(date: Date, perYearPercent: Double)
        /// Enough history, but wear hasn't moved — common (and good) on
        /// lightly-used or Apple SSDs that report wear in coarse steps.
        case flat
        /// Not enough span or samples to say anything yet.
        case insufficientData
    }

    public let status: Status
    public let currentPercent: Int
    public let spanDays: Double
    public let target: Int
}

public enum WearTrendAnalyzer {
    /// Minimum observation window and sample count before we'll project.
    /// Wear moves slowly and `percentage_used` is integer-quantized, so a
    /// couple of days of 5-minute samples is the floor for any signal.
    static let minSpanDays = 2.0
    static let minSamples = 5
    /// Below this fitted slope (≈0.18 %/yr) we call it flat rather than
    /// pretend a multi-century projection is meaningful.
    static let flatSlopePerDay = 0.0005

    public static func analyze(
        samples: [HealthSample],
        target: Int = 100,
        now: Date = Date()
    ) -> WearProjection? {
        // Newest-first or oldest-first both arrive here; normalize to ascending.
        let points = samples
            .compactMap { s -> (t: Date, y: Double)? in
                s.percentageUsed.map { (s.timestamp, Double($0)) }
            }
            .sorted { $0.t < $1.t }

        guard let first = points.first, let last = points.last else { return nil }
        let current = Int(last.y.rounded())
        let spanDays = last.t.timeIntervalSince(first.t) / 86_400

        guard points.count >= minSamples, spanDays >= minSpanDays else {
            return WearProjection(status: .insufficientData, currentPercent: current,
                                  spanDays: spanDays, target: target)
        }

        // OLS slope of wear (%) over time (days), x measured from `first`.
        let xs = points.map { $0.t.timeIntervalSince(first.t) / 86_400 }
        let ys = points.map(\.y)
        let n = Double(points.count)
        let meanX = xs.reduce(0, +) / n
        let meanY = ys.reduce(0, +) / n
        var sxx = 0.0, sxy = 0.0
        for i in points.indices {
            let dx = xs[i] - meanX
            sxx += dx * dx
            sxy += dx * (ys[i] - meanY)
        }
        guard sxx > 0 else {
            return WearProjection(status: .flat, currentPercent: current,
                                  spanDays: spanDays, target: target)
        }
        let slopePerDay = sxy / sxx     // % per day

        let observedDelta = last.y - first.y
        if slopePerDay < flatSlopePerDay || observedDelta < 1 {
            return WearProjection(status: .flat, currentPercent: current,
                                  spanDays: spanDays, target: target)
        }

        let remaining = Double(target) - last.y
        guard remaining > 0 else {
            return WearProjection(status: .flat, currentPercent: current,
                                  spanDays: spanDays, target: target)
        }
        let daysToTarget = remaining / slopePerDay
        let date = now.addingTimeInterval(daysToTarget * 86_400)
        return WearProjection(
            status: .projected(date: date, perYearPercent: slopePerDay * 365),
            currentPercent: current,
            spanDays: spanDays,
            target: target
        )
    }
}
