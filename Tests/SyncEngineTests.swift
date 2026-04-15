import Foundation
import Testing
@testable import MocoCompanion

// MARK: - Combined Mock

/// Mock that conforms to both ActivityAPI and TimerAPI for SyncEngine testing.
private struct MockSyncAPI: ActivityAPI, TimerAPI, @unchecked Sendable {
    var fetchActivitiesHandler: (String, String, Int?) async throws -> [MocoActivity] = { _, _, _ in [] }
    var createActivityHandler: (String, Int, Int, String, Int, String?) async throws -> MocoActivity = { _, _, _, _, _, _ in
        throw MocoError.serverError(statusCode: 500, message: "not stubbed")
    }
    var updateActivityHandler: (Int, String?, String?, Int?) async throws -> MocoActivity = { _, _, _, _ in
        throw MocoError.serverError(statusCode: 500, message: "not stubbed")
    }
    var deleteActivityHandler: (Int) async throws -> Void = { _ in }
    var startTimerHandler: (Int) async throws -> MocoActivity = { _ in
        throw MocoError.serverError(statusCode: 500, message: "not stubbed")
    }
    var stopTimerHandler: (Int) async throws -> MocoActivity = { _ in
        throw MocoError.serverError(statusCode: 500, message: "not stubbed")
    }

    func fetchActivities(from: String, to: String, userId: Int?) async throws -> [MocoActivity] {
        try await fetchActivitiesHandler(from, to, userId)
    }

    func createActivity(date: String, projectId: Int, taskId: Int, description: String, seconds: Int, tag: String?) async throws -> MocoActivity {
        try await createActivityHandler(date, projectId, taskId, description, seconds, tag)
    }

    func updateActivity(activityId: Int, description: String, tag: String?) async throws -> MocoActivity {
        try await updateActivityHandler(activityId, description, tag, nil)
    }

    func updateActivity(activityId: Int, description: String?, tag: String?, seconds: Int?) async throws -> MocoActivity {
        try await updateActivityHandler(activityId, description, tag, seconds)
    }

    func updateActivity(activityId: Int, projectId: Int?, taskId: Int?, description: String?, tag: String?, seconds: Int?) async throws -> MocoActivity {
        try await updateActivityHandler(activityId, description, tag, seconds)
    }

    func deleteActivity(activityId: Int) async throws {
        try await deleteActivityHandler(activityId)
    }

    func fetchPlanningEntries(period: String, userId: Int?) async throws -> [MocoPlanningEntry] { [] }
    func fetchSchedules(from: String, to: String) async throws -> [MocoSchedule] { [] }

    func startTimer(activityId: Int) async throws -> MocoActivity {
        try await startTimerHandler(activityId)
    }

    func stopTimer(activityId: Int) async throws -> MocoActivity {
        try await stopTimerHandler(activityId)
    }
}

// MARK: - Tests

@Suite("SyncEngine")
struct SyncEngineTests {

    private static func makeStore() throws -> ShadowEntryStore {
        let db = try SQLiteDatabase(path: ":memory:")
        return try ShadowEntryStore(database: db)
    }

    // MARK: - Pull Tests

    @Test("Pull inserts new entries from server")
    func pullInsertsNewEntries() async throws {
        let store = try Self.makeStore()
        let syncState = await SyncState()
        let a1 = TestFactories.makeActivity(id: 1, date: "2025-06-01")
        let a2 = TestFactories.makeActivity(id: 2, date: "2025-06-01", projectId: 101, projectName: "Other")

        var mock = MockSyncAPI()
        mock.fetchActivitiesHandler = { _, _, _ in [a1, a2] }

        let engine = SyncEngine(
            store: store,
            clientFactory: { mock },
            userIdProvider: { 42 },
            syncState: syncState
        )

        try await engine.pullRemote(date: "2025-06-01")

        let entries = try await store.entries(forDate: "2025-06-01")
        #expect(entries.count == 2)
        #expect(entries.allSatisfy { $0.sync.status == .synced })
    }

    @Test("Pull updates changed entries with newer updatedAt")
    func pullUpdatesChangedEntries() async throws {
        let store = try Self.makeStore()
        let syncState = await SyncState()

        // Insert an existing synced entry with old updatedAt
        var existing = TestFactories.makeShadowEntry(id: 10, date: "2025-06-01")
        existing.sync.serverUpdatedAt = "2025-01-01T00:00:00Z"
        existing.updatedAt = "2025-01-01T00:00:00Z"
        existing.description = "old description"
        try await store.insert(existing)

        // Server returns same ID with newer updatedAt and new description
        let updated = TestFactories.makeActivity(id: 10, date: "2025-06-01", description: "new description")

        var mock = MockSyncAPI()
        mock.fetchActivitiesHandler = { _, _, _ in [updated] }

        let engine = SyncEngine(
            store: store,
            clientFactory: { mock },
            userIdProvider: { 42 },
            syncState: syncState
        )

        try await engine.pullRemote(date: "2025-06-01")

        let entry = try await store.entry(id: 10)
        #expect(entry != nil)
        // The entry should be updated since serverUpdatedAt differs from server's updatedAt
    }

    @Test("Pull detects conflict on dirty entry with server changes")
    func pullDetectsConflict() async throws {
        let store = try Self.makeStore()
        let syncState = await SyncState()

        // Insert a dirty local entry with an older serverUpdatedAt than the server's updatedAt
        var dirty = TestFactories.makeShadowEntry(id: 20, date: "2025-06-01", syncStatus: .dirty)
        dirty.sync.serverUpdatedAt = "2024-12-01T00:00:00Z"
        dirty.description = "local edit"
        try await store.insert(dirty)

        // Server returns same ID with different updatedAt — conflict
        let serverVersion = TestFactories.makeActivity(id: 20, date: "2025-06-01", description: "server edit")

        var mock = MockSyncAPI()
        mock.fetchActivitiesHandler = { _, _, _ in [serverVersion] }

        let engine = SyncEngine(
            store: store,
            clientFactory: { mock },
            userIdProvider: { 42 },
            syncState: syncState
        )

        try await engine.pullRemote(date: "2025-06-01")

        let entry = try await store.entry(id: 20)
        #expect(entry != nil)
        #expect(entry?.sync.conflictFlag == true)
        #expect(entry?.sync.status == .synced)
    }

    @Test("Pull removes server-deleted entries")
    func pullRemovesServerDeletedEntries() async throws {
        let store = try Self.makeStore()
        let syncState = await SyncState()

        // Insert 3 synced entries
        try await store.insert(TestFactories.makeShadowEntry(id: 30, date: "2025-06-01"))
        try await store.insert(TestFactories.makeShadowEntry(id: 31, date: "2025-06-01", projectId: 101))
        try await store.insert(TestFactories.makeShadowEntry(id: 32, date: "2025-06-01", projectId: 102))

        // Server only returns 2 of them — third was deleted
        let a1 = TestFactories.makeActivity(id: 30, date: "2025-06-01")
        let a2 = TestFactories.makeActivity(id: 31, date: "2025-06-01", projectId: 101)

        var mock = MockSyncAPI()
        mock.fetchActivitiesHandler = { _, _, _ in [a1, a2] }

        let engine = SyncEngine(
            store: store,
            clientFactory: { mock },
            userIdProvider: { 42 },
            syncState: syncState
        )

        try await engine.pullRemote(date: "2025-06-01")

        let entries = try await store.entries(forDate: "2025-06-01")
        #expect(entries.count == 2)
        let entry32 = try await store.entry(id: 32)
        #expect(entry32 == nil)
    }

    @Test("Pull propagates locked field from API")
    func pullPropagatesLockedField() async throws {
        let store = try Self.makeStore()
        let syncState = await SyncState()

        let lockedActivity = TestFactories.makeActivity(id: 50, date: "2025-06-01", locked: true)

        var mock = MockSyncAPI()
        mock.fetchActivitiesHandler = { _, _, _ in [lockedActivity] }

        let engine = SyncEngine(
            store: store,
            clientFactory: { mock },
            userIdProvider: { 42 },
            syncState: syncState
        )

        try await engine.pullRemote(date: "2025-06-01")

        let entry = try await store.entry(id: 50)
        #expect(entry != nil)
        #expect(entry?.locked == true)
    }

    // MARK: - Push Tests

    @Test("Push creates pending entries via API")
    func pushCreatesPendingEntries() async throws {
        let store = try Self.makeStore()
        let syncState = await SyncState()

        // Insert a pendingCreate entry with a localId (no server ID yet)
        var pending = TestFactories.makeShadowEntry(date: "2025-06-01", syncStatus: .pendingCreate)
        pending.localId = "local-abc"
        pending.id = nil
        try await store.insert(pending)

        // Mock: createActivity returns a server-assigned activity
        let serverActivity = TestFactories.makeActivity(id: 999, date: "2025-06-01")

        var mock = MockSyncAPI()
        mock.createActivityHandler = { _, _, _, _, _, _ in serverActivity }

        let engine = SyncEngine(
            store: store,
            clientFactory: { mock },
            userIdProvider: { 42 },
            syncState: syncState
        )

        try await engine.pushDirty()

        // The local-only entry should be gone, replaced by server entry
        let local = try await store.entry(localId: "local-abc")
        #expect(local == nil)
        let server = try await store.entry(id: 999)
        #expect(server != nil)
        #expect(server?.sync.status == .synced)
    }

    @Test("Push updates dirty entries via API")
    func pushUpdatesDirtyEntries() async throws {
        let store = try Self.makeStore()
        let syncState = await SyncState()

        let dirty = TestFactories.makeShadowEntry(id: 60, date: "2025-06-01", syncStatus: .dirty)
        try await store.insert(dirty)

        let updatedActivity = TestFactories.makeActivity(id: 60, date: "2025-06-01")

        var mock = MockSyncAPI()
        mock.updateActivityHandler = { _, _, _, _ in updatedActivity }

        let engine = SyncEngine(
            store: store,
            clientFactory: { mock },
            userIdProvider: { 42 },
            syncState: syncState
        )

        try await engine.pushDirty()

        let entry = try await store.entry(id: 60)
        #expect(entry?.sync.status == .synced)
    }

    // MARK: - SyncState Tests

    @Test("Sync updates lastSyncedAt on success")
    func syncUpdatesLastSyncedAt() async throws {
        let store = try Self.makeStore()
        let syncState = await SyncState()

        let mock = MockSyncAPI()

        let engine = SyncEngine(
            store: store,
            clientFactory: { mock },
            userIdProvider: { 42 },
            syncState: syncState
        )

        await engine.sync(dates: ["2025-06-01"])

        await MainActor.run {
            #expect(syncState.lastSyncedAt != nil)
            #expect(syncState.isSyncing == false)
        }
    }

    @Test("Sync sets lastError on API failure")
    func syncSetsLastErrorOnFailure() async throws {
        let store = try Self.makeStore()
        let syncState = await SyncState()

        var mock = MockSyncAPI()
        mock.fetchActivitiesHandler = { _, _, _ in
            throw MocoError.serverError(statusCode: 500, message: "test error")
        }

        let engine = SyncEngine(
            store: store,
            clientFactory: { mock },
            userIdProvider: { 42 },
            syncState: syncState
        )

        await engine.sync(dates: ["2025-06-01"])

        await MainActor.run {
            #expect(syncState.lastError != nil)
            #expect(syncState.isSyncing == false)
        }
    }

    @Test("Pull preserves local start_time when updating from server")
    func pullPreservesLocalStartTime() async throws {
        let store = try Self.makeStore()
        let syncState = await SyncState()

        // Insert a synced entry with a local start_time and old serverUpdatedAt
        var existing = TestFactories.makeShadowEntry(id: 80, date: "2025-06-01", startTime: "09:15")
        existing.sync.serverUpdatedAt = "2024-12-01T00:00:00Z"
        existing.updatedAt = "2024-12-01T00:00:00Z"
        try await store.insert(existing)

        // Server returns same ID with newer updatedAt — triggers updateFromServer path
        let serverVersion = TestFactories.makeActivity(id: 80, date: "2025-06-01", description: "server update")

        var mock = MockSyncAPI()
        mock.fetchActivitiesHandler = { _, _, _ in [serverVersion] }

        let engine = SyncEngine(
            store: store,
            clientFactory: { mock },
            userIdProvider: { 42 },
            syncState: syncState
        )

        try await engine.pullRemote(date: "2025-06-01")

        let entry = try await store.entry(id: 80)
        #expect(entry != nil)
        #expect(entry?.startTime == "09:15") // local start_time preserved
    }

    @Test("Push with zero dirty entries is a no-op")
    func pushWithNoDirtyEntriesIsNoOp() async throws {
        let store = try Self.makeStore()
        let syncState = await SyncState()

        // Insert only synced entries
        try await store.insert(TestFactories.makeShadowEntry(id: 70, date: "2025-06-01"))

        var createCalled = false
        var mock = MockSyncAPI()
        mock.createActivityHandler = { _, _, _, _, _, _ in
            createCalled = true
            throw MocoError.serverError(statusCode: 500, message: "should not be called")
        }

        let engine = SyncEngine(
            store: store,
            clientFactory: { mock },
            userIdProvider: { 42 },
            syncState: syncState
        )

        try await engine.pushDirty()
        #expect(createCalled == false)
    }
}
