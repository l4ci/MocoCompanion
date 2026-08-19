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

    @Test("openRecovering does not quarantine a healthy file that's locked by another connection")
    func openRecoveringLeavesLockedHealthyFileAlone() throws {
        try withTempDatabasePath { path in
            // Connection A: create the file, then grab an OS-level exclusive
            // lock that outlives any single transaction, so a second
            // connection's queries hit SQLITE_BUSY. (A plain `BEGIN
            // EXCLUSIVE` does NOT achieve this under WAL — WAL readers use
            // snapshot isolation and aren't blocked by a writer's exclusive
            // transaction; `PRAGMA locking_mode=EXCLUSIVE` is what actually
            // locks out other connections, verified empirically.)
            let connectionA = try SQLiteDatabase(path: path)
            try connectionA.execute("CREATE TABLE t (id INTEGER PRIMARY KEY)")
            try connectionA.execute("PRAGMA locking_mode=EXCLUSIVE")
            try connectionA.execute("INSERT INTO t (id) VALUES (1)")

            // A short busy timeout keeps this test fast instead of waiting
            // out the real 2s default.
            #expect(throws: DatabaseError.self) {
                _ = try SQLiteDatabase.openRecovering(
                    atPath: path,
                    logger: Logger(category: "SQLiteDatabaseTests"),
                    label: "test.db",
                    busyTimeoutMillis: 50
                )
            }

            connectionA.close()

            // The file was NOT quarantined — it's healthy, just contended.
            let dir = (path as NSString).deletingLastPathComponent
            let fileName = (path as NSString).lastPathComponent
            let quarantined = (try? FileManager.default.contentsOfDirectory(atPath: dir))?
                .filter { $0.hasPrefix("\(fileName).corrupt-") } ?? []
            #expect(quarantined.isEmpty)
            #expect(FileManager.default.fileExists(atPath: path))

            // Now that the lock is released, the original healthy file opens
            // fine and still has the table connection A created.
            let db = try SQLiteDatabase.openRecovering(
                atPath: path,
                logger: Logger(category: "SQLiteDatabaseTests"),
                label: "test.db"
            )
            let rows = try db.query("SELECT name FROM sqlite_master WHERE type='table' AND name='t'")
            #expect(rows.count == 1)
        }
    }
}
