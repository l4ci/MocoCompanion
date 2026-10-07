import Foundation

/// Serializes all SQLite access for shadow entries through an actor.
/// Use in-memory SQLite (`:memory:`) for tests.
actor ShadowEntryStore {

    private let database: SQLiteDatabase

    // Undoable tombstones are hidden from readers but not eligible for upload.
    // On restart the grace period has ended, so persisted tombstones are committed.
    private var undoableDeletes: Set<Int> = []
    static let schemaVersion = 4

    init(database: SQLiteDatabase) throws {
        self.database = database
        try Self.runMigrations(database: database)
    }

    private static func runMigrations(database: SQLiteDatabase) throws {
        try database.transaction {
            try database.createTable(sql: Self.createTableSQL)
            let columns = Set(try database.query("PRAGMA table_info(shadow_entries)").compactMap { $0["name"] as? String })
            // Inspect columns instead of swallowing arbitrary ALTER failures.
            for (name, type) in [("start_time", "TEXT"), ("source_app_bundle_id", "TEXT"),
                                 ("source_rule_id", "INTEGER"), ("source_calendar_event_id", "TEXT")] {
                if !columns.contains(name) {
                    try database.execute("ALTER TABLE shadow_entries ADD COLUMN \(name) \(type)")
                }
            }
            if !columns.contains("row_id") {
                try database.execute("ALTER TABLE shadow_entries RENAME TO shadow_entries_legacy")
                try database.createTable(sql: Self.createTableSQL)
                let oldColumns = try database.query("PRAGMA table_info(shadow_entries_legacy)").compactMap { $0["name"] as? String }
                let selections = oldColumns.map { column -> String in
                    // Keep both CASE predicates identical: a row losing its id
                    // must become pending_create, or it is an invisible ghost.
                    let isLegacyDraft = "(sync_status = 'pending_create' OR (local_id IS NOT NULL AND sync_status = 'dirty'))"
                    if column == "id" {
                        return "CASE WHEN \(isLegacyDraft) THEN NULL ELSE id END"
                    }
                    if column == "sync_status" {
                        return "CASE WHEN \(isLegacyDraft) THEN 'pending_create' ELSE sync_status END"
                    }
                    return column
                }
                // Legacy local drafts were never uploaded: a deleted draft needs no server tombstone.
                try database.execute("INSERT INTO shadow_entries (\(oldColumns.joined(separator: ","))) SELECT \(selections.joined(separator: ",")) FROM shadow_entries_legacy WHERE NOT (local_id IS NOT NULL AND sync_status = 'pending_delete')")
                try database.execute("DROP TABLE shadow_entries_legacy")
            }
            try database.execute("CREATE INDEX IF NOT EXISTS idx_shadow_entries_date ON shadow_entries(date)")
            try database.execute("CREATE INDEX IF NOT EXISTS idx_shadow_entries_sync ON shadow_entries(sync_status)")
            try database.execute("PRAGMA user_version = \(schemaVersion)")
        }
    }

    static let createTableSQL = """
        CREATE TABLE IF NOT EXISTS shadow_entries (
            row_id INTEGER PRIMARY KEY,
            id INTEGER UNIQUE,
            local_revision INTEGER NOT NULL DEFAULT 0,
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

    #if DEBUG
    /// Fault injection on the owning actor, without sharing its connection.
    func _testExecute(_ sql: String) throws { try database.execute(sql) }
    #endif

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

    /// Delete every shadow entry. Used by the full "Reset Everything" flow.
    func deleteAll() throws {
        try database.execute("DELETE FROM shadow_entries")
    }

    // MARK: - Queries

    func entries(forDate date: String) throws -> [ShadowEntry] {
        let rows = try database.query("SELECT * FROM shadow_entries WHERE date = ?", params: [date])
        return rows.map(entryFromRow)
    }

    func dirtyEntries() throws -> [ShadowEntry] {
        // Use IN with concrete values instead of `!= 'synced'` so SQLite's
        // planner can actually use idx_shadow_entries_sync. Inequality
        // against a single value does not narrow an equality index.
        let rows = try database.query(
            "SELECT * FROM shadow_entries WHERE sync_status IN (?, ?, ?)",
            params: [
                SyncStatus.dirty.rawValue,
                SyncStatus.pendingCreate.rawValue,
                SyncStatus.pendingDelete.rawValue,
            ]
        )
        return rows.map(entryFromRow).filter { entry in
            guard let id = entry.id else { return true }
            return !undoableDeletes.contains(id)
        }
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

    @discardableResult
    func insertIfBookingAbsent(_ entry: ShadowEntry) throws -> Bool {
        var inserted = false
        try database.transaction {
            let existing = try database.query("SELECT id, sync_status FROM shadow_entries WHERE date = ? AND project_id = ? AND task_id = ? AND start_time IS ?",
                                              params: [entry.date, entry.projectId, entry.taskId, entry.startTime])
            let occupied = existing.contains { row in
                if row["sync_status"] as? String != SyncStatus.pendingDelete.rawValue { return true }
                guard let id = intFromRow(row, "id") else { return false }
                return undoableDeletes.contains(id)
            }
            guard !occupied else { return }
            try insert(entry)
            inserted = true
        }
        return inserted
    }

    func beginUndoableDelete(id: Int) throws -> ShadowEntry? {
        guard let original = try entry(id: id) else { return nil }
        var tombstone = original
        tombstone.sync.status = .pendingDelete
        try update(tombstone)
        undoableDeletes.insert(id)
        return original
    }

    func commitUndoableDelete(id: Int) {
        undoableDeletes.remove(id)
    }

    func restoreUndoableDelete(_ original: ShadowEntry) throws {
        guard let id = original.id, undoableDeletes.contains(id),
              let current = try entry(id: id) else { return }
        var restored = original
        // An earlier upload may have completed during the grace period.
        restored.sync.serverUpdatedAt = current.sync.serverUpdatedAt
        try update(restored)
        undoableDeletes.remove(id)
    }

    /// Recheck queued work just before dispatch; a snapshot can predate undo.
    func isUploadEligible(_ sent: ShadowEntry) throws -> Bool {
        let current: ShadowEntry?
        if let id = sent.id {
            guard !undoableDeletes.contains(id) else { return false }
            current = try entry(id: id)
        } else if let localId = sent.localId {
            current = try entry(localId: localId)
        } else { return false }
        return current?.sync.revision == sent.sync.revision && current?.sync.status == sent.sync.status
    }

    /// Acknowledge only the version actually sent. Newer edits and deletion
    /// intent survive, but their server baseline advances to this response.
    @discardableResult
    func acknowledgeUpdate(sent: ShadowEntry, response: MocoActivity) throws -> Bool {
        guard let id = sent.id, let current = try entry(id: id) else { return false }
        if current.sync.revision == sent.sync.revision && current.sync.status == sent.sync.status {
            var merged = ShadowEntry.merged(api: response, preserving: current)
            merged.localId = current.localId
            try update(merged)
            return false
        }
        try database.execute("UPDATE shadow_entries SET server_updated_at = ? WHERE id = ?", params: [response.updatedAt, id])
        return current.sync.status == .dirty || (current.sync.status == .pendingDelete && !undoableDeletes.contains(id))
    }

    /// Replace a draft and an optional already-pulled server row atomically.
    /// A draft removed while POST was in flight becomes a remote tombstone.
    @discardableResult
    func promoteDraft(sent: ShadowEntry, response: MocoActivity) throws -> Bool {
        var needsPush = false
        try database.transaction {
            let current = try sent.localId.flatMap { try entry(localId: $0) }
            var promoted = ShadowEntry.merged(api: response, preserving: current ?? sent)
            if let current {
                if current.sync.revision != sent.sync.revision || current.sync.status != sent.sync.status {
                    promoted = current
                    promoted.id = response.id
                    promoted.sync.status = current.sync.status == .pendingDelete ? .pendingDelete : .dirty
                    promoted.sync.serverUpdatedAt = response.updatedAt
                    needsPush = true
                }
            } else {
                promoted.sync.status = .pendingDelete
                needsPush = true
            }
            if let remote = try entry(id: response.id), remote.sync.status != .synced {
                // A pull may have inserted the POST result, followed by a user
                // edit/delete before promotion. Never discard that intent.
                var newer = remote
                if newer.startTime == nil { newer.startTime = promoted.startTime }
                if newer.origin.appBundleId == nil { newer.origin.appBundleId = promoted.origin.appBundleId }
                if newer.origin.ruleId == nil { newer.origin.ruleId = promoted.origin.ruleId }
                if newer.origin.calendarEventId == nil { newer.origin.calendarEventId = promoted.origin.calendarEventId }
                if newer.localId == nil { newer.localId = sent.localId }
                newer.sync.serverUpdatedAt = response.updatedAt
                promoted = newer
                needsPush = newer.sync.status != .pendingDelete || !undoableDeletes.contains(response.id)
            }
            if let localId = sent.localId { try deleteByLocalId(localId) }
            try delete(id: response.id)
            try insert(promoted)
        }
        return needsPush
    }

    /// Timer snapshots never overwrite local edits or tombstones.
    @discardableResult
    func mergeFetchedActivity(_ activity: MocoActivity) throws -> ShadowEntry {
        if let current = try entry(id: activity.id) {
            guard current.sync.status == .synced else { return current }
            let merged = ShadowEntry.merged(api: activity, preserving: current)
            try update(merged)
        } else {
            try insert(ShadowEntry.from(activity))
        }
        return try entry(id: activity.id)!
    }

    func reconcileTimerSnapshot(_ activities: [MocoActivity], forDate date: String) throws -> [ShadowEntry] {
        try database.transaction {
            for activity in activities { try mergeFetchedActivity(activity) }
            try removeServerDeleted(keepingIds: Set(activities.map(\.id)), forDate: date)
        }
        return try entries(forDate: date).filter { $0.sync.status != .pendingDelete }
    }

    func rejectDelete(sent: ShadowEntry) throws {
        guard let id = sent.id, let current = try entry(id: id),
              current.sync.revision == sent.sync.revision,
              current.sync.status == .pendingDelete else { return }
        try markSynced(id: id, serverUpdatedAt: current.sync.serverUpdatedAt)
    }

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

    @discardableResult
    func updateFromServer(_ entry: ShadowEntry, expectedRevision: Int? = nil) throws -> Bool {
        guard let id = entry.id else { return false }
        if let expectedRevision, try self.entry(id: id)?.sync.revision != expectedRevision { return false }
        try database.execute(Self.updateFromServerSQL, params: updateFromServerParams(for: entry) + [id])
        return database.changes > 0
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

    // MARK: - Local-Only Column Registry

    /// Columns that are LOCAL-ONLY: never sent to Moco, never overwritten
    /// on pull. Maintained as a single source of truth so insert/update
    /// SQL can include them while `updateFromServerSQL` deliberately
    /// excludes them via `allColumnsExcludingLocalOnly`.
    static let localOnlyColumns: [String] = [
        "start_time",
        "source_app_bundle_id",
        "source_rule_id",
        "source_calendar_event_id",
    ]

    // MARK: - SQL Constants

    private static let insertSQL = """
        INSERT INTO shadow_entries (
            id, local_id, date, hours, seconds, worked_seconds, description,
            billed, billable, tag, project_id, project_name, project_billable,
            task_id, task_name, task_billable, customer_id, customer_name,
            user_id, user_firstname, user_lastname, hourly_rate, timer_started_at,
            start_time, locked, created_at, updated_at, sync_status, local_updated_at,
            server_updated_at, conflict_flag, source_app_bundle_id, source_rule_id,
            source_calendar_event_id, local_revision
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """

    private static let updateSQL = """
        UPDATE shadow_entries SET
            local_revision = local_revision + 1,
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
            local_revision = local_revision + 1,
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

    static let updateFromServerSQL = """
        UPDATE shadow_entries SET
            local_revision = local_revision + 1,
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
            e.startTime, e.locked, e.createdAt, e.updatedAt, e.sync.status.rawValue,
            e.sync.localUpdatedAt, e.sync.serverUpdatedAt, e.sync.conflictFlag,
            e.origin.appBundleId, e.origin.ruleId.map { Int($0) } as Any?,
            e.origin.calendarEventId, e.sync.revision,
        ]
    }

    private func updateParams(for e: ShadowEntry) -> [Any?] {
        [
            e.localId, e.date, e.hours, e.seconds, e.workedSeconds,
            e.description, e.billed, e.billable, e.tag, e.projectId,
            e.projectName, e.projectBillable, e.taskId, e.taskName,
            e.taskBillable, e.customerId, e.customerName, e.userId,
            e.userFirstname, e.userLastname, e.hourlyRate, e.timerStartedAt,
            e.startTime, e.locked, e.createdAt, e.updatedAt, e.sync.status.rawValue,
            e.sync.localUpdatedAt, e.sync.serverUpdatedAt, e.sync.conflictFlag,
            e.origin.appBundleId, e.origin.ruleId.map { Int($0) } as Any?,
            e.origin.calendarEventId,
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
            e.sync.localUpdatedAt, e.sync.serverUpdatedAt, e.sync.conflictFlag,
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
            sync: ShadowEntry.SyncMeta(
                status: SyncStatus(rawValue: row["sync_status"] as? String ?? "synced") ?? .synced,
                localUpdatedAt: row["local_updated_at"] as? String ?? "",
                serverUpdatedAt: row["server_updated_at"] as? String ?? "",
                conflictFlag: boolFromRow(row, "conflict_flag"),
                revision: intFromRow(row, "local_revision") ?? 0
            ),
            origin: ShadowEntry.Origin(
                appBundleId: row["source_app_bundle_id"] as? String,
                ruleId: (row["source_rule_id"] as? Int64) ?? (row["source_rule_id"] as? Int).map { Int64($0) },
                calendarEventId: row["source_calendar_event_id"] as? String
            )
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
