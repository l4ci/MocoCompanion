import Foundation

/// Centralizes on-disk paths for the app's SQLite databases so every store
/// that opens one, and the "Reset Everything" flow that clears them, agree
/// on where they live. Previously each store computed its own path inline;
/// a mismatch there would leave databases either un-reset or unopenable.
enum DatabasePaths {
    /// `Application Support/MocoCompanion/`, created on first access.
    static var applicationSupportDirectory: URL {
        let dir = URL.applicationSupportDirectory.appendingPathComponent("MocoCompanion", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Shadow (local) time entries — `ShadowEntryStore`.
    static var shadowEntries: URL { applicationSupportDirectory.appendingPathComponent("shadow.db") }

    /// Autotracker automation rules — `RuleStore`.
    static var rules: URL { applicationSupportDirectory.appendingPathComponent("rules.sqlite") }

    /// Autotracker recorded app/window activity — `AppRecordStore`.
    static var appRecords: URL { applicationSupportDirectory.appendingPathComponent("app_records.sqlite") }

    /// All primary database files. Does not include `-wal`/`-shm` siblings —
    /// see `SQLiteDatabase.siblingFiles(of:)` for those.
    static var all: [URL] { [shadowEntries, rules, appRecords] }
}
