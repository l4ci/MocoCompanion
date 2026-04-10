import Foundation
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

    // MARK: - Private

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
