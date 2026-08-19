import Foundation

/// Centralizes on-disk paths for the app's SQLite databases so every store
/// that opens one, and the "Reset Everything" flow that clears them, agree
/// on where they live. Previously each store computed its own path inline;
/// a mismatch there would leave databases either un-reset or unopenable.
enum DatabasePaths {
    /// Under XCTest the test host shares the real user's Application Support
    /// directory, so opening `shadow.db`/`rules.sqlite`/`app_records.sqlite`
    /// there would read and write the developer's real tracked-time data on
    /// every test run. Tests get a per-process temp directory instead — see
    /// KeychainHelper/AppLogger for the same rationale applied to Keychain
    /// and log file access.
    private static let isRunningTests = ProcessInfo.processInfo.isRunningTests

    /// `Application Support/MocoCompanion/`, created on first access. Under
    /// XCTest this resolves to a per-process temp directory instead (see
    /// `isRunningTests` above).
    static var applicationSupportDirectory: URL {
        let dir: URL
        if isRunningTests {
            dir = FileManager.default.temporaryDirectory
                .appendingPathComponent("MocoCompanionTests-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
        } else {
            dir = URL.applicationSupportDirectory.appendingPathComponent("MocoCompanion", isDirectory: true)
        }
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
