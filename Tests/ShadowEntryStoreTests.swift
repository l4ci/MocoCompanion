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
        #expect(results[0].syncStatus == .pendingCreate)
    }

    @Test("mark synced changes status")
    func markSyncedChangesStatus() async throws {
        let store = try makeStore()
        let entry = TestFactories.makeShadowEntry(id: 1, date: "2025-03-15", syncStatus: .dirty)
        try await store.insert(entry)

        try await store.markSynced(id: 1, serverUpdatedAt: "2025-03-15T12:00:00Z")

        let fetched = try await store.entry(id: 1)
        #expect(fetched?.syncStatus == .synced)
        #expect(fetched?.serverUpdatedAt == "2025-03-15T12:00:00Z")
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
        entry.syncStatus = .synced
        try await store.updateFromServer(entry)

        let fetched = try await store.entry(id: 1)
        #expect(fetched?.description == "updated from server")
        #expect(fetched?.startTime == "09:00") // preserved
    }

    @Test("PRAGMA user_version is 1 after migration")
    func userVersionAfterMigration() async throws {
        let store = try makeStore()
        let version = await store.databaseUserVersion
        #expect(version == 1)
    }

    @Test("markConflict sets conflict flag")
    func markConflict() async throws {
        let store = try makeStore()
        let entry = TestFactories.makeShadowEntry(id: 1, date: "2025-03-15")
        try await store.insert(entry)

        try await store.markConflict(id: 1)

        let fetched = try await store.entry(id: 1)
        #expect(fetched?.conflictFlag == true)
    }
}
