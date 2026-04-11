import Foundation
import SQLite3
import os

/// Stores app usage records in a local SQLite database.
@Observable
@MainActor
final class AppRecordStore {
    private static let logger = Logger(category: "AppRecordStore")

    /// SQLite connection handle. Must remain accessible from deinit (which
    /// is nonisolated) so the connection is closed on last release.
    /// Swift warns that `nonisolated(unsafe)` is redundant here, but
    /// removing it breaks the deinit — `db` becomes @MainActor-isolated and
    /// cannot be referenced from the nonisolated deinit. Keep this until
    /// Swift supports `isolated deinit` on @Observable classes.
    // swiftlint:disable:next redundant_nonisolated_unsafe
    nonisolated(unsafe) private var db: OpaquePointer?
    private static let dateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    init(inMemory: Bool = false) {
        if inMemory {
            open(path: ":memory:")
        } else {
            let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("MocoCompanion", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let path = dir.appendingPathComponent("app_records.sqlite").path
            open(path: path)
        }
    }

    private func open(path: String) {
        if sqlite3_open(path, &db) != SQLITE_OK {
            let err = dbError
            Self.logger.error("Failed to open database at \(path): \(err)")
            return
        }
        createTable()
    }

    private func createTable() {
        let sql = """
            CREATE TABLE IF NOT EXISTS app_records (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp TEXT NOT NULL,
                app_bundle_id TEXT NOT NULL,
                app_name TEXT NOT NULL,
                window_title TEXT,
                duration_seconds REAL NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_app_records_timestamp ON app_records(timestamp);
            """
        var errMsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &errMsg) != SQLITE_OK {
            let msg = errMsg.map { String(cString: $0) } ?? "unknown"
            Self.logger.error("Failed to create table: \(msg)")
            sqlite3_free(errMsg)
        }
    }

    func insert(_ record: AppRecord) {
        insertMany([record])
    }

    /// Insert one or more records in a single SQLite transaction. Using a
    /// transaction for even a single insert avoids the implicit per-statement
    /// BEGIN/COMMIT cycle (with its fsync on journal_mode=DELETE), which is
    /// the dominant cost of per-segment writes in Autotracker. Failing
    /// inserts are logged individually; a fatal bind failure rolls back the
    /// entire batch so partial state isn't persisted.
    func insertMany(_ records: [AppRecord]) {
        guard !records.isEmpty else { return }
        guard let db else { return }

        if sqlite3_exec(db, "BEGIN IMMEDIATE", nil, nil, nil) != SQLITE_OK {
            Self.logger.error("Failed to begin transaction: \(self.dbError)")
            return
        }

        let sql = "INSERT INTO app_records (timestamp, app_bundle_id, app_name, window_title, duration_seconds) VALUES (?, ?, ?, ?, ?)"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            Self.logger.error("Failed to prepare insert: \(self.dbError)")
            sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
            return
        }
        defer { sqlite3_finalize(stmt) }

        for record in records {
            sqlite3_reset(stmt)
            sqlite3_clear_bindings(stmt)

            let ts = Self.dateFormatter.string(from: record.timestamp)
            sqlite3_bind_text(stmt, 1, (ts as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 2, (record.appBundleId as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 3, (record.appName as NSString).utf8String, -1, nil)
            if let title = record.windowTitle {
                sqlite3_bind_text(stmt, 4, (title as NSString).utf8String, -1, nil)
            } else {
                sqlite3_bind_null(stmt, 4)
            }
            sqlite3_bind_double(stmt, 5, record.durationSeconds)

            if sqlite3_step(stmt) != SQLITE_DONE {
                Self.logger.error("Failed to insert record: \(self.dbError)")
            }
        }

        if sqlite3_exec(db, "COMMIT", nil, nil, nil) != SQLITE_OK {
            Self.logger.error("Failed to commit batch insert: \(self.dbError)")
            sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
        }
    }

    func records(for date: Date) -> [AppRecord] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        let startStr = Self.dateFormatter.string(from: startOfDay)
        let endStr = Self.dateFormatter.string(from: endOfDay)

        let sql = "SELECT id, timestamp, app_bundle_id, app_name, window_title, duration_seconds FROM app_records WHERE timestamp >= ? AND timestamp < ? ORDER BY timestamp ASC"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            let err = dbError
            Self.logger.error("Failed to prepare query: \(err)")
            return []
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (startStr as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (endStr as NSString).utf8String, -1, nil)

        var results: [AppRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let record = readRow(stmt) {
                results.append(record)
            }
        }
        return results
    }

    func recordCount() -> Int {
        let sql = "SELECT COUNT(*) FROM app_records"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(stmt) }
        return sqlite3_step(stmt) == SQLITE_ROW ? Int(sqlite3_column_int64(stmt, 0)) : 0
    }

    func cleanup(olderThan days: Int) {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        let cutoffStr = Self.dateFormatter.string(from: cutoff)
        let sql = "DELETE FROM app_records WHERE timestamp < ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            let err = dbError
            Self.logger.error("Failed to prepare cleanup: \(err)")
            return
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, (cutoffStr as NSString).utf8String, -1, nil)
        if sqlite3_step(stmt) != SQLITE_DONE {
            let err = dbError
            Self.logger.error("Failed to execute cleanup: \(err)")
        }
    }

    deinit {
        sqlite3_close(db)
    }

    // MARK: - Private

    private var dbError: String {
        db.map { String(cString: sqlite3_errmsg($0)) } ?? "no db"
    }

    private func readRow(_ stmt: OpaquePointer?) -> AppRecord? {
        guard let stmt else { return nil }
        let id = sqlite3_column_int64(stmt, 0)
        guard let tsRaw = sqlite3_column_text(stmt, 1),
              let timestamp = Self.dateFormatter.date(from: String(cString: tsRaw)),
              let bundleRaw = sqlite3_column_text(stmt, 2),
              let nameRaw = sqlite3_column_text(stmt, 3) else { return nil }

        let windowTitle: String? = sqlite3_column_type(stmt, 4) != SQLITE_NULL
            ? String(cString: sqlite3_column_text(stmt, 4))
            : nil

        return AppRecord(
            id: id,
            timestamp: timestamp,
            appBundleId: String(cString: bundleRaw),
            appName: String(cString: nameRaw),
            windowTitle: windowTitle,
            durationSeconds: sqlite3_column_double(stmt, 5)
        )
    }
}
