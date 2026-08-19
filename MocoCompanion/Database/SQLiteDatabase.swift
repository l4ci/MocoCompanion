import Foundation
import os
import SQLite3

enum DatabaseError: Error, LocalizedError {
    case openFailed(String)
    case prepareFailed(String)
    case executionFailed(String)
    case queryFailed(String)

    var errorDescription: String? {
        switch self {
        case .openFailed(let msg): msg
        case .prepareFailed(let msg): msg
        case .executionFailed(let msg): msg
        case .queryFailed(let msg): msg
        }
    }
}

/// Thin wrapper over the system sqlite3 C API.
/// Not Sendable — intended to be owned by a serializing actor (ShadowEntryStore).
final class SQLiteDatabase {

    private var db: OpaquePointer?

    /// Opens (or creates) a SQLite database at the given path.
    /// Pass ":memory:" for an in-memory database.
    init(path: String) throws {
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let result = sqlite3_open_v2(path, &db, flags, nil)
        guard result == SQLITE_OK else {
            let msg = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            sqlite3_close(db)
            db = nil
            throw DatabaseError.openFailed("Failed to open database: \(msg)")
        }

        // WAL lets readers and a writer proceed concurrently instead of the
        // default rollback journal's exclusive-writer lock, and NORMAL
        // synchronous is the safe pairing with WAL (still durable across app
        // crashes, only risks losing the last few transactions on a full OS
        // crash/power loss). Skipped for in-memory databases (used in tests):
        // WAL is a no-op there since SQLite keeps ":memory:" pages entirely
        // in memory regardless of journal mode, but issuing the PRAGMA is
        // still harmless if it were ever hit.
        if path != ":memory:" {
            try execute("PRAGMA journal_mode=WAL")
            try execute("PRAGMA synchronous=NORMAL")
        }
    }

    deinit {
        close()
    }

    func close() {
        if let db {
            sqlite3_close(db)
        }
        db = nil
    }

    // MARK: - Schema versioning

    var userVersion: Int {
        get {
            guard let db else { return 0 }
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, "PRAGMA user_version", -1, &stmt, nil) == SQLITE_OK,
                  sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
            return Int(sqlite3_column_int64(stmt, 0))
        }
        set {
            try? execute("PRAGMA user_version = \(newValue)")
        }
    }

    // MARK: - Execute (INSERT/UPDATE/DELETE/DDL)

    func execute(_ sql: String, params: [Any?] = []) throws {
        guard let db else { throw DatabaseError.executionFailed("Database not open") }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DatabaseError.prepareFailed("Prepare failed: \(msg)\nSQL: \(sql)")
        }
        defer { sqlite3_finalize(stmt) }

        bind(stmt!, params: params)

        let stepResult = sqlite3_step(stmt)
        guard stepResult == SQLITE_DONE || stepResult == SQLITE_ROW else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DatabaseError.executionFailed("Execution failed: \(msg)\nSQL: \(sql)")
        }
    }

    // MARK: - Query (SELECT)

    func query(_ sql: String, params: [Any?] = []) throws -> [[String: Any]] {
        guard let db else { throw DatabaseError.queryFailed("Database not open") }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DatabaseError.prepareFailed("Prepare failed: \(msg)\nSQL: \(sql)")
        }
        defer { sqlite3_finalize(stmt) }

        bind(stmt!, params: params)

        var rows: [[String: Any]] = []
        let columnCount = sqlite3_column_count(stmt)

        while sqlite3_step(stmt) == SQLITE_ROW {
            var row: [String: Any] = [:]
            for i in 0..<columnCount {
                let name = String(cString: sqlite3_column_name(stmt, i))
                switch sqlite3_column_type(stmt, i) {
                case SQLITE_INTEGER:
                    row[name] = sqlite3_column_int64(stmt, i)
                case SQLITE_FLOAT:
                    row[name] = sqlite3_column_double(stmt, i)
                case SQLITE_TEXT:
                    row[name] = String(cString: sqlite3_column_text(stmt, i))
                case SQLITE_NULL:
                    row[name] = NSNull()
                default:
                    row[name] = NSNull()
                }
            }
            rows.append(row)
        }
        return rows
    }

    // MARK: - Convenience

    var lastInsertRowId: Int64 {
        guard let db else { return 0 }
        return sqlite3_last_insert_rowid(db)
    }

    func createTable(sql: String) throws {
        try execute(sql)
    }

    /// Runs `body` inside a `BEGIN IMMEDIATE` / `COMMIT` transaction — avoids
    /// the implicit per-statement transaction cycle (with its fsync) that
    /// SQLite otherwise wraps around every individual `execute` call, the
    /// dominant cost of batched writes. Rolls back and rethrows if `body`
    /// throws or if `COMMIT` itself fails.
    func transaction(_ body: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE")
        do {
            try body()
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    // MARK: - Private

    // MARK: - Recovery

    /// `PRAGMA quick_check` cheaply verifies the file is a well-formed,
    /// readable SQLite database (catches garbage bytes, truncation, or a
    /// corrupt header) without doing a full `integrity_check` scan. It does
    /// not replace each store's own schema migrations.
    fileprivate var passesQuickCheck: Bool {
        (try? query("PRAGMA quick_check"))?.first?["quick_check"] as? String == "ok"
    }

    /// Opens the database at `path`, recovering automatically instead of
    /// crashing when the file is corrupt. A corrupt file left in place would
    /// otherwise crash the app on every launch (the store's `init` throws,
    /// which callers previously turned into `fatalError`).
    ///
    /// If the file can't be opened, or opens but fails `PRAGMA quick_check`,
    /// it — along with any `-wal`/`-shm` siblings — is renamed aside with a
    /// `.corrupt-<yyyyMMdd-HHmmss>` suffix, logged via `Logger` and
    /// `BreadcrumbTrail`, and a fresh database is opened at the original
    /// path. Only throws if even a fresh database can't be created there
    /// (e.g. the directory is unwritable) — that case is truly unrecoverable
    /// and callers should still treat it as fatal.
    ///
    /// - Parameters:
    ///   - path: On-disk path, or `":memory:"` (never corrupt; passed through).
    ///   - logger: Category-scoped logger for the owning store.
    ///   - label: Short name identifying the database in logs/breadcrumbs
    ///     (e.g. `"shadow.db"`).
    static func openRecovering(atPath path: String, logger: Logger, label: String) throws -> SQLiteDatabase {
        if let db = try? SQLiteDatabase(path: path), db.passesQuickCheck {
            return db
        }

        logger.error("\(label): database at \(path) is missing or corrupt — quarantining and starting fresh")
        quarantineCorruptFiles(atPath: path, logger: logger, label: label)

        return try SQLiteDatabase(path: path)
    }

    private static func quarantineCorruptFiles(atPath path: String, logger: Logger, label: String) {
        guard path != ":memory:" else { return }
        let fm = FileManager.default
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let suffix = formatter.string(from: .now)

        var quarantinedAny = false
        for candidate in [path, path + "-wal", path + "-shm"] {
            guard fm.fileExists(atPath: candidate) else { continue }
            let quarantined = "\(candidate).corrupt-\(suffix)"
            try? fm.removeItem(atPath: quarantined)
            do {
                try fm.moveItem(atPath: candidate, toPath: quarantined)
                quarantinedAny = true
                logger.error("\(label): moved \(candidate) aside to \(quarantined)")
            } catch {
                logger.error("\(label): failed to quarantine \(candidate): \(error)")
            }
        }

        if quarantinedAny {
            BreadcrumbTrail.shared.record(label, "Corrupt database recovered: quarantined and reopened fresh")
        }
    }

    private func bind(_ stmt: OpaquePointer, params: [Any?]) {
        for (index, param) in params.enumerated() {
            let idx = Int32(index + 1)
            switch param {
            case nil:
                sqlite3_bind_null(stmt, idx)
            case let value as Int:
                sqlite3_bind_int64(stmt, idx, Int64(value))
            case let value as Int64:
                sqlite3_bind_int64(stmt, idx, value)
            case let value as Double:
                sqlite3_bind_double(stmt, idx, value)
            case let value as String:
                sqlite3_bind_text(stmt, idx, (value as NSString).utf8String, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            case let value as Bool:
                sqlite3_bind_int64(stmt, idx, value ? 1 : 0)
            default:
                sqlite3_bind_null(stmt, idx)
            }
        }
    }
}
