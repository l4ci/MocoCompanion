import Testing
import Foundation
@testable import MocoCompanion

@Suite("ActivityService")
struct ActivityServiceTests {

    // MARK: - Helpers

    @MainActor
    private func makeService(
        api: MockActivityAPI = MockActivityAPI()
    ) -> (ActivityService, MockActivityAPI) {
        let capturedAPI = api
        let dispatcher = NotificationDispatcher(isEnabledCheck: { _ in false })
        let service = ActivityService(
            clientFactory: { capturedAPI },
            notificationDispatcher: dispatcher,
            userIdProvider: { 42 }
        )
        return (service, capturedAPI)
    }

    // MARK: - refreshTodayStats

    @Test("refreshTodayStats populates activities and recomputes hours/billable percentage")
    @MainActor func refreshPopulatesStats() async {
        var api = MockActivityAPI()
        let a1 = TestFactories.makeActivity(id: 1, seconds: 3600, hours: 1.0, billable: true)
        let a2 = TestFactories.makeActivity(id: 2, seconds: 1800, hours: 0.5, billable: false)
        api.fetchActivitiesHandler = { _, _, _ in [a1, a2] }

        let (service, _) = makeService(api: api)
        await service.refreshTodayStats()

        #expect(service.todayActivities.count == 2)
        #expect(service.todayTotalHours == 1.5)
        // Only a1 is billable (1.0h), total is 1.5h → 66.67%
        #expect(abs(service.todayBillablePercentage - (1.0 / 1.5 * 100.0)) < 0.01)
    }

    @Test("refreshTodayStats with nil client returns silently (empty state)")
    @MainActor func refreshWithNilClient() async {
        let dispatcher = NotificationDispatcher(isEnabledCheck: { _ in false })
        let service = ActivityService(
            clientFactory: { nil as (any ActivityAPI)? },
            notificationDispatcher: dispatcher,
            userIdProvider: { 42 }
        )

        await service.refreshTodayStats()

        #expect(service.todayActivities.isEmpty)
        #expect(service.todayTotalHours == 0)
        #expect(service.todayBillablePercentage == 0)
    }

    // MARK: - updateDescription

    @Test("updateDescription calls API and upserts locally")
    @MainActor func updateDescriptionUpsertsLocally() async {
        var api = MockActivityAPI()
        let original = TestFactories.makeActivity(id: 5, description: "old")
        api.fetchActivitiesHandler = { _, _, _ in [original] }

        let updated = TestFactories.makeActivity(id: 5, description: "new desc")
        api.updateActivityDescTag = { activityId, description, tag in
            #expect(activityId == 5)
            return updated
        }

        let (service, _) = makeService(api: api)
        await service.refreshTodayStats()
        #expect(service.todayActivities.count == 1)

        await service.updateDescription(activityId: 5, description: "new desc")

        let found = service.todayActivities.first(where: { $0.id == 5 })
        #expect(found?.description == "new desc")
    }

    // MARK: - deleteActivity

    @Test("deleteActivity removes from local arrays and invokes timer stop")
    @MainActor func deleteRemovesLocally() async {
        var api = MockActivityAPI()
        let a1 = TestFactories.makeActivity(id: 10)
        let a2 = TestFactories.makeActivity(id: 20)
        api.fetchActivitiesHandler = { _, _, _ in [a1, a2] }
        api.deleteActivityHandler = { _ in }

        let (service, capturedAPI) = makeService(api: api)
        await service.refreshTodayStats()
        #expect(service.todayActivities.count == 2)

        let dispatcher = NotificationDispatcher(isEnabledCheck: { _ in false })
        let deleteUndo = DeleteUndoManager(
            clientFactory: { capturedAPI },
            activityService: service,
            shadowEntryStore: try! ShadowEntryStore(database: SQLiteDatabase(path: ":memory:")),
            notificationDispatcher: dispatcher
        )
        let mockTimer = MockTimerStopProvider()
        deleteUndo.timerStopProvider = mockTimer

        await deleteUndo.deleteActivity(activityId: 10)

        #expect(service.todayActivities.count == 1)
        #expect(service.todayActivities.first?.id == 20)
        #expect(mockTimer.stoppedActivityId == 10)
    }

    // MARK: - editActivity

    @Test("editActivity upserts in today array with new seconds")
    @MainActor func editActivityUpserts() async {
        var api = MockActivityAPI()
        let original = TestFactories.makeActivity(id: 7, seconds: 3600, hours: 1.0)
        api.fetchActivitiesHandler = { _, _, _ in [original] }

        let edited = TestFactories.makeActivity(id: 7, seconds: 7200, hours: 2.0)
        api.updateActivityFull = { activityId, description, tag, seconds in
            #expect(activityId == 7)
            #expect(seconds == 7200)
            return edited
        }

        let (service, _) = makeService(api: api)
        await service.refreshTodayStats()

        await service.editActivity(activityId: 7, seconds: 7200)

        let found = service.todayActivities.first(where: { $0.id == 7 })
        #expect(found?.seconds == 7200)
        #expect(service.todayTotalHours == 2.0)
    }

    // MARK: - bookManualEntry

    @Test("bookManualEntry appends to today activities and fires side effect")
    @MainActor func bookManualEntrySuccess() async {
        var api = MockActivityAPI()
        let created = TestFactories.makeActivity(
            id: 99, projectId: 100, projectName: "Booked Project",
            taskId: 200, seconds: 1800, hours: 0.5, description: "manual"
        )
        api.createActivityHandler = { _, _, _, _, _, _ in created }

        let (service, _) = makeService(api: api)
        #expect(service.todayActivities.isEmpty)

        let result = await service.bookManualEntry(
            date: "2026-04-01", projectId: 100, taskId: 200,
            projectName: "Booked Project", taskName: "Task", customerName: "Customer",
            description: "manual", seconds: 1800
        )

        switch result {
        case .success(let activity):
            #expect(activity.id == 99)
        case .failure(let error):
            Issue.record("Expected success, got \(error)")
        }
        #expect(service.todayActivities.count == 1)
        #expect(service.todayTotalHours == 0.5)
    }

    @Test("bookManualEntry returns failure on API error")
    @MainActor func bookManualEntryFailure() async {
        var api = MockActivityAPI()
        api.createActivityHandler = { _, _, _, _, _, _ in
            throw MocoError.serverError(statusCode: 422, message: "Validation failed")
        }

        let (service, _) = makeService(api: api)
        let result = await service.bookManualEntry(
            date: "2026-04-01", projectId: 100, taskId: 200,
            projectName: "Project", taskName: "Task", customerName: "Customer",
            description: "test", seconds: 3600
        )

        switch result {
        case .success:
            Issue.record("Expected failure")
        case .failure:
            break // expected
        }
        #expect(service.todayActivities.isEmpty)
    }

    @Test("bookManualEntry queues a pendingCreate row and succeeds when offline")
    @MainActor func bookManualEntryOffline() async throws {
        var api = MockActivityAPI()
        api.createActivityHandler = { _, _, _, _, _, _ in
            throw MocoError.networkError(URLError(.notConnectedToInternet))
        }

        let store = try ShadowEntryStore(database: SQLiteDatabase(path: ":memory:"))
        let syncState = SyncState()
        // nonisolated(unsafe) suppresses the sending diagnostic — safe because
        // these closures capture no state (mirrors AppState.buildStorage).
        nonisolated(unsafe) let noClient: () -> (any ActivityAPI & TimerAPI)? = { nil }
        nonisolated(unsafe) let fixedUserId: () -> Int? = { 42 }
        let syncEngine = SyncEngine(
            store: store,
            clientFactory: noClient,
            userIdProvider: fixedUserId,
            syncState: syncState
        )

        let (service, _) = makeService(api: api)
        service.syncEngine = syncEngine

        let result = await service.bookManualEntry(
            date: "2026-04-01", projectId: 100, taskId: 200,
            projectName: "Offline Project", taskName: "Offline Task", customerName: "Offline Customer",
            description: "manual #TICKET-1", seconds: 1800
        )

        guard case .success(let entry) = result else {
            Issue.record("Expected success, got \(result)")
            return
        }
        #expect(entry.localId != nil)
        #expect(entry.id == nil)
        #expect(entry.sync.status == .pendingCreate)
        #expect(entry.description == "manual")
        #expect(entry.tag == "TICKET-1")
        #expect(entry.projectName == "Offline Project")

        // Appears in today's list immediately (optimistic local update).
        #expect(service.todayActivities.count == 1)
        #expect(service.todayActivities.first?.sync.status == .pendingCreate)

        // Persisted to the shadow store as a dirty (pendingCreate) row, ready
        // for SyncEngine.pushDirty() to pick up on the next sync.
        let dirty = try await store.dirtyEntries()
        #expect(dirty.count == 1)
        #expect(dirty.first?.sync.status == .pendingCreate)
        #expect(dirty.first?.projectId == 100)
        #expect(dirty.first?.tag == "TICKET-1")

        // The offline banner's pending count is updated immediately, not
        // just after the next sync cycle.
        #expect(syncState.pendingChanges == 1)
    }

    // MARK: - duplicateToToday

    @Test("duplicateToToday creates activity with today's date")
    @MainActor func duplicateToTodaySuccess() async {
        var api = MockActivityAPI()
        let source = TestFactories.makeActivity(
            id: 50, date: "2026-03-31", projectId: 100,
            taskId: 200, seconds: 3600, hours: 1.0, description: "yesterday work"
        )
        let duplicated = TestFactories.makeActivity(
            id: 51, projectId: 100, taskId: 200,
            seconds: 3600, hours: 1.0, description: "yesterday work"
        )
        api.createActivityHandler = { date, projectId, taskId, description, seconds, tag in
            #expect(projectId == 100)
            #expect(taskId == 200)
            #expect(seconds == 3600)
            return duplicated
        }

        let (service, _) = makeService(api: api)
        let result = await service.duplicateToToday(entry: ShadowEntry.from(source))

        switch result {
        case .success(let activity):
            #expect(activity.id == 51)
        case .failure(let error):
            Issue.record("Expected success, got \(error)")
        }
        #expect(service.todayActivities.count == 1)
    }

    // MARK: - upsertActivity(fromServer:)

    @Test("upsertActivity(fromServer:) inserts new and updates existing")
    @MainActor func upsertInsertAndUpdate() async {
        var api = MockActivityAPI()
        let existing = TestFactories.makeActivity(id: 30, seconds: 3600, hours: 1.0)
        api.fetchActivitiesHandler = { _, _, _ in [existing] }

        let (service, _) = makeService(api: api)
        await service.refreshTodayStats()
        #expect(service.todayActivities.count == 1)

        // Update existing
        let updatedExisting = TestFactories.makeActivity(id: 30, seconds: 7200, hours: 2.0)
        service.upsertActivity(fromServer: updatedExisting)
        #expect(service.todayActivities.first(where: { $0.id == 30 })?.seconds == 7200)

        // Insert new (activity with today's date not already in array)
        let brand = TestFactories.makeActivity(id: 31, seconds: 1800, hours: 0.5)
        service.upsertActivity(fromServer: brand)
        #expect(service.todayActivities.count == 2)
        #expect(service.todayActivities.contains(where: { $0.id == 31 }))
    }

    @Test("upsertActivity(fromServer:) preserves local origin metadata")
    @MainActor func upsertPreservesOrigin() async {
        let (service, _) = makeService()

        // Inject a today entry with origin metadata via the public
        // restoreToday entry point (the path DeleteUndoManager uses on
        // undo). Simulates an autotracker-driven create that the server
        // doesn't know about.
        var seeded = TestFactories.makeShadowEntry(id: 40, seconds: 3600, hours: 1.0)
        seeded.startTime = "09:30"
        seeded.origin = ShadowEntry.Origin(
            appBundleId: "com.example.app",
            ruleId: 7,
            calendarEventId: nil
        )
        service.restoreToday(seeded)

        // A server response after editing the same entry would normally
        // zero out origin metadata via plain `ShadowEntry.from(_:)`. The
        // (fromServer:) variant must merge the prior local row.
        let edited = TestFactories.makeActivity(id: 40, seconds: 7200, hours: 2.0)
        let merged = service.upsertActivity(fromServer: edited)

        #expect(merged.origin.appBundleId == "com.example.app")
        #expect(merged.origin.ruleId == 7)
        #expect(merged.startTime == "09:30")
        #expect(merged.seconds == 7200)

        let row = service.todayActivities.first(where: { $0.id == 40 })
        #expect(row?.origin.appBundleId == "com.example.app")
        #expect(row?.seconds == 7200)
    }

    // MARK: - sortedTodayActivities

    @Test("sortedTodayActivities puts running timer first")
    @MainActor func sortedPutsRunningFirst() async {
        var api = MockActivityAPI()
        let stopped = TestFactories.makeActivity(id: 1, seconds: 3600, hours: 1.0, timerStartedAt: nil)
        let running = TestFactories.makeActivity(id: 2, seconds: 100, hours: 0.028, timerStartedAt: "2026-04-01T10:00:00Z")
        api.fetchActivitiesHandler = { _, _, _ in [stopped, running] }

        let (service, _) = makeService(api: api)
        await service.refreshTodayStats()

        let sorted = service.sortedTodayActivities
        #expect(sorted.first?.id == 2) // running timer comes first
        #expect(sorted.last?.id == 1)
    }

    // MARK: - PlanningStore (tested directly, no longer forwarded)

    @Test("unplannedTasks filters planning entries against tracked activities")
    @MainActor func unplannedFiltersTracked() async {
        var api = MockActivityAPI()
        let tracked = TestFactories.makeActivity(id: 1, projectId: 100, taskId: 200)
        api.fetchActivitiesHandler = { _, _, _ in [tracked] }

        let planned1 = TestFactories.makePlanningEntry(id: 10, projectId: 100, taskId: 200)
        let planned2 = TestFactories.makePlanningEntry(id: 11, projectId: 101, taskId: 201, taskName: "Unplanned Task")
        api.fetchPlanningEntriesHandler = { _, _ in [planned1, planned2] }

        let (service, capturedAPI) = makeService(api: api)
        await service.refreshTodayStats()
        let planningStore = PlanningStore(
            clientFactory: { capturedAPI },
            userIdProvider: { 42 },
            todayActivitiesProvider: { [weak service] in service?.todayActivities ?? [] }
        )
        await planningStore.refreshTodayPlanning()

        let unplanned = planningStore.unplannedTasks
        #expect(unplanned.count == 1)
        #expect(unplanned.first?.taskId == 201)
    }

    @Test("refreshAllPlanning splits entries into today and tomorrow")
    @MainActor func refreshAllPlanningSplits() async {
        var api = MockActivityAPI()
        let today = DateUtilities.todayString()
        let calendar = Calendar.current
        let tomorrowDate = calendar.date(byAdding: .day, value: 1, to: Date())!
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let tomorrow = formatter.string(from: tomorrowDate)

        let todayEntry = TestFactories.makePlanningEntry(
            id: 1, projectId: 100, taskId: 200,
            startsOn: today, endsOn: today
        )
        let tomorrowEntry = TestFactories.makePlanningEntry(
            id: 2, projectId: 101, taskId: 201,
            startsOn: tomorrow, endsOn: tomorrow
        )
        api.fetchPlanningEntriesHandler = { _, _ in [todayEntry, tomorrowEntry] }

        let planningStore = PlanningStore(
            clientFactory: { api },
            userIdProvider: { 42 },
            todayActivitiesProvider: { [] }
        )
        await planningStore.refreshAllPlanning()

        #expect(planningStore.todayPlanningEntries.count == 1)
        #expect(planningStore.todayPlanningEntries.first?.id == 1)
        #expect(planningStore.tomorrowPlanningEntries.count == 1)
        #expect(planningStore.tomorrowPlanningEntries.first?.id == 2)
    }
}

// MARK: - Test Helpers

@MainActor
final class MockTimerStopProvider: TimerStopProvider {
    var timerState: TimerState = .idle
    var stoppedActivityId: Int?

    func stopTimer() async {
        // no-op
    }

    func stopTimerIfActive(activityId: Int) async {
        stoppedActivityId = activityId
    }
}
