import Foundation
import os
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

    // MARK: - openRecovering

    @Test("openRecovering quarantines a corrupt file and returns a fresh, working database")
    func openRecoveringQuarantinesCorruptFile() throws {
        try withTempDatabasePath { path in
            // Garbage bytes — not a valid SQLite file.
            try Data("this is definitely not a sqlite database".utf8).write(to: URL(fileURLWithPath: path))

            let db = try SQLiteDatabase.openRecovering(
                atPath: path,
                logger: Logger(category: "SQLiteDatabaseTests"),
                label: "test.db"
            )

            // The returned database is fresh and usable.
            try db.execute("CREATE TABLE t (id INTEGER PRIMARY KEY)")
            try db.execute("INSERT INTO t (id) VALUES (1)")
            let rows = try db.query("SELECT id FROM t")
            #expect(rows.count == 1)

            // The garbage file was moved aside, not left in place or deleted outright.
            let dir = (path as NSString).deletingLastPathComponent
            let fileName = (path as NSString).lastPathComponent
            let quarantined = (try? FileManager.default.contentsOfDirectory(atPath: dir))?
                .filter { $0.hasPrefix("\(fileName).corrupt-") } ?? []
            #expect(!quarantined.isEmpty)
            #expect(FileManager.default.fileExists(atPath: path))

            for name in quarantined {
                try? FileManager.default.removeItem(atPath: (dir as NSString).appendingPathComponent(name))
            }
        }
    }

    @Test("openRecovering opens a healthy file normally, without quarantining it")
    func openRecoveringLeavesHealthyFileAlone() throws {
        try withTempDatabasePath { path in
            _ = try SQLiteDatabase(path: path) // create a valid, empty database first

            let db = try SQLiteDatabase.openRecovering(
                atPath: path,
                logger: Logger(category: "SQLiteDatabaseTests"),
                label: "test.db"
            )
            try db.execute("CREATE TABLE t (id INTEGER PRIMARY KEY)")

            let dir = (path as NSString).deletingLastPathComponent
            let fileName = (path as NSString).lastPathComponent
            let quarantined = (try? FileManager.default.contentsOfDirectory(atPath: dir))?
                .filter { $0.hasPrefix("\(fileName).corrupt-") } ?? []
            #expect(quarantined.isEmpty)
        }
    }
}
