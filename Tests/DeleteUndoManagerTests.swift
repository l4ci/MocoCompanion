import Testing
import Foundation
@testable import MocoCompanion

@Suite("DeleteUndoManager")
struct DeleteUndoManagerTests {

    // MARK: - Helpers

    @MainActor
    private func makeService(
        api: MockActivityAPI = MockActivityAPI()
    ) -> (DeleteUndoManager, ActivityService, MockActivityAPI) {
        let capturedAPI = api
        let dispatcher = NotificationDispatcher(isEnabledCheck: { _ in false })
        let service = ActivityService(
            clientFactory: { capturedAPI },
            notificationDispatcher: dispatcher,
            userIdProvider: { 42 }
        )
        let undoManager = DeleteUndoManager(
            clientFactory: { capturedAPI },
            activityService: service,
            notificationDispatcher: dispatcher
        )
        return (undoManager, service, capturedAPI)
    }

    // MARK: - Delete removes locally

    @Test("deleteActivity removes activity from local today array")
    @MainActor func deleteRemovesLocally() async {
        var api = MockActivityAPI()
        let a1 = TestFactories.makeActivity(id: 10)
        let a2 = TestFactories.makeActivity(id: 20)
        api.fetchActivitiesHandler = { _, _, _ in [a1, a2] }
        api.deleteActivityHandler = { _ in }

        let (undoManager, service, _) = makeService(api: api)
        await service.refreshTodayStats()
        #expect(service.todayActivities.count == 2)

        await undoManager.deleteActivity(activityId: 10)

        #expect(service.todayActivities.count == 1)
        #expect(service.todayActivities.first?.id == 20)
    }

    // MARK: - Undo restores

    @Test("undoDelete restores the activity to the local today array")
    @MainActor func undoRestoresToday() async {
        var api = MockActivityAPI()
        let activity = TestFactories.makeActivity(id: 10, seconds: 3600, hours: 1.0)
        api.fetchActivitiesHandler = { _, _, _ in [activity] }
        api.deleteActivityHandler = { _ in }

        let (undoManager, service, _) = makeService(api: api)
        await service.refreshTodayStats()
        #expect(service.todayActivities.count == 1)

        await undoManager.deleteActivity(activityId: 10)
        #expect(service.todayActivities.isEmpty)
        #expect(undoManager.pendingDelete != nil)

        undoManager.undoDelete()

        #expect(service.todayActivities.count == 1)
        #expect(service.todayActivities.first?.id == 10)
        #expect(undoManager.pendingDelete == nil)
    }

    // MARK: - Commit calls API

    @Test("commitPendingDelete calls deleteActivity on the API")
    @MainActor func commitCallsAPI() async {
        var api = MockActivityAPI()
        let activity = TestFactories.makeActivity(id: 10)
        api.fetchActivitiesHandler = { _, _, _ in [activity] }

        var deletedIds: [Int] = []
        api.deleteActivityHandler = { id in deletedIds.append(id) }

        let (undoManager, service, _) = makeService(api: api)
        await service.refreshTodayStats()

        await undoManager.deleteActivity(activityId: 10)
        #expect(undoManager.pendingDelete != nil)

        await undoManager.commitPendingDelete()

        #expect(deletedIds.contains(10))
        #expect(undoManager.pendingDelete == nil)
    }

    // MARK: - Grace period (pending delete exists)

    @Test("pendingDelete is set after delete and cleared after undo")
    @MainActor func gracePeriodPendingState() async {
        var api = MockActivityAPI()
        let activity = TestFactories.makeActivity(id: 10)
        api.fetchActivitiesHandler = { _, _, _ in [activity] }
        api.deleteActivityHandler = { _ in }

        let (undoManager, service, _) = makeService(api: api)
        await service.refreshTodayStats()

        await undoManager.deleteActivity(activityId: 10)
        #expect(undoManager.pendingDelete != nil)
        #expect(undoManager.pendingDelete?.activity.id == 10)

        undoManager.undoDelete()
        #expect(undoManager.pendingDelete == nil)
    }

    // MARK: - Second delete commits first

    @Test("starting a second delete immediately commits the first pending delete")
    @MainActor func secondDeleteCommitsFirst() async {
        var api = MockActivityAPI()
        let a1 = TestFactories.makeActivity(id: 10)
        let a2 = TestFactories.makeActivity(id: 20)
        api.fetchActivitiesHandler = { _, _, _ in [a1, a2] }

        var deletedIds: [Int] = []
        api.deleteActivityHandler = { id in deletedIds.append(id) }

        let (undoManager, service, _) = makeService(api: api)
        await service.refreshTodayStats()

        await undoManager.deleteActivity(activityId: 10)
        #expect(undoManager.pendingDelete?.activity.id == 10)

        await undoManager.deleteActivity(activityId: 20)

        // First delete should have been committed to the API
        #expect(deletedIds.contains(10))
        // Second delete is now pending
        #expect(undoManager.pendingDelete?.activity.id == 20)
    }

    // MARK: - Timer stop via protocol

    @Test("deleteActivity calls timerStopProvider.stopTimerIfActive")
    @MainActor func deleteStopsTimerViaProtocol() async {
        var api = MockActivityAPI()
        let activity = TestFactories.makeActivity(id: 10)
        api.fetchActivitiesHandler = { _, _, _ in [activity] }
        api.deleteActivityHandler = { _ in }

        let (undoManager, service, _) = makeService(api: api)
        await service.refreshTodayStats()

        let mockTimer = MockTimerStopProvider()
        undoManager.timerStopProvider = mockTimer

        await undoManager.deleteActivity(activityId: 10)

        #expect(mockTimer.stoppedActivityId == 10)
    }

    // MARK: - Nil client guard

    @Test("deleteActivity with nil client returns silently")
    @MainActor func deleteWithNilClient() async {
        let dispatcher = NotificationDispatcher(isEnabledCheck: { _ in false })
        let service = ActivityService(
            clientFactory: { nil as (any ActivityAPI)? },
            notificationDispatcher: dispatcher,
            userIdProvider: { 42 }
        )
        let undoManager = DeleteUndoManager(
            clientFactory: { nil as (any ActivityAPI)? },
            activityService: service,
            notificationDispatcher: dispatcher
        )

        await undoManager.deleteActivity(activityId: 10)

        #expect(undoManager.pendingDelete == nil)
        #expect(service.todayActivities.isEmpty)
    }
}
