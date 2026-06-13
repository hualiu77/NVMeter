import Foundation
import GRDB

/// One persisted benchmark run. `results` and `samples` are stored as JSON
/// blobs so the schema stays flat while keeping the full speed+temperature
/// timeline for the history comparison cards.
public struct SpeedRunRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    public var id: Int64?
    public var deviceName: String
    public var devicePath: String
    public var startedAt: Date
    public var durationSeconds: Double
    public var bytesWritten: Int64
    public var resultsJSON: Data
    public var samplesJSON: Data

    public static let databaseTableName = "speed_run"

    public var results: [ProfileResult] {
        (try? JSONDecoder().decode([ProfileResult].self, from: resultsJSON)) ?? []
    }
    public var samples: [SpeedSample] {
        (try? JSONDecoder().decode([SpeedSample].self, from: samplesJSON)) ?? []
    }

    /// Peak sequential read MB/s — the headline figure for a row.
    public var headlineRead: Double? {
        results.filter { $0.isRead && $0.profileID.hasPrefix("seq1m-q8t1") }.map(\.mbPerSec).max()
    }
    public var headlineWrite: Double? {
        results.filter { !$0.isRead && $0.profileID.hasPrefix("seq1m-q8t1") }.map(\.mbPerSec).max()
    }
}

public final class SpeedTestStore {
    private let dbQueue: DatabaseQueue

    public init(url: URL) throws {
        self.dbQueue = try DatabaseQueue(path: url.path)
        try migrate()
    }

    private func migrate() throws {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "speed_run") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("deviceName", .text).notNull()
                t.column("devicePath", .text).notNull().indexed()
                t.column("startedAt", .datetime).notNull()
                t.column("durationSeconds", .double).notNull()
                t.column("bytesWritten", .integer).notNull()
                t.column("resultsJSON", .blob).notNull()
                t.column("samplesJSON", .blob).notNull()
            }
        }
        try migrator.migrate(dbQueue)
    }

    public func insert(run: SpeedTestRun, deviceName: String, devicePath: String) throws {
        let encoder = JSONEncoder()
        var record = SpeedRunRecord(
            id: nil,
            deviceName: deviceName,
            devicePath: devicePath,
            startedAt: run.startedAt,
            durationSeconds: run.durationSeconds,
            bytesWritten: run.bytesWritten,
            resultsJSON: (try? encoder.encode(run.results)) ?? Data(),
            samplesJSON: (try? encoder.encode(run.samples)) ?? Data()
        )
        try dbQueue.write { db in try record.insert(db) }
    }

    public func recent(devicePath: String, limit: Int = 50) throws -> [SpeedRunRecord] {
        try dbQueue.read { db in
            try SpeedRunRecord
                .filter(Column("devicePath") == devicePath)
                .order(Column("startedAt").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    public func allRecent(limit: Int = 50) throws -> [SpeedRunRecord] {
        try dbQueue.read { db in
            try SpeedRunRecord.order(Column("startedAt").desc).limit(limit).fetchAll(db)
        }
    }
}
