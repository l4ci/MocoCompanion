import Foundation
import os
import SQLite3

enum DatabaseError: Error, LocalizedError {
    case openFailed(String, code: Int32)
    case prepareFailed(String, code: Int32)
    case executionFailed(String, code: Int32)
    case queryFailed(String, code: Int32)

    var errorDescription: String? {
        switch self {
        case .openFailed(let msg, _): msg
        case .prepareFailed(let msg, _): msg
        case .executionFailed(let msg, _): msg
        case .queryFailed(let msg, _): msg
        }
    }

    /// The underlying sqlite3 primary result code (e.g. `SQLITE_BUSY` = 5,
    /// `SQLITE_CORRUPT` = 11, `SQLITE_NOTADB` = 26). `openRecovering` uses
    /// this to tell genuine corruption apart from a transient condition —
    /// most importantly a lock held by another connection — which must not
    /// be treated as corruption.
    var sqliteCode: Int32 {
        switch self {
        case .openFailed(_, let code), .prepareFailed(_, let code),
             .executionFailed(_, let code), .queryFailed(_, let code):
            code
        }
    }
}

/// Thin wrapper over the system sqlite3 C API.
/// Not Sendable — intended to be owned by a serializing actor (ShadowEntryStore).
final class SQLiteDatabase {

    private var db: OpaquePointer?

    /// Opens (or creates) a SQLite database at the given path.
    /// Pass ":memory:" for an in-memory database.
    ///
    /// - Parameter busyTimeoutMillis: How long a call should block waiting on
    ///   a lock held by another connection before giving up with
    ///   `SQLITE_BUSY`, instead of failing immediately. Defaults to 2s, which
    ///   comfortably covers a brief overlap with another process's writer.
    ///   Tests that need to exercise the busy path deterministically without
    ///   a real multi-second wait can pass a much smaller value.
    init(path: String, busyTimeoutMillis: Int32 = 2000) throws {
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let result = sqlite3_open_v2(path, &db, flags, nil)
        guard result == SQLITE_OK else {
            let msg = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            sqlite3_close(db)
            db = nil
            throw DatabaseError.openFailed("Failed to open database: \(msg)", code: result)
        }

        sqlite3_busy_timeout(db, busyTimeoutMillis)

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
        guard let db else { throw DatabaseError.executionFailed("Database not open", code: SQLITE_MISUSE) }
        var stmt: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        guard prepareResult == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DatabaseError.prepareFailed("Prepare failed: \(msg)\nSQL: \(sql)", code: prepareResult)
        }
        defer { sqlite3_finalize(stmt) }

        bind(stmt!, params: params)

        let stepResult = sqlite3_step(stmt)
        guard stepResult == SQLITE_DONE || stepResult == SQLITE_ROW else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DatabaseError.executionFailed("Execution failed: \(msg)\nSQL: \(sql)", code: stepResult)
        }
    }

    // MARK: - Query (SELECT)

    func query(_ sql: String, params: [Any?] = []) throws -> [[String: Any]] {
        guard let db else { throw DatabaseError.queryFailed("Database not open", code: SQLITE_MISUSE) }
        var stmt: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        guard prepareResult == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DatabaseError.prepareFailed("Prepare failed: \(msg)\nSQL: \(sql)", code: prepareResult)
        }
        defer { sqlite3_finalize(stmt) }

        bind(stmt!, params: params)

        var rows: [[String: Any]] = []
        let columnCount = sqlite3_column_count(stmt)

        var stepResult = sqlite3_step(stmt)
        while stepResult == SQLITE_ROW {
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
            stepResult = sqlite3_step(stmt)
        }
        guard stepResult == SQLITE_DONE else {
            // Previously this loop treated ANY non-ROW step result as "no
            // more rows", silently swallowing SQLITE_BUSY/SQLITE_LOCKED (and
            // real errors) as an empty result set. That masked exactly the
            // failures `openRecovering`'s probe/quick_check need to see.
            let msg = String(cString: sqlite3_errmsg(db))
            throw DatabaseError.executionFailed("Query failed: \(msg)\nSQL: \(sql)", code: stepResult)
        }
        return rows
    }

    // MARK: - Convenience

    var lastInsertRowId: Int64 {
        guard let db else { return 0 }
        return sqlite3_last_insert_rowid(db)
    }

    /// Number of rows inserted/updated/deleted by the most recently
    /// completed INSERT/UPDATE/DELETE on this connection. Lets callers get a
    /// delete's row count for free instead of a separate `SELECT COUNT(*)`.
    var changes: Int {
        guard let db else { return 0 }
        return Int(sqlite3_changes(db))
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

    /// Cheap read confirming the database is minimally usable — much
    /// cheaper than `PRAGMA quick_check`, which does an O(pages) scan. Safe
    /// to run on every launch for all three on-disk databases; only escalated
    /// to `quickCheckPasses()` if this fails.
    private func probeReadable() throws {
        _ = try query("SELECT 1 FROM sqlite_master LIMIT 1")
    }

    /// `PRAGMA quick_check` — a thorough (but O(pages)) verification that the
    /// file is a well-formed, readable SQLite database (catches garbage
    /// bytes, truncation, or a corrupt header) without doing a full
    /// `integrity_check` scan. Only run when `probeReadable()` fails, since
    /// it's the expensive path. Does not replace each store's own schema
    /// migrations.
    private func quickCheckPasses() throws -> Bool {
        (try query("PRAGMA quick_check")).first?["quick_check"] as? String == "ok"
    }

    /// Opens `path` and confirms it's healthy, closing it again on any
    /// failure so callers never end up holding a half-open connection.
    /// Returns the classifying `DatabaseError` on failure so `openRecovering`
    /// can tell genuine corruption apart from something transient (most
    /// importantly a lock held by another connection).
    private static func attemptOpen(atPath path: String, busyTimeoutMillis: Int32) -> Result<SQLiteDatabase, DatabaseError> {
        let db: SQLiteDatabase
        do {
            db = try SQLiteDatabase(path: path, busyTimeoutMillis: busyTimeoutMillis)
        } catch let error as DatabaseError {
            return .failure(error)
        } catch {
            return .failure(.openFailed("\(error)", code: SQLITE_ERROR))
        }

        do {
            try db.probeReadable()
            return .success(db)
        } catch let probeError as DatabaseError {
            do {
                if try db.quickCheckPasses() {
                    // quick_check overrides the probe failure — it's the more
                    // thorough check and found nothing wrong.
                    return .success(db)
                }
                db.close()
                return .failure(.queryFailed("PRAGMA quick_check reported corruption", code: SQLITE_CORRUPT))
            } catch let quickCheckError as DatabaseError {
                db.close()
                return .failure(quickCheckError)
            } catch {
                db.close()
                return .failure(probeError)
            }
        } catch {
            db.close()
            return .failure(.queryFailed("\(error)", code: SQLITE_ERROR))
        }
    }

    /// Whether `code` (from an open/probe/quick_check failure) indicates
    /// genuine file corruption that warrants quarantining the file, as
    /// opposed to a transient condition — most notably `SQLITE_BUSY`/
    /// `SQLITE_LOCKED` from another connection holding a lock — which must
    /// leave a perfectly healthy file alone.
    private static func isCorruption(code: Int32, atPath path: String) -> Bool {
        switch code {
        case SQLITE_CORRUPT, SQLITE_NOTADB, SQLITE_FORMAT:
            return true
        case SQLITE_CANTOPEN:
            // CANTOPEN also covers an unwritable/missing directory, which
            // isn't corruption — only quarantine when the file itself
            // exists but sqlite still couldn't open it as a database.
            return path != ":memory:" && FileManager.default.fileExists(atPath: path)
        default:
            return false
        }
    }

    /// Opens the database at `path`, recovering automatically instead of
    /// crashing when the file is corrupt. A corrupt file left in place would
    /// otherwise crash the app on every launch (the store's `init` throws,
    /// which callers previously turned into `fatalError`).
    ///
    /// If the file can't be opened, or opens but fails the health check, and
    /// the failure's sqlite result code indicates genuine corruption
    /// (`SQLITE_CORRUPT`/`SQLITE_NOTADB`/`SQLITE_FORMAT`, or `SQLITE_CANTOPEN`
    /// with the file present but unreadable as a database) — it, along with
    /// any `-wal`/`-shm` siblings, is renamed aside with a
    /// `.corrupt-<yyyyMMdd-HHmmss>` suffix, logged via `Logger` and
    /// `BreadcrumbTrail`, and a fresh database is opened at the original
    /// path.
    ///
    /// Any other failure — most importantly `SQLITE_BUSY`/`SQLITE_LOCKED`
    /// from another connection holding a lock on an otherwise healthy file —
    /// is rethrown untouched, without quarantining anything. Callers keep
    /// their existing handling of that (currently `fatalError`), which is
    /// still correct: the difference is only that a healthy-but-contended
    /// file no longer gets destroyed on the way there.
    ///
    /// - Parameters:
    ///   - path: On-disk path, or `":memory:"` (never corrupt; passed through).
    ///   - logger: Category-scoped logger for the owning store.
    ///   - label: Short name identifying the database in logs/breadcrumbs
    ///     (e.g. `"shadow.db"`).
    ///   - busyTimeoutMillis: Forwarded to `SQLiteDatabase.init`; see there.
    static func openRecovering(atPath path: String, logger: Logger, label: String, busyTimeoutMillis: Int32 = 2000) throws -> SQLiteDatabase {
        switch attemptOpen(atPath: path, busyTimeoutMillis: busyTimeoutMillis) {
        case .success(let db):
            return db
        case .failure(let error):
            guard isCorruption(code: error.sqliteCode, atPath: path) else {
                throw error
            }
            logger.error("\(label): database at \(path) is corrupt (sqlite code \(error.sqliteCode)) — quarantining and starting fresh")
            quarantineCorruptFiles(atPath: path, logger: logger, label: label)
            return try SQLiteDatabase(path: path, busyTimeoutMillis: busyTimeoutMillis)
        }
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
