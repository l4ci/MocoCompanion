import Foundation
import Testing
@testable import MocoCompanion

@Suite("ShadowEntryStore")
struct ShadowEntryStoreTests {

    private func makeStore() throws -> ShadowEntryStore {
        let db = try SQLiteDatabase(path: ":memory:")
        return try ShadowEntryStore(database: db)
    }

    // MARK: - CRUD

    @Test("insert and retrieve by date")
    func insertAndRetrieveByDate() async throws {
        let store = try makeStore()
        let entry = TestFactories.makeShadowEntry(id: 1, date: "2025-03-15")
        try await store.insert(entry)

        let results = try await store.entries(forDate: "2025-03-15")
        #expect(results.count == 1)
        #expect(results[0].id == 1)
        #expect(results[0].date == "2025-03-15")
        #expect(results[0].projectName == "Test Project")
        #expect(results[0].hours == 1.0)
        #expect(results[0].seconds == 3600)
    }

    @Test("update description")
    func updateDescription() async throws {
        let store = try makeStore()
        var entry = TestFactories.makeShadowEntry(id: 1, date: "2025-03-15")
        try await store.insert(entry)

        entry.description = "Updated description"
        try await store.update(entry)

        let fetched = try await store.entry(id: 1)
        #expect(fetched?.description == "Updated description")
    }

    @Test("delete entry by id")
    func deleteEntry() async throws {
        let store = try makeStore()
        let entry = TestFactories.makeShadowEntry(id: 1, date: "2025-03-15")
        try await store.insert(entry)

        try await store.delete(id: 1)
        let fetched = try await store.entry(id: 1)
        #expect(fetched == nil)
    }

    @Test("entry not found returns nil")
    func entryNotFound() async throws {
        let store = try makeStore()
        let fetched = try await store.entry(id: 999)
        #expect(fetched == nil)
    }

    // MARK: - Sync Status Filtering

    @Test("dirty entries query returns non-synced entries")
    func dirtyEntriesQuery() async throws {
        let store = try makeStore()
        let synced = TestFactories.makeShadowEntry(id: 1, date: "2025-03-15", syncStatus: .synced)
        let dirty = TestFactories.makeShadowEntry(id: 2, date: "2025-03-15", syncStatus: .pendingCreate)
        try await store.insert(synced)
        try await store.insert(dirty)

        let results = try await store.dirtyEntries()
        #expect(results.count == 1)
        #expect(results[0].id == 2)
        #expect(results[0].sync.status == .pendingCreate)
    }

    @Test("mark synced changes status")
    func markSyncedChangesStatus() async throws {
        let store = try makeStore()
        let entry = TestFactories.makeShadowEntry(id: 1, date: "2025-03-15", syncStatus: .dirty)
        try await store.insert(entry)

        try await store.markSynced(id: 1, serverUpdatedAt: "2025-03-15T12:00:00Z")

        let fetched = try await store.entry(id: 1)
        #expect(fetched?.sync.status == .synced)
        #expect(fetched?.sync.serverUpdatedAt == "2025-03-15T12:00:00Z")
    }

    // MARK: - Date Isolation

    @Test("entries isolated by date")
    func entriesIsolatedByDate() async throws {
        let store = try makeStore()
        let entry1 = TestFactories.makeShadowEntry(id: 1, date: "2025-03-15")
        let entry2 = TestFactories.makeShadowEntry(id: 2, date: "2025-03-16")
        try await store.insert(entry1)
        try await store.insert(entry2)

        let mar15 = try await store.entries(forDate: "2025-03-15")
        let mar16 = try await store.entries(forDate: "2025-03-16")

        #expect(mar15.count == 1)
        #expect(mar15[0].id == 1)
        #expect(mar16.count == 1)
        #expect(mar16[0].id == 2)
    }

    // MARK: - Remove Server Deleted

    @Test("removeServerDeleted keeps specified IDs and removes others")
    func removeServerDeleted() async throws {
        let store = try makeStore()
        let e1 = TestFactories.makeShadowEntry(id: 1, date: "2025-03-15")
        let e2 = TestFactories.makeShadowEntry(id: 2, date: "2025-03-15")
        let e3 = TestFactories.makeShadowEntry(id: 3, date: "2025-03-15")
        try await store.insert(e1)
        try await store.insert(e2)
        try await store.insert(e3)

        try await store.removeServerDeleted(keepingIds: [1, 2], forDate: "2025-03-15")

        let remaining = try await store.entries(forDate: "2025-03-15")
        #expect(remaining.count == 2)
        let ids = Set(remaining.compactMap(\.id))
        #expect(ids == [1, 2])
    }

    // MARK: - Negative / Edge Cases

    @Test("dirty entries on clean DB returns empty")
    func dirtyEntriesEmptyDB() async throws {
        let store = try makeStore()
        let results = try await store.dirtyEntries()
        #expect(results.isEmpty)
    }

    @Test("delete non-existent ID is no-op")
    func deleteNonExistent() async throws {
        let store = try makeStore()
        try await store.delete(id: 999)
        // No error thrown — operation is a no-op
    }

    @Test("removeServerDeleted with empty keepingIds removes all synced for date")
    func removeServerDeletedEmptyKeeping() async throws {
        let store = try makeStore()
        let e1 = TestFactories.makeShadowEntry(id: 1, date: "2025-03-15", syncStatus: .synced)
        let e2 = TestFactories.makeShadowEntry(id: 2, date: "2025-03-15", syncStatus: .synced)
        let dirty = TestFactories.makeShadowEntry(id: 3, date: "2025-03-15", syncStatus: .pendingCreate)
        try await store.insert(e1)
        try await store.insert(e2)
        try await store.insert(dirty)

        try await store.removeServerDeleted(keepingIds: [], forDate: "2025-03-15")

        let remaining = try await store.entries(forDate: "2025-03-15")
        #expect(remaining.count == 1)
        #expect(remaining[0].id == 3)
    }

    // MARK: - start_time Migration & Round-Trip

    @Test("fresh database includes start_time column")
    func freshDatabaseHasStartTimeColumn() async throws {
        let store = try makeStore()
        let entry = TestFactories.makeShadowEntry(id: 1, date: "2025-03-15", startTime: "09:30")
        try await store.insert(entry)

        let fetched = try await store.entry(id: 1)
        #expect(fetched?.startTime == "09:30")
    }

    @Test("startTime round-trips through insert and query")
    func startTimeRoundTrip() async throws {
        let store = try makeStore()
        let entry = TestFactories.makeShadowEntry(id: 1, date: "2025-03-15", startTime: "14:00")
        try await store.insert(entry)

        let fetched = try await store.entry(id: 1)
        #expect(fetched?.startTime == "14:00")
    }

    @Test("nil startTime persists as nil")
    func nilStartTimePersists() async throws {
        let store = try makeStore()
        let entry = TestFactories.makeShadowEntry(id: 1, date: "2025-03-15")
        try await store.insert(entry)

        let fetched = try await store.entry(id: 1)
        #expect(fetched?.startTime == nil)
    }

    @Test("updateFromServer does not overwrite local start_time")
    func updateFromServerPreservesStartTime() async throws {
        let store = try makeStore()
        var entry = TestFactories.makeShadowEntry(id: 1, date: "2025-03-15", startTime: "09:00")
        try await store.insert(entry)

        // Simulate server update — the ShadowEntry from server has no startTime
        entry.description = "updated from server"
        entry.startTime = nil
        entry.sync.status = .synced
        try await store.updateFromServer(entry)

        let fetched = try await store.entry(id: 1)
        #expect(fetched?.description == "updated from server")
        #expect(fetched?.startTime == "09:00") // preserved
    }

    @Test("PRAGMA user_version matches latest migration")
    func userVersionAfterMigration() async throws {
        let store = try makeStore()
        let version = await store.databaseUserVersion
        #expect(version == ShadowEntryStore.schemaVersion)
    }

    @Test("markConflict sets conflict flag")
    func markConflict() async throws {
        let store = try makeStore()
        let entry = TestFactories.makeShadowEntry(id: 1, date: "2025-03-15")
        try await store.insert(entry)

        try await store.markConflict(id: 1)

        let fetched = try await store.entry(id: 1)
        #expect(fetched?.sync.conflictFlag == true)
    }

    // MARK: - Local-Only Column Invariant

    @Test("updateFromServerSQL does not reference local-only columns")
    func updateFromServerSQL_doesNotReferenceLocalOnlyColumns() {
        for column in ShadowEntryStore.localOnlyColumns {
            #expect(
                !ShadowEntryStore.updateFromServerSQL.contains(column),
                "updateFromServerSQL must not reference local-only column '\(column)'"
            )
        }
    }
}

extension ShadowEntryStoreTests {
    @Test("Draft server identity remains nil and cannot collide with a remote row")
    func draftIdentity() async throws {
        let store = try makeStore()
        try await store.insert(TestFactories.makeShadowEntry(id: 100))
        var draft = TestFactories.makeShadowEntry(localId: "draft", syncStatus: .pendingCreate)
        draft.id = nil
        try await store.insert(draft)
        try await store.insert(TestFactories.makeShadowEntry(id: 101))
        #expect(try await store.entry(localId: "draft")?.id == nil)
        #expect(try await store.entry(id: 101)?.localId == nil)
    }

    @Test("An acknowledgement preserves a newer edit even with the same timestamp")
    func acknowledgeNewerRevision() async throws {
        let store = try makeStore()
        try await store.insert(TestFactories.makeShadowEntry(id: 1, description: "A", syncStatus: .dirty))
        let sent = try #require(await store.entry(id: 1))
        var newer = sent
        newer.description = "B"
        try await store.update(newer)
        #expect(try await store.acknowledgeUpdate(sent: sent, response: TestFactories.makeActivity(id: 1, description: "A")))
        let current = try #require(await store.entry(id: 1))
        #expect(current.description == "B")
        #expect(current.sync.status == .dirty)
        #expect(current.sync.revision > sent.sync.revision)
    }

    @Test("An acknowledgement cannot erase an undoable deletion")
    func acknowledgePreservesDelete() async throws {
        let store = try makeStore()
        try await store.insert(TestFactories.makeShadowEntry(id: 1, syncStatus: .dirty))
        let sent = try #require(await store.entry(id: 1))
        _ = try await store.beginUndoableDelete(id: 1)
        _ = try await store.acknowledgeUpdate(sent: sent, response: TestFactories.makeActivity(id: 1))
        #expect(try await store.entry(id: 1)?.sync.status == .pendingDelete)
        #expect(try await store.dirtyEntries().isEmpty)
        await store.commitUndoableDelete(id: 1)
        #expect(try await store.dirtyEntries().count == 1)
    }

    @Test("Promotion preserves edits made during POST and merges an already-pulled remote row")
    func promoteEditedDraft() async throws {
        let store = try makeStore()
        var draft = TestFactories.makeShadowEntry(localId: "draft", description: "A", startTime: "09:00", syncStatus: .pendingCreate)
        draft.id = nil
        draft.origin.appBundleId = "com.test.app"
        try await store.insert(draft)
        let sent = try #require(await store.entry(localId: "draft"))
        draft.description = "B"
        try await store.updateByLocalId(draft)
        try await store.insert(TestFactories.makeShadowEntry(id: 100))
        #expect(try await store.promoteDraft(sent: sent, response: TestFactories.makeActivity(id: 100, description: "A")))
        let promoted = try #require(await store.entry(id: 100))
        #expect(promoted.description == "B")
        #expect(promoted.sync.status == .dirty)
        #expect(promoted.startTime == "09:00")
        #expect(promoted.origin.appBundleId == "com.test.app")
        #expect(promoted.uiIdentity == sent.uiIdentity)
    }

    @Test("Promotion keeps the row's UI identity so selection survives")
    func promotionKeepsUIIdentity() async throws {
        let store = try makeStore()
        var draft = TestFactories.makeShadowEntry(localId: "stable", description: "A", syncStatus: .pendingCreate)
        draft.id = nil
        try await store.insert(draft)
        let sent = try #require(await store.entry(localId: "stable"))
        let before = sent.uiIdentity
        #expect(try await store.promoteDraft(sent: sent, response: TestFactories.makeActivity(id: 100, description: "A")) == false)
        let promoted = try #require(await store.entry(id: 100))
        #expect(promoted.uiIdentity == before)
        // A later server refresh must not drop it either.
        try await store.mergeFetchedActivity(TestFactories.makeActivity(id: 100, description: "A"))
        #expect(try await store.entry(id: 100)?.uiIdentity == before)
    }

    @Test("Failed promotion rolls back both draft deletion and existing remote deletion")
    func promotionRollback() async throws {
        let db = try SQLiteDatabase(path: ":memory:")
        let store = try ShadowEntryStore(database: db)
        var draft = TestFactories.makeShadowEntry(localId: "draft", startTime: "09:00", syncStatus: .pendingCreate)
        draft.id = nil
        try await store.insert(draft)
        try await store.insert(TestFactories.makeShadowEntry(id: 100, description: "existing"))
        try await store._testExecute("CREATE TRIGGER reject_promotion BEFORE INSERT ON shadow_entries WHEN NEW.id = 100 BEGIN SELECT RAISE(ABORT, 'forced failure'); END")
        do {
            _ = try await store.promoteDraft(sent: draft, response: TestFactories.makeActivity(id: 100))
            Issue.record("Expected failed promotion")
        } catch { }
        #expect(try await store.entry(localId: "draft")?.startTime == "09:00")
        #expect(try await store.entry(id: 100)?.description == "existing")
    }

    @Test("Version 3 migration clears synthetic draft IDs and preserves metadata")
    func migrateLegacyDrafts() async throws {
        let db = try SQLiteDatabase(path: ":memory:")
        let legacySchema = ShadowEntryStore.createTableSQL
            .replacingOccurrences(of: "row_id INTEGER PRIMARY KEY,", with: "")
            .replacingOccurrences(of: "id INTEGER UNIQUE,", with: "id INTEGER PRIMARY KEY,")
            .replacingOccurrences(of: "local_revision INTEGER NOT NULL DEFAULT 0,", with: "")
        try db.execute(legacySchema)
        try db.execute("PRAGMA user_version = 3")
        let columns = try db.query("PRAGMA table_info(shadow_entries)")
        let required = columns.filter { ($0["notnull"] as? Int64) == 1 && $0["dflt_value"] is NSNull }
        let names = required.compactMap { $0["name"] as? String }
        let values: [Any?] = required.map { ($0["type"] as? String) == "TEXT" ? "" as Any : 0 as Any }
        let placeholders = Array(repeating: "?", count: names.count).joined(separator: ",")
        try db.execute("INSERT INTO shadow_entries (id, \(names.joined(separator: ","))) VALUES (100, \(placeholders))", params: values)
        try db.execute("INSERT INTO shadow_entries (id, \(names.joined(separator: ","))) VALUES (101, \(placeholders))", params: values)
        try db.execute("UPDATE shadow_entries SET local_id = 'legacy', sync_status = 'pending_create', start_time = '10:30' WHERE id = 101")
        // A synced row that merely carries a local_id keeps its server id.
        try db.execute("INSERT INTO shadow_entries (id, \(names.joined(separator: ","))) VALUES (102, \(placeholders))", params: values)
        try db.execute("UPDATE shadow_entries SET local_id = 'synced-legacy', sync_status = 'synced' WHERE id = 102")
        let migrated = try ShadowEntryStore(database: db)
        #expect(try await migrated.entry(id: 102)?.localId == "synced-legacy")
        #expect(try await migrated.entry(id: 102)?.sync.status == .synced)
        #expect(try await migrated.entry(localId: "legacy")?.id == nil)
        #expect(try await migrated.entry(localId: "legacy")?.startTime == "10:30")
        #expect(try await migrated.entry(id: 100) != nil)
        try await migrated.insert(TestFactories.makeShadowEntry(id: 101))
        #expect(await migrated.databaseUserVersion == ShadowEntryStore.schemaVersion)
    }
}

extension ShadowEntryStoreTests {
    @Test("Promotion retains edits or undoable tombstones on an already-present remote row")
    func promotePreservesRemoteIntent() async throws {
        for status in [SyncStatus.dirty, .pendingDelete] {
            let store = try makeStore()
            var draft = TestFactories.makeShadowEntry(localId: "draft", startTime: "09:00", syncStatus: .pendingCreate)
            draft.id = nil
            try await store.insert(draft)
            try await store.insert(TestFactories.makeShadowEntry(id: 100, description: "newer remote edit", syncStatus: status))
            if status == .pendingDelete { _ = try await store.beginUndoableDelete(id: 100) }
            _ = try await store.promoteDraft(sent: draft, response: TestFactories.makeActivity(id: 100, description: "POST"))
            let remote = try #require(await store.entry(id: 100))
            #expect(remote.description == "newer remote edit")
            #expect(remote.sync.status == status)
            #expect(remote.startTime == "09:00")
            if status == .pendingDelete { #expect(try await store.dirtyEntries().isEmpty) }
        }
    }

    @Test("Deleting a draft during POST queues deletion of the created server entry")
    func promotionAfterLocalDelete() async throws {
        let store = try makeStore()
        var draft = TestFactories.makeShadowEntry(localId: "deleted", syncStatus: .pendingCreate)
        draft.id = nil
        try await store.insert(draft)
        try await store.deleteByLocalId("deleted")
        #expect(try await store.promoteDraft(sent: draft, response: TestFactories.makeActivity(id: 100)))
        #expect(try await store.entry(id: 100)?.sync.status == .pendingDelete)
    }
}

extension ShadowEntryStoreTests {
    @Test("Undoable deletion reserves its booking until commit")
    func undoableDeleteReservesBooking() async throws {
        let store = try makeStore()
        let original = TestFactories.makeShadowEntry(id: 1, startTime: "09:00")
        try await store.insert(original)
        _ = try await store.beginUndoableDelete(id: 1)
        var duplicate = original
        duplicate.id = nil
        duplicate.localId = "rule-created"
        duplicate.sync.status = .pendingCreate
        #expect(try await store.insertIfBookingAbsent(duplicate) == false)
        try await store.restoreUndoableDelete(original)
        #expect(try await store.entries(forDate: original.date).count == 1)
        _ = try await store.beginUndoableDelete(id: 1)
        await store.commitUndoableDelete(id: 1)
        #expect(try await store.insertIfBookingAbsent(duplicate))
    }
}
