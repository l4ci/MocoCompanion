import Foundation
import Testing
@testable import MocoCompanion

@Suite("SQLiteDatabase")
struct SQLiteDatabaseTests {

    /// A fresh temp file path per test, cleaned up afterwards. SQLite's WAL
    /// mode needs a real file — it's a documented no-op on ":memory:" — so
    /// journal-mode assertions require a file-backed database.
    private func withTempDatabasePath(_ body: (String) throws -> Void) rethrows {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("sqlite-database-tests-\(UUID().uuidString).sqlite")
            .path
        defer {
            try? FileManager.default.removeItem(atPath: path)
            try? FileManager.default.removeItem(atPath: path + "-wal")
            try? FileManager.default.removeItem(atPath: path + "-shm")
        }
        try body(path)
    }

    @Test("File-backed database opens in WAL journal mode")
    func fileBackedDatabaseUsesWAL() throws {
        try withTempDatabasePath { path in
            let db = try SQLiteDatabase(path: path)
            let rows = try db.query("PRAGMA journal_mode")
            let mode = rows.first?["journal_mode"] as? String
            #expect(mode?.lowercased() == "wal")
        }
    }

    @Test("File-backed database opens with synchronous=NORMAL")
    func fileBackedDatabaseUsesSynchronousNormal() throws {
        try withTempDatabasePath { path in
            let db = try SQLiteDatabase(path: path)
            let rows = try db.query("PRAGMA synchronous")
            // SQLite reports synchronous as an integer: 0=OFF, 1=NORMAL, 2=FULL.
            let level = rows.first?["synchronous"] as? Int64
            #expect(level == 1)
        }
    }

    @Test("In-memory database opens without error and skips WAL")
    func inMemoryDatabaseOpensCleanly() throws {
        let db = try SQLiteDatabase(path: ":memory:")
        try db.execute("CREATE TABLE t (id INTEGER PRIMARY KEY)")
        try db.execute("INSERT INTO t (id) VALUES (1)")
        let rows = try db.query("SELECT id FROM t")
        #expect(rows.count == 1)
    }
}
