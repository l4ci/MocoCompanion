import Foundation

/// Serializes all SQLite access for shadow entries through an actor.
/// Use in-memory SQLite (`:memory:`) for tests.
actor ShadowEntryStore {

    private let database: SQLiteDatabase

    init(database: SQLiteDatabase) throws {
        self.database = database
        try database.createTable(sql: Self.createTableSQL)
        try database.execute("CREATE INDEX IF NOT EXISTS idx_shadow_entries_date ON shadow_entries(date)")
        try database.execute("CREATE INDEX IF NOT EXISTS idx_shadow_entries_sync ON shadow_entries(sync_status)")
        try Self.runMigrations(database: database)
    }

    private static func runMigrations(database: SQLiteDatabase) throws {
        if database.userVersion < 1 {
            // On fresh databases the column already exists from createTableSQL.
            // ALTER TABLE ADD COLUMN errors on duplicates, so we catch that case.
            do {
                try database.execute("ALTER TABLE shadow_entries ADD COLUMN start_time TEXT")
            } catch {
                // Column already exists — expected on fresh databases
            }
            database.userVersion = 1
        }
        if database.userVersion < 2 {
            // Origin tracking columns (local-only metadata). See
            // ShadowEntry.sourceAppBundleId / sourceRuleId for context.
            do {
                try database.execute("ALTER TABLE shadow_entries ADD COLUMN source_app_bundle_id TEXT")
            } catch { /* already exists */ }
            do {
                try database.execute("ALTER TABLE shadow_entries ADD COLUMN source_rule_id INTEGER")
            } catch { /* already exists */ }
            database.userVersion = 2
        }
        if database.userVersion < 3 {
            // Calendar event origin tracking (local-only metadata). See
            // ShadowEntry.sourceCalendarEventId for context.
            do {
                try database.execute("ALTER TABLE shadow_entries ADD COLUMN source_calendar_event_id TEXT")
            } catch { /* already exists */ }
            database.userVersion = 3
        }
    }

    private static let createTableSQL = """
        CREATE TABLE IF NOT EXISTS shadow_entries (
            id INTEGER PRIMARY KEY,
            local_id TEXT UNIQUE,
            date TEXT NOT NULL,
            hours REAL NOT NULL,
            seconds INTEGER NOT NULL,
            worked_seconds INTEGER NOT NULL,
            description TEXT NOT NULL DEFAULT '',
            billed INTEGER NOT NULL DEFAULT 0,
            billable INTEGER NOT NULL DEFAULT 0,
            tag TEXT NOT NULL DEFAULT '',
            project_id INTEGER NOT NULL,
            project_name TEXT NOT NULL,
            project_billable INTEGER NOT NULL DEFAULT 0,
            task_id INTEGER NOT NULL,
            task_name TEXT NOT NULL,
            task_billable INTEGER NOT NULL DEFAULT 0,
            customer_id INTEGER NOT NULL,
            customer_name TEXT NOT NULL,
            user_id INTEGER NOT NULL,
            user_firstname TEXT NOT NULL,
            user_lastname TEXT NOT NULL,
            hourly_rate REAL NOT NULL DEFAULT 0,
            timer_started_at TEXT,
            start_time TEXT,
            locked INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            sync_status TEXT NOT NULL DEFAULT 'synced',
            local_updated_at TEXT NOT NULL,
            server_updated_at TEXT NOT NULL,
            conflict_flag INTEGER NOT NULL DEFAULT 0,
            source_app_bundle_id TEXT,
            source_rule_id INTEGER,
            source_calendar_event_id TEXT
        )
        """

    /// Expose the database's PRAGMA user_version for testing.
    var databaseUserVersion: Int { database.userVersion }

    // MARK: - CRUD

    func insert(_ entry: ShadowEntry) throws {
        try database.execute(Self.insertSQL, params: insertParams(for: entry))
    }

    func update(_ entry: ShadowEntry) throws {
        guard let id = entry.id else { return }
        try database.execute(Self.updateSQL, params: updateParams(for: entry) + [id])
    }

    /// Update a local-only entry (no server id) by its localId.
    func updateByLocalId(_ entry: ShadowEntry) throws {
        guard let localId = entry.localId else { return }
        try database.execute(Self.updateByLocalIdSQL, params: updateParams(for: entry) + [localId])
    }

    func delete(id: Int) throws {
        try database.execute("DELETE FROM shadow_entries WHERE id = ?", params: [id])
    }

    func deleteByLocalId(_ localId: String) throws {
        try database.execute("DELETE FROM shadow_entries WHERE local_id = ?", params: [localId])
    }

    // MARK: - Queries

    func entries(forDate date: String) throws -> [ShadowEntry] {
        let rows = try database.query("SELECT * FROM shadow_entries WHERE date = ?", params: [date])
        return rows.map(entryFromRow)
    }

    func dirtyEntries() throws -> [ShadowEntry] {
        let rows = try database.query("SELECT * FROM shadow_entries WHERE sync_status != ?", params: ["synced"])
        return rows.map(entryFromRow)
    }

    func entry(id: Int) throws -> ShadowEntry? {
        let rows = try database.query("SELECT * FROM shadow_entries WHERE id = ?", params: [id])
        return rows.first.map(entryFromRow)
    }

    func entry(localId: String) throws -> ShadowEntry? {
        let rows = try database.query("SELECT * FROM shadow_entries WHERE local_id = ?", params: [localId])
        return rows.first.map(entryFromRow)
    }

    // MARK: - Sync Operations

    func markSynced(id: Int, serverUpdatedAt: String) throws {
        try database.execute(
            "UPDATE shadow_entries SET sync_status = ?, server_updated_at = ? WHERE id = ?",
            params: ["synced", serverUpdatedAt, id]
        )
    }

    func markConflict(id: Int) throws {
        try database.execute(
            "UPDATE shadow_entries SET conflict_flag = 1 WHERE id = ?",
            params: [id]
        )
    }

    func updateFromServer(_ entry: ShadowEntry) throws {
        guard let id = entry.id else { return }
        try database.execute(Self.updateFromServerSQL, params: updateFromServerParams(for: entry) + [id])
    }

    func removeServerDeleted(keepingIds: Set<Int>, forDate date: String) throws {
        if keepingIds.isEmpty {
            try database.execute(
                "DELETE FROM shadow_entries WHERE date = ? AND sync_status = ?",
                params: [date, "synced"]
            )
        } else {
            let placeholders = keepingIds.map { _ in "?" }.joined(separator: ", ")
            let sql = "DELETE FROM shadow_entries WHERE date = ? AND id NOT IN (\(placeholders)) AND sync_status = ?"
            let params: [Any?] = [date] + keepingIds.sorted().map { $0 as Any? } + ["synced"]
            try database.execute(sql, params: params)
        }
    }

    // MARK: - SQL Constants

    private static let insertSQL = """
        INSERT INTO shadow_entries (
            id, local_id, date, hours, seconds, worked_seconds, description,
            billed, billable, tag, project_id, project_name, project_billable,
            task_id, task_name, task_billable, customer_id, customer_name,
            user_id, user_firstname, user_lastname, hourly_rate, timer_started_at,
            start_time, locked, created_at, updated_at, sync_status, local_updated_at,
            server_updated_at, conflict_flag, source_app_bundle_id, source_rule_id,
            source_calendar_event_id
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """

    private static let updateSQL = """
        UPDATE shadow_entries SET
            local_id = ?, date = ?, hours = ?, seconds = ?, worked_seconds = ?,
            description = ?, billed = ?, billable = ?, tag = ?, project_id = ?,
            project_name = ?, project_billable = ?, task_id = ?, task_name = ?,
            task_billable = ?, customer_id = ?, customer_name = ?, user_id = ?,
            user_firstname = ?, user_lastname = ?, hourly_rate = ?,
            timer_started_at = ?, start_time = ?, locked = ?, created_at = ?,
            updated_at = ?, sync_status = ?, local_updated_at = ?,
            server_updated_at = ?, conflict_flag = ?,
            source_app_bundle_id = ?, source_rule_id = ?,
            source_calendar_event_id = ?
        WHERE id = ?
        """

    private static let updateByLocalIdSQL = """
        UPDATE shadow_entries SET
            local_id = ?, date = ?, hours = ?, seconds = ?, worked_seconds = ?,
            description = ?, billed = ?, billable = ?, tag = ?, project_id = ?,
            project_name = ?, project_billable = ?, task_id = ?, task_name = ?,
            task_billable = ?, customer_id = ?, customer_name = ?, user_id = ?,
            user_firstname = ?, user_lastname = ?, hourly_rate = ?,
            timer_started_at = ?, start_time = ?, locked = ?, created_at = ?,
            updated_at = ?, sync_status = ?, local_updated_at = ?,
            server_updated_at = ?, conflict_flag = ?,
            source_app_bundle_id = ?, source_rule_id = ?,
            source_calendar_event_id = ?
        WHERE local_id = ?
        """

    private static let updateFromServerSQL = """
        UPDATE shadow_entries SET
            date = ?, hours = ?, seconds = ?, worked_seconds = ?,
            description = ?, billed = ?, billable = ?, tag = ?, project_id = ?,
            project_name = ?, project_billable = ?, task_id = ?, task_name = ?,
            task_billable = ?, customer_id = ?, customer_name = ?, user_id = ?,
            user_firstname = ?, user_lastname = ?, hourly_rate = ?,
            timer_started_at = ?, locked = ?, created_at = ?, updated_at = ?,
            sync_status = ?, local_updated_at = ?, server_updated_at = ?,
            conflict_flag = ?
        WHERE id = ?
        """

    // MARK: - Parameter Binding

    private func insertParams(for e: ShadowEntry) -> [Any?] {
        [
            e.id, e.localId, e.date, e.hours, e.seconds, e.workedSeconds,
            e.description, e.billed, e.billable, e.tag, e.projectId,
            e.projectName, e.projectBillable, e.taskId, e.taskName,
            e.taskBillable, e.customerId, e.customerName, e.userId,
            e.userFirstname, e.userLastname, e.hourlyRate, e.timerStartedAt,
            e.startTime, e.locked, e.createdAt, e.updatedAt, e.syncStatus.rawValue,
            e.localUpdatedAt, e.serverUpdatedAt, e.conflictFlag,
            e.sourceAppBundleId, e.sourceRuleId.map { Int($0) } as Any?,
            e.sourceCalendarEventId,
        ]
    }

    private func updateParams(for e: ShadowEntry) -> [Any?] {
        [
            e.localId, e.date, e.hours, e.seconds, e.workedSeconds,
            e.description, e.billed, e.billable, e.tag, e.projectId,
            e.projectName, e.projectBillable, e.taskId, e.taskName,
            e.taskBillable, e.customerId, e.customerName, e.userId,
            e.userFirstname, e.userLastname, e.hourlyRate, e.timerStartedAt,
            e.startTime, e.locked, e.createdAt, e.updatedAt, e.syncStatus.rawValue,
            e.localUpdatedAt, e.serverUpdatedAt, e.conflictFlag,
            e.sourceAppBundleId, e.sourceRuleId.map { Int($0) } as Any?,
            e.sourceCalendarEventId,
        ]
    }

    private func updateFromServerParams(for e: ShadowEntry) -> [Any?] {
        [
            e.date, e.hours, e.seconds, e.workedSeconds,
            e.description, e.billed, e.billable, e.tag, e.projectId,
            e.projectName, e.projectBillable, e.taskId, e.taskName,
            e.taskBillable, e.customerId, e.customerName, e.userId,
            e.userFirstname, e.userLastname, e.hourlyRate, e.timerStartedAt,
            e.locked, e.createdAt, e.updatedAt, "synced",
            e.localUpdatedAt, e.serverUpdatedAt, e.conflictFlag,
        ]
    }

    // MARK: - Row Mapping

    private func entryFromRow(_ row: [String: Any]) -> ShadowEntry {
        ShadowEntry(
            id: intFromRow(row, "id"),
            localId: row["local_id"] as? String,
            date: row["date"] as? String ?? "",
            hours: row["hours"] as? Double ?? 0,
            seconds: intFromRow(row, "seconds") ?? 0,
            workedSeconds: intFromRow(row, "worked_seconds") ?? 0,
            description: row["description"] as? String ?? "",
            billed: boolFromRow(row, "billed"),
            billable: boolFromRow(row, "billable"),
            tag: row["tag"] as? String ?? "",
            projectId: intFromRow(row, "project_id") ?? 0,
            projectName: row["project_name"] as? String ?? "",
            projectBillable: boolFromRow(row, "project_billable"),
            taskId: intFromRow(row, "task_id") ?? 0,
            taskName: row["task_name"] as? String ?? "",
            taskBillable: boolFromRow(row, "task_billable"),
            customerId: intFromRow(row, "customer_id") ?? 0,
            customerName: row["customer_name"] as? String ?? "",
            userId: intFromRow(row, "user_id") ?? 0,
            userFirstname: row["user_firstname"] as? String ?? "",
            userLastname: row["user_lastname"] as? String ?? "",
            hourlyRate: row["hourly_rate"] as? Double ?? 0,
            timerStartedAt: row["timer_started_at"] as? String,
            startTime: row["start_time"] as? String,
            locked: boolFromRow(row, "locked"),
            createdAt: row["created_at"] as? String ?? "",
            updatedAt: row["updated_at"] as? String ?? "",
            syncStatus: SyncStatus(rawValue: row["sync_status"] as? String ?? "synced") ?? .synced,
            localUpdatedAt: row["local_updated_at"] as? String ?? "",
            serverUpdatedAt: row["server_updated_at"] as? String ?? "",
            conflictFlag: boolFromRow(row, "conflict_flag"),
            sourceAppBundleId: row["source_app_bundle_id"] as? String,
            sourceRuleId: (row["source_rule_id"] as? Int64) ?? (row["source_rule_id"] as? Int).map { Int64($0) },
            sourceCalendarEventId: row["source_calendar_event_id"] as? String
        )
    }

    private func intFromRow(_ row: [String: Any], _ key: String) -> Int? {
        if let v = row[key] as? Int64 { return Int(v) }
        if let v = row[key] as? Int { return v }
        return nil
    }

    private func boolFromRow(_ row: [String: Any], _ key: String) -> Bool {
        if let v = row[key] as? Int64 { return v != 0 }
        if let v = row[key] as? Int { return v != 0 }
        return false
    }
}
