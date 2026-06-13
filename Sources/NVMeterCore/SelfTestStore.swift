import Foundation
import GRDB

/// One recorded extended self-test run. Persisted so the user keeps a
/// local history of "I ran the long test on this date and it passed",
/// independent of the (short, ring-buffered) on-drive SMART log.
public struct SelfTestRecord: Codable, FetchableRecord, PersistableRecord, Sendable, Identifiable {
    public var id: Int64?
    public var deviceName: String
    public var devicePath: String
    public var serial: String?
    public var startedAt: Date
    public var finishedAt: Date
    public var resultLabel: String
    /// 1 = passed, 0 = failed, nil = aborted / inconclusive.
    public var passed: Bool?
    public var lifetimeHours: Int?

    public static let databaseTableName = "self_test"

    public init(
        id: Int64? = nil,
        deviceName: String,
        devicePath: String,
        serial: String?,
        startedAt: Date,
        finishedAt: Date,
        resultLabel: String,
        passed: Bool?,
        lifetimeHours: Int?
    ) {
        self.id = id
        self.deviceName = deviceName
        self.devicePath = devicePath
        self.serial = serial
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.resultLabel = resultLabel
        self.passed = passed
        self.lifetimeHours = lifetimeHours
    }
}

public final class SelfTestStore {
    private let dbQueue: DatabaseQueue

    public init(url: URL) throws {
        self.dbQueue = try DatabaseQueue(path: url.path)
        try migrate()
    }

    private func migrate() throws {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "self_test") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("deviceName", .text).notNull()
                t.column("devicePath", .text).notNull().indexed()
                t.column("serial", .text)
                t.column("startedAt", .datetime).notNull()
                t.column("finishedAt", .datetime).notNull()
                t.column("resultLabel", .text).notNull()
                t.column("passed", .boolean)
                t.column("lifetimeHours", .integer)
            }
        }
        try migrator.migrate(dbQueue)
    }

    public func insert(_ record: SelfTestRecord) throws {
        try dbQueue.write { db in
            try record.insert(db)
        }
    }

    public func recent(devicePath: String, limit: Int = 50) throws -> [SelfTestRecord] {
        try dbQueue.read { db in
            try SelfTestRecord
                .filter(Column("devicePath") == devicePath)
                .order(Column("startedAt").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }
}
