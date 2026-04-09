import Testing
import Foundation
@testable import MocoCompanion

@Suite("PlanningStore")
struct PlanningStoreTests {

    // MARK: - Helpers

    @MainActor
    private func makeStore(
        api: MockActivityAPI = MockActivityAPI(),
        userId: Int? = 42,
        todayActivities: @escaping () -> [MocoActivity] = { [] }
    ) -> (PlanningStore, MockActivityAPI) {
        let capturedAPI = api
        let store = PlanningStore(
            clientFactory: { capturedAPI },
            userIdProvider: { userId },
            todayActivitiesProvider: todayActivities
        )
        return (store, capturedAPI)
    }

    // MARK: - refreshTodayPlanning

    @Test("refreshTodayPlanning populates today planning entries")
    @MainActor func refreshTodayPopulates() async {
        var api = MockActivityAPI()
        let entry1 = TestFactories.makePlanningEntry(id: 1, projectId: 100, taskId: 200, hoursPerDay: 4.0)
        let entry2 = TestFactories.makePlanningEntry(id: 2, projectId: 101, taskId: 201, hoursPerDay: 4.0)
        api.fetchPlanningEntriesHandler = { _, _ in [entry1, entry2] }

        let (store, _) = makeStore(api: api)
        await store.refreshTodayPlanning()

        #expect(store.todayPlanningEntries.count == 2)
        #expect(store.todayPlanningEntries.map(\.id).contains(1))
        #expect(store.todayPlanningEntries.map(\.id).contains(2))
    }

    @Test("refreshTodayPlanning with nil userId skips fetch")
    @MainActor func refreshTodayNilUserId() async {
        var api = MockActivityAPI()
        var fetchCalled = false
        api.fetchPlanningEntriesHandler = { _, _ in
            fetchCalled = true
            return []
        }

        let (store, _) = makeStore(api: api, userId: nil)
        await store.refreshTodayPlanning()

        #expect(!fetchCalled)
        #expect(store.todayPlanningEntries.isEmpty)
    }

    // MARK: - refreshTomorrowPlanning

    @Test("refreshTomorrowPlanning populates tomorrow planning entries")
    @MainActor func refreshTomorrowPopulates() async {
        var api = MockActivityAPI()
        let tomorrow = DateUtilities.tomorrowString()!
        let entry = TestFactories.makePlanningEntry(id: 3, startsOn: tomorrow, endsOn: tomorrow)
        api.fetchPlanningEntriesHandler = { _, _ in [entry] }

        let (store, _) = makeStore(api: api)
        await store.refreshTomorrowPlanning()

        #expect(store.tomorrowPlanningEntries.count == 1)
        #expect(store.tomorrowPlanningEntries.first?.id == 3)
    }

    // MARK: - unplannedTasks

    @Test("unplannedTasks filters out tasks already tracked in today activities")
    @MainActor func unplannedFiltersTracked() async {
        var api = MockActivityAPI()
        let tracked = TestFactories.makeActivity(id: 1, projectId: 100, taskId: 200)
        let planned1 = TestFactories.makePlanningEntry(id: 10, projectId: 100, taskId: 200)
        let planned2 = TestFactories.makePlanningEntry(id: 11, projectId: 101, taskId: 201)
        api.fetchPlanningEntriesHandler = { _, _ in [planned1, planned2] }

        let (store, _) = makeStore(api: api, todayActivities: { [tracked] })
        await store.refreshTodayPlanning()

        let unplanned = store.unplannedTasks
        #expect(unplanned.count == 1)
        #expect(unplanned.first?.projectId == 101)
        #expect(unplanned.first?.taskId == 201)
    }

    @Test("unplannedTasks returns all entries when no activities tracked")
    @MainActor func unplannedAllWhenNoActivities() async {
        var api = MockActivityAPI()
        let planned1 = TestFactories.makePlanningEntry(id: 10, projectId: 100, taskId: 200)
        let planned2 = TestFactories.makePlanningEntry(id: 11, projectId: 101, taskId: 201)
        api.fetchPlanningEntriesHandler = { _, _ in [planned1, planned2] }

        let (store, _) = makeStore(api: api, todayActivities: { [] })
        await store.refreshTodayPlanning()

        let unplanned = store.unplannedTasks
        #expect(unplanned.count == 2)
    }

    // MARK: - absence lookup

    @Test("absence(for:) returns schedule when present for date")
    @MainActor func absenceLookupFound() async {
        var api = MockActivityAPI()
        let today = DateUtilities.todayString()
        let schedule = TestFactories.makeSchedule(id: 1, date: today, userId: 42)
        api.fetchSchedulesHandler = { _, _ in [schedule] }

        let (store, _) = makeStore(api: api)
        await store.refreshAbsences()

        let result = store.absence(for: today)
        #expect(result != nil)
        #expect(result?.id == 1)
    }

    @Test("absence(for:) returns nil for date with no absence")
    @MainActor func absenceLookupMissing() async {
        let (store, _) = makeStore()

        let result = store.absence(for: "2099-12-31")
        #expect(result == nil)
    }

    // MARK: - plannedHours

    @Test("plannedHours returns sum for matching project/task")
    @MainActor func plannedHoursSum() async {
        var api = MockActivityAPI()
        let entry1 = TestFactories.makePlanningEntry(id: 1, projectId: 100, taskId: 200, hoursPerDay: 3.0)
        let entry2 = TestFactories.makePlanningEntry(id: 2, projectId: 100, taskId: 200, hoursPerDay: 2.0)
        let entry3 = TestFactories.makePlanningEntry(id: 3, projectId: 101, taskId: 201, hoursPerDay: 8.0)
        api.fetchPlanningEntriesHandler = { _, _ in [entry1, entry2, entry3] }

        let (store, _) = makeStore(api: api)
        await store.refreshTodayPlanning()

        let hours = store.plannedHours(projectId: 100, taskId: 200)
        #expect(hours == 5.0)

        let noMatch = store.plannedHours(projectId: 999, taskId: 999)
        #expect(noMatch == nil)
    }
}
