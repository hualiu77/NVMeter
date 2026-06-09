import Foundation

struct ReportRecord: Codable, Sendable {
    var firstReportedAt: Date
    var lastReportedAt: Date
    var count: Int
}

/// Persists the user's history of "Help map this enclosure" submissions
/// keyed by model hint, so we can warn before opening a duplicate Issue.
///
/// Stored at `~/Library/Application Support/NVMeter/reported.json`.
/// Plain JSON — easy to inspect, easy to wipe.
@MainActor
final class ReportHistory {
    static let shared = ReportHistory()

    private let url: URL
    private var byModel: [String: ReportRecord] = [:]

    private init() {
        let dir = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        ).appendingPathComponent("NVMeter", isDirectory: true)) ?? URL(fileURLWithPath: "/tmp")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("reported.json")
        load()
    }

    func lastReport(for model: String) -> ReportRecord? {
        byModel[normalize(model)]
    }

    func recordSubmission(model: String) {
        let key = normalize(model)
        let now = Date()
        if var existing = byModel[key] {
            existing.lastReportedAt = now
            existing.count += 1
            byModel[key] = existing
        } else {
            byModel[key] = ReportRecord(firstReportedAt: now, lastReportedAt: now, count: 1)
        }
        save()
    }

    // MARK: - persistence

    private func load() {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: ReportRecord].self, from: data)
        else { return }
        byModel = decoded
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(byModel) {
            try? data.write(to: url, options: [.atomic])
        }
    }

    private func normalize(_ model: String) -> String {
        model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
