import Foundation
import os

/// Serializes all SQLite access for tracking rules through an actor.
/// Use in-memory SQLite (`:memory:`) for tests.
actor RuleStore {

    private static let logger = Logger(category: "RuleStore")
    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private let database: SQLiteDatabase

    init(database: SQLiteDatabase) throws {
        self.database = database
        try Self.runMigrations(database: database)
    }

    private static func runMigrations(database: SQLiteDatabase) throws {
        if database.userVersion < 1 {
            try database.createTable(sql: createTableSQL)
            database.userVersion = 1
        }
        if database.userVersion < 2 {
            do { try database.execute("ALTER TABLE tracking_rules ADD COLUMN rule_type TEXT NOT NULL DEFAULT 'app'") } catch { /* already exists */ }
            do { try database.execute("ALTER TABLE tracking_rules ADD COLUMN event_title_pattern TEXT") } catch { /* already exists */ }
            database.userVersion = 2
        }
    }

    private static let createTableSQL = """
        CREATE TABLE IF NOT EXISTS tracking_rules (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            app_bundle_id TEXT,
            app_name_pattern TEXT,
            window_title_pattern TEXT,
            mode TEXT NOT NULL DEFAULT 'suggest',
            project_id INTEGER NOT NULL,
            project_name TEXT NOT NULL,
            task_id INTEGER NOT NULL,
            task_name TEXT NOT NULL,
            description TEXT NOT NULL DEFAULT '',
            enabled INTEGER NOT NULL DEFAULT 1,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            rule_type TEXT NOT NULL DEFAULT 'app',
            event_title_pattern TEXT
        )
        """

    // MARK: - CRUD

    func insert(_ rule: TrackingRule) throws -> Int64 {
        let now = Self.isoNow()
        try database.execute(Self.insertSQL, params: [
            rule.name,
            rule.appBundleId,
            rule.appNamePattern,
            rule.windowTitlePattern,
            rule.mode.rawValue,
            rule.projectId,
            rule.projectName,
            rule.taskId,
            rule.taskName,
            rule.description,
            rule.enabled,
            rule.createdAt.isEmpty ? now : rule.createdAt,
            rule.updatedAt.isEmpty ? now : rule.updatedAt,
            rule.ruleType.rawValue,
            rule.eventTitlePattern,
        ])
        return database.lastInsertRowId
    }

    func update(_ rule: TrackingRule) throws {
        guard let id = rule.id else { return }
        let now = Self.isoNow()
        try database.execute(Self.updateSQL, params: [
            rule.name,
            rule.appBundleId,
            rule.appNamePattern,
            rule.windowTitlePattern,
            rule.mode.rawValue,
            rule.projectId,
            rule.projectName,
            rule.taskId,
            rule.taskName,
            rule.description,
            rule.enabled,
            rule.ruleType.rawValue,
            rule.eventTitlePattern,
            now,
            id,
        ])
    }

    func delete(id: Int64) throws {
        try database.execute("DELETE FROM tracking_rules WHERE id = ?", params: [id])
    }

    func allRules() throws -> [TrackingRule] {
        let rows = try database.query("SELECT * FROM tracking_rules ORDER BY name")
        return rows.map(Self.ruleFromRow)
    }

    func enabledRules() throws -> [TrackingRule] {
        let rows = try database.query("SELECT * FROM tracking_rules WHERE enabled = 1 ORDER BY name")
        return rows.map(Self.ruleFromRow)
    }

    // MARK: - SQL Constants

    private static let insertSQL = """
        INSERT INTO tracking_rules (
            name, app_bundle_id, app_name_pattern, window_title_pattern,
            mode, project_id, project_name, task_id, task_name,
            description, enabled, created_at, updated_at,
            rule_type, event_title_pattern
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """

    private static let updateSQL = """
        UPDATE tracking_rules SET
            name = ?, app_bundle_id = ?, app_name_pattern = ?,
            window_title_pattern = ?, mode = ?, project_id = ?,
            project_name = ?, task_id = ?, task_name = ?,
            description = ?, enabled = ?, rule_type = ?,
            event_title_pattern = ?, updated_at = ?
        WHERE id = ?
        """

    // MARK: - Row Mapping

    private static func ruleFromRow(_ row: [String: Any]) -> TrackingRule {
        TrackingRule(
            id: row["id"] as? Int64,
            name: row["name"] as? String ?? "",
            appBundleId: nullableString(row, "app_bundle_id"),
            appNamePattern: nullableString(row, "app_name_pattern"),
            windowTitlePattern: nullableString(row, "window_title_pattern"),
            eventTitlePattern: nullableString(row, "event_title_pattern"),
            mode: RuleMode(rawValue: row["mode"] as? String ?? "suggest") ?? .suggest,
            ruleType: (row["rule_type"] as? String).flatMap(RuleType.init) ?? .app,
            projectId: intFromRow(row, "project_id"),
            projectName: row["project_name"] as? String ?? "",
            taskId: intFromRow(row, "task_id"),
            taskName: row["task_name"] as? String ?? "",
            description: row["description"] as? String ?? "",
            enabled: boolFromRow(row, "enabled"),
            createdAt: row["created_at"] as? String ?? "",
            updatedAt: row["updated_at"] as? String ?? ""
        )
    }

    private static func nullableString(_ row: [String: Any], _ key: String) -> String? {
        let val = row[key]
        if val is NSNull { return nil }
        return val as? String
    }

    private static func intFromRow(_ row: [String: Any], _ key: String) -> Int {
        if let v = row[key] as? Int64 { return Int(v) }
        if let v = row[key] as? Int { return v }
        return 0
    }

    private static func boolFromRow(_ row: [String: Any], _ key: String) -> Bool {
        if let v = row[key] as? Int64 { return v != 0 }
        if let v = row[key] as? Int { return v != 0 }
        return false
    }

    private static func isoNow() -> String {
        isoFormatter.string(from: Date.now)
    }
}
