import Foundation
import os

/// Stores app usage records in a local SQLite database. Serializes all
/// SQLite access through this actor via `SQLiteDatabase` — mirrors
/// `ShadowEntryStore`'s ownership pattern. Every call site now `await`s,
/// which moves disk IO for Autotracker segment flushes and timeline loads
/// off the main actor instead of blocking it on every app/window focus
/// switch.
actor AppRecordStore {
    private static let logger = Logger(category: "AppRecordStore")

    private let database: SQLiteDatabase

    nonisolated(unsafe) private static let dateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// - Parameter inMemory: `true` for tests (`:memory:` SQLite DB). The
    ///   default computes the same on-disk path this store used before the
    ///   actor port — `Application Support/MocoCompanion/app_records.sqlite`
    ///   — so existing installs keep their history.
    init(inMemory: Bool = false) throws {
        let path: String
        if inMemory {
            path = ":memory:"
        } else {
            let dir = URL.applicationSupportDirectory
                .appendingPathComponent("MocoCompanion", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            path = dir.appendingPathComponent("app_records.sqlite").path
        }
        database = try SQLiteDatabase(path: path)
        try database.createTable(sql: Self.createTableSQL)
        try database.execute("CREATE INDEX IF NOT EXISTS idx_app_records_timestamp ON app_records(timestamp)")
    }

    private static let createTableSQL = """
        CREATE TABLE IF NOT EXISTS app_records (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp TEXT NOT NULL,
            app_bundle_id TEXT NOT NULL,
            app_name TEXT NOT NULL,
            window_title TEXT,
            duration_seconds REAL NOT NULL
        )
        """

    // MARK: - Writes

    func insert(_ record: AppRecord) {
        insertMany([record])
    }

    /// Insert one or more records in a single SQLite transaction. Using a
    /// transaction for even a single insert avoids the implicit
    /// per-statement BEGIN/COMMIT cycle (with its fsync on
    /// journal_mode=DELETE), which is the dominant cost of per-segment
    /// writes in Autotracker. A single record's insert failure is logged
    /// and skipped so one bad row doesn't drop the rest of the batch; only
    /// a failure to begin or commit the transaction rolls back everything.
    func insertMany(_ records: [AppRecord]) {
        guard !records.isEmpty else { return }
        do {
            try database.transaction {
                for record in records {
                    do {
                        try database.execute(Self.insertSQL, params: [
                            Self.dateFormatter.string(from: record.timestamp),
                            record.appBundleId,
                            record.appName,
                            record.windowTitle,
                            record.durationSeconds,
                        ])
                    } catch {
                        Self.logger.error("Failed to insert record: \(error)")
                    }
                }
            }
        } catch {
            Self.logger.error("Failed to commit batch insert: \(error)")
        }
    }

    // MARK: - Reads

    func records(for date: Date) -> [AppRecord] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else { return [] }

        let startStr = Self.dateFormatter.string(from: startOfDay)
        let endStr = Self.dateFormatter.string(from: endOfDay)

        do {
            let rows = try database.query(Self.selectByDateSQL, params: [startStr, endStr])
            return rows.compactMap(Self.recordFromRow)
        } catch {
            Self.logger.error("Failed to query records: \(error)")
            return []
        }
    }

    func recordCount() -> Int {
        do {
            let rows = try database.query("SELECT COUNT(*) as count FROM app_records")
            return (rows.first?["count"] as? Int64).map(Int.init) ?? 0
        } catch {
            Self.logger.error("Failed to count records: \(error)")
            return 0
        }
    }

    // MARK: - Cleanup

    func cleanup(olderThan days: Int) {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date.now) else { return }
        let cutoffStr = Self.dateFormatter.string(from: cutoff)
        do {
            try database.execute("DELETE FROM app_records WHERE timestamp < ?", params: [cutoffStr])
        } catch {
            Self.logger.error("Failed to execute cleanup: \(error)")
        }
    }

    // MARK: - SQL

    private static let insertSQL = """
        INSERT INTO app_records (timestamp, app_bundle_id, app_name, window_title, duration_seconds) \
        VALUES (?, ?, ?, ?, ?)
        """

    private static let selectByDateSQL = """
        SELECT id, timestamp, app_bundle_id, app_name, window_title, duration_seconds \
        FROM app_records WHERE timestamp >= ? AND timestamp < ? ORDER BY timestamp ASC
        """

    private static func recordFromRow(_ row: [String: Any]) -> AppRecord? {
        guard let tsRaw = row["timestamp"] as? String,
              let timestamp = dateFormatter.date(from: tsRaw),
              let bundleId = row["app_bundle_id"] as? String,
              let name = row["app_name"] as? String else { return nil }

        return AppRecord(
            id: row["id"] as? Int64,
            timestamp: timestamp,
            appBundleId: bundleId,
            appName: name,
            windowTitle: row["window_title"] as? String,
            durationSeconds: (row["duration_seconds"] as? Double) ?? 0
        )
    }
}
