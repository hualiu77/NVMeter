import Foundation
import GRDB

public struct HealthSample: Codable, FetchableRecord, PersistableRecord, Sendable {
    public var id: Int64?
    public var deviceName: String
    public var serial: String?
    public var timestamp: Date
    public var temperatureC: Int?
    public var percentageUsed: Int?
    public var availableSpare: Int?
    public var mediaErrors: Int?
    public var dataUnitsWritten: Int64?
    public var healthLevel: String

    public static let databaseTableName = "health_sample"
}

public final class HistoryStore {
    private let dbQueue: DatabaseQueue
    public let retentionDays: Int

    public init(url: URL, retentionDays: Int = 7) throws {
        self.dbQueue = try DatabaseQueue(path: url.path)
        self.retentionDays = retentionDays
        try migrate()
    }

    private func migrate() throws {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "health_sample") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("deviceName", .text).notNull()
                t.column("serial", .text)
                t.column("timestamp", .datetime).notNull().indexed()
                t.column("temperatureC", .integer)
                t.column("percentageUsed", .integer)
                t.column("availableSpare", .integer)
                t.column("mediaErrors", .integer)
                t.column("dataUnitsWritten", .integer)
                t.column("healthLevel", .text).notNull()
            }
        }
        try migrator.migrate(dbQueue)
    }

    public func insert(_ sample: HealthSample) throws {
        try dbQueue.write { db in
            var s = sample
            try s.insert(db)
        }
    }

    public func recent(device: String, limit: Int = 500) throws -> [HealthSample] {
        try dbQueue.read { db in
            try HealthSample
                .filter(Column("deviceName") == device)
                .order(Column("timestamp").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    public func prune() throws {
        let cutoff = Date().addingTimeInterval(-Double(retentionDays) * 86_400)
        try dbQueue.write { db in
            try HealthSample.filter(Column("timestamp") < cutoff).deleteAll(db)
        }
    }
}
