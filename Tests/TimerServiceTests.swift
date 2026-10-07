import Testing
import Foundation
@testable import MocoCompanion

@Suite("TimerService")
struct TimerServiceTests {

    // MARK: - Helpers

    @MainActor
    private func makeService(
        api: MockTimerAPI = MockTimerAPI()
    ) -> (TimerService, MockTimerAPI) {
        let capturedAPI = api
        let service = TimerService(
            clientFactory: { capturedAPI },
            userIdProvider: { 42 }
        )
        return (service, capturedAPI)
    }

    /// Build a MockTimerAPI pre-wired for a successful start flow.
    private func makeStartableAPI() -> MockTimerAPI {
        var api = MockTimerAPI()
        api.createActivityHandler = { date, projectId, taskId, desc, seconds, tag in
            TestFactories.makeActivity(
                id: 10, date: date,
                projectId: projectId, projectName: "Test Project",
                taskId: taskId, taskName: "Test Task",
                seconds: seconds, description: desc, tag: tag ?? "",
                timerStartedAt: "2025-01-01T10:00:00Z"
            )
        }
        api.startTimerHandler = { activityId in
            TestFactories.makeActivity(
                id: activityId,
                timerStartedAt: "2025-01-01T10:00:00Z"
            )
        }
        api.stopTimerHandler = { activityId in
            TestFactories.makeActivity(id: activityId, timerStartedAt: nil)
        }
        return api
    }

    @Test("A sync fetched before start cannot clear the new timer or its activities")
    @MainActor func staleSyncCannotOverwriteStart() async {
        let response = TimerResponseLatch()
        var fetchCount = 0
        var api = makeStartableAPI()
        api.fetchActivitiesHandler = { _, _, _ in
            fetchCount += 1
            if fetchCount == 1 { return await response.receive() }
            return []
        }
        let activities = ActivityService(clientFactory: { nil }, notificationDispatcher: NotificationDispatcher { _ in false })
        let timer = TimerService(clientFactory: { api }, userIdProvider: { 42 }, activitySync: activities)
        let sync = Task { await timer.sync() }
        await response.waitUntilRequested()
        let result = await timer.startTimer(projectId: 100, taskId: 200, description: "new work")
        guard case .success = result else { Issue.record("Start failed"); return }
        let version = activities.todayMutationVersion
        await response.resolve([])
        await sync.value
        #expect(timer.activeActivityId == 10)
        #expect(timer.currentActivity?.description == "new work")
        #expect(activities.todayActivities.map(\.id) == [10])
        #expect(activities.todayMutationVersion == version)
    }

    @Test("A sync fetched before pause cannot resurrect the running timer")
    @MainActor func staleSyncCannotUndoPause() async {
        let response = TimerResponseLatch()
        var api = makeStartableAPI()
        var holdFetch = false
        api.fetchActivitiesHandler = { _, _, _ in
            if holdFetch { return await response.receive() }
            return []
        }
        let (timer, _) = makeService(api: api)
        _ = await timer.startTimer(projectId: 100, taskId: 200, description: "work")
        holdFetch = true
        let sync = Task { await timer.sync() }
        await response.waitUntilRequested()
        await timer.pauseTimer()
        await response.resolve([TestFactories.makeActivity(id: 10, timerStartedAt: "2026-01-01T10:00:00Z")])
        await sync.value
        #expect(timer.timerState == .paused(activityId: 10, projectName: "Test Project"))
        #expect(timer.currentActivity?.isTimerRunning == false)
    }

    @Test("An older sync cannot overwrite a newer completed sync")
    @MainActor func olderSyncCannotOverwriteNewerSync() async {
        let response = TimerResponseLatch()
        var api = MockTimerAPI()
        var fetchCount = 0
        api.fetchActivitiesHandler = { _, _, _ in
            fetchCount += 1
            if fetchCount == 1 { return await response.receive() }
            return [TestFactories.makeActivity(id: 20, timerStartedAt: "2026-01-01T10:00:00Z")]
        }
        let (timer, _) = makeService(api: api)
        let older = Task { await timer.sync() }
        await response.waitUntilRequested()
        await timer.sync()
        await response.resolve([])
        await older.value
        #expect(timer.activeActivityId == 20)
    }

    @Test("Failed explicit stop retains the running timer and emits only an error")
    @MainActor func failedStopPreservesTimer() async {
        var api = makeStartableAPI()
        api.stopTimerHandler = { _ in throw MocoError.serverError(statusCode: 503, message: "unavailable") }
        let (timer, _) = makeService(api: api)
        _ = await timer.startTimer(projectId: 100, taskId: 200, description: "work")
        var errors = 0
        var stops = 0
        timer.onEvent = { event in
            if case .error = event { errors += 1 }
            if case .stopped = event { stops += 1 }
        }
        await timer.stopTimer()
        #expect(timer.timerState == .running(activityId: 10, projectName: "Test Project"))
        #expect(timer.currentActivity?.id == 10)
        #expect(timer.lastError != nil)
        #expect(errors == 1 && stops == 0)
    }

    @Test("Failed quiet stop prevents replacement create and continue")
    @MainActor func failedQuietStopPreventsReplacement() async {
        var api = makeStartableAPI()
        var creates = 0
        let create = api.createActivityHandler
        api.createActivityHandler = { date, project, task, description, seconds, tag in
            creates += 1
            return try await create(date, project, task, description, seconds, tag)
        }
        var starts = 0
        api.startTimerHandler = { id in
            starts += 1
            return TestFactories.makeActivity(id: id, timerStartedAt: "2026-01-01T10:00:00Z")
        }
        api.stopTimerHandler = { _ in throw MocoError.networkError(URLError(.notConnectedToInternet)) }
        let (timer, _) = makeService(api: api)
        _ = await timer.startTimer(projectId: 100, taskId: 200, description: "first")
        let result = await timer.startTimer(projectId: 101, taskId: 201, description: "replacement")
        if case .success = result { Issue.record("Replacement must fail when stop fails") }
        await timer.toggleTimer(for: 20, projectName: "Other")
        #expect(creates == 1 && starts == 0)
        #expect(timer.activeActivityId == 10)
        #expect(timer.currentActivity?.description == "first")
    }

    @Test("Failed stop of an external timer keeps it visible and prevents create")
    @MainActor func failedExternalStopPreventsCreate() async {
        var api = makeStartableAPI()
        api.fetchActivitiesHandler = { _, _, _ in
            [TestFactories.makeActivity(id: 99, timerStartedAt: "2026-01-01T10:00:00Z")]
        }
        api.stopTimerHandler = { _ in throw MocoError.serverError(statusCode: 503, message: "unavailable") }
        api.createActivityHandler = { _, _, _, _, _, _ in
            Issue.record("Must not create after failed external stop")
            throw MocoError.invalidConfiguration
        }
        let (timer, _) = makeService(api: api)
        let result = await timer.startTimer(projectId: 100, taskId: 200, description: "replacement")
        if case .success = result { Issue.record("Expected stop failure") }
        #expect(timer.activeActivityId == 99)
        #expect(timer.currentActivity?.isTimerRunning == true)
    }

    @Test("Deleting a paused timer clears it without another server stop")
    @MainActor func stopPausedActivityClearsLocally() async {
        var api = makeStartableAPI()
        var stops = 0
        api.stopTimerHandler = { id in
            stops += 1
            return TestFactories.makeActivity(id: id)
        }
        let (timer, _) = makeService(api: api)
        _ = await timer.startTimer(projectId: 100, taskId: 200, description: "work")
        await timer.pauseTimer()
        await timer.stopTimerIfActive(activityId: 99)
        #expect(timer.activeActivityId == 10)
        await timer.stopTimerIfActive(activityId: 10)
        #expect(timer.timerState == .idle)
        #expect(timer.currentActivity == nil)
        #expect(stops == 1)
        await timer.handleEmptySubmit()
        #expect(timer.timerState == .idle)
    }

    @Test("Starting another timer waits for an in-flight pause")
    @MainActor func timerMutationsAreSerialized() async {
        let stopResponse = TimerResponseLatch()
        var api = makeStartableAPI()
        api.stopTimerHandler = { id in
            let response = await stopResponse.receive()
            return response[0]
        }
        let (timer, _) = makeService(api: api)
        _ = await timer.startTimer(projectId: 100, taskId: 200, description: "first")
        let pause = Task { await timer.pauseTimer() }
        await stopResponse.waitUntilRequested()
        let start = Task { await timer.startTimer(projectId: 101, taskId: 201, description: "second") }
        await stopResponse.resolve([TestFactories.makeActivity(id: 10)])
        await pause.value
        _ = await start.value
        #expect(timer.timerState == .running(activityId: 10, projectName: "Test Project"))
        #expect(timer.currentActivity?.description == "second")
    }

    // MARK: - Start Timer

    @Test("startTimer transitions to running on success")
    @MainActor func startTimerSuccess() async {
        let api = makeStartableAPI()
        let (service, _) = makeService(api: api)

        let result = await service.startTimer(projectId: 100, taskId: 200, description: "work")
        switch result {
        case .success(let activity):
            #expect(activity.id == 10)
        case .failure(let error):
            Issue.record("Expected success, got \(error)")
        }

        #expect(service.timerState == TimerState.running(activityId: 10, projectName: "Test Project"))
        #expect(service.lastError == nil)
    }

    @Test("startTimer when already running stops current then starts new")
    @MainActor func startTimerWhileRunning() async {
        var api = makeStartableAPI()
        var stopCalledWith: [Int] = []
        api.stopTimerHandler = { activityId in
            stopCalledWith.append(activityId)
            return TestFactories.makeActivity(id: activityId, timerStartedAt: nil)
        }
        let (service, _) = makeService(api: api)

        // Start first timer
        _ = await service.startTimer(projectId: 100, taskId: 200, description: "first")
        #expect(service.timerState == TimerState.running(activityId: 10, projectName: "Test Project"))

        // Start second timer — should stop the first
        _ = await service.startTimer(projectId: 101, taskId: 201, description: "second")

        // Stop should have been called for the first timer
        #expect(stopCalledWith.contains(10))
    }

    @Test("startTimer API failure returns .failure and sets lastError")
    @MainActor func startTimerFailure() async {
        var api = MockTimerAPI()
        api.createActivityHandler = { _, _, _, _, _, _ in
            throw MocoError.serverError(statusCode: 500, message: "Internal Server Error")
        }
        let (service, _) = makeService(api: api)

        let result = await service.startTimer(projectId: 100, taskId: 200, description: "work")
        switch result {
        case .success:
            Issue.record("Expected failure")
        case .failure:
            break // expected
        }

        #expect(service.lastError != nil)
    }

    @Test("startTimer with nil client returns .failure(.invalidConfiguration)")
    @MainActor func startTimerNoClient() async {
        let service = TimerService(
            clientFactory: { nil as (any TimerAPI)? },
            userIdProvider: { 42 }
        )

        let result = await service.startTimer(projectId: 1, taskId: 2, description: "x")
        if case .failure(let error) = result {
            switch error {
            case .invalidConfiguration: break // expected
            default: Issue.record("Expected .invalidConfiguration, got \(error)")
            }
        } else {
            Issue.record("Expected failure")
        }
    }

    // MARK: - Pause Timer

    @Test("pauseTimer transitions from running to paused")
    @MainActor func pauseTimerSuccess() async {
        let api = makeStartableAPI()
        let (service, _) = makeService(api: api)

        _ = await service.startTimer(projectId: 100, taskId: 200, description: "work")
        #expect(service.timerState == TimerState.running(activityId: 10, projectName: "Test Project"))

        await service.pauseTimer()
        #expect(service.timerState == TimerState.paused(activityId: 10, projectName: "Test Project"))
    }

    @Test("pauseTimer when idle does nothing")
    @MainActor func pauseTimerWhenIdle() async {
        let (service, _) = makeService()
        await service.pauseTimer()
        #expect(service.timerState == TimerState.idle)
    }

    // MARK: - Resume Timer

    @Test("resumeTimer transitions from paused to running")
    @MainActor func resumeTimerSuccess() async {
        let api = makeStartableAPI()
        let (service, _) = makeService(api: api)

        _ = await service.startTimer(projectId: 100, taskId: 200, description: "work")
        await service.pauseTimer()
        #expect(service.timerState == TimerState.paused(activityId: 10, projectName: "Test Project"))

        await service.resumeTimer()
        #expect(service.timerState == TimerState.running(activityId: 10, projectName: "Test Project"))
    }

    @Test("resumeTimer when idle does nothing")
    @MainActor func resumeTimerWhenIdle() async {
        let (service, _) = makeService()
        await service.resumeTimer()
        #expect(service.timerState == TimerState.idle)
    }

    // MARK: - Stop Timer

    @Test("stopTimer transitions to idle")
    @MainActor func stopTimerSuccess() async {
        let api = makeStartableAPI()
        let (service, _) = makeService(api: api)

        _ = await service.startTimer(projectId: 100, taskId: 200, description: "work")
        await service.stopTimer()
        #expect(service.timerState == TimerState.idle)
        #expect(service.currentActivity == nil)
    }

    // MARK: - Sync

    @Test("sync detects externally running timer")
    @MainActor func syncDetectsRunning() async {
        var api = MockTimerAPI()
        let runningActivity = TestFactories.makeActivity(
            id: 55, projectName: "External Project",
            timerStartedAt: "2025-01-01T12:00:00Z"
        )
        api.fetchActivitiesHandler = { _, _, _ in [runningActivity] }
        let (service, _) = makeService(api: api)

        #expect(service.timerState == TimerState.idle)
        await service.sync()
        #expect(service.timerState == TimerState.running(activityId: 55, projectName: "External Project"))
    }

    @Test("sync detects externally stopped timer")
    @MainActor func syncDetectsStopped() async {
        // Use a class wrapper so the closure captures a mutable reference
        var syncAPI = MockTimerAPI()
        syncAPI.createActivityHandler = { date, projectId, taskId, desc, seconds, tag in
            TestFactories.makeActivity(
                id: 10, projectId: projectId, projectName: "Test Project",
                taskId: taskId, timerStartedAt: "2025-01-01T10:00:00Z"
            )
        }
        syncAPI.stopTimerHandler = { id in
            TestFactories.makeActivity(id: id, timerStartedAt: nil)
        }
        // fetchActivities always returns no running timers
        syncAPI.fetchActivitiesHandler = { _, _, _ in
            [TestFactories.makeActivity(id: 10, timerStartedAt: nil)]
        }
        let service = TimerService(
            clientFactory: { syncAPI },
            userIdProvider: { 42 }
        )

        _ = await service.startTimer(projectId: 100, taskId: 200, description: "work")
        #expect(service.timerState == TimerState.running(activityId: 10, projectName: "Test Project"))

        await service.sync()
        #expect(service.timerState == TimerState.idle)
    }

    // MARK: - Toggle Timer

    @Test("toggleTimer for running activity pauses it")
    @MainActor func toggleRunningPauses() async {
        let api = makeStartableAPI()
        let (service, _) = makeService(api: api)

        _ = await service.startTimer(projectId: 100, taskId: 200, description: "work")
        #expect(service.timerState == TimerState.running(activityId: 10, projectName: "Test Project"))

        await service.toggleTimer(for: 10, projectName: "Test Project")
        #expect(service.timerState == TimerState.paused(activityId: 10, projectName: "Test Project"))
    }

    @Test("toggleTimer for paused activity resumes it")
    @MainActor func togglePausedResumes() async {
        let api = makeStartableAPI()
        let (service, _) = makeService(api: api)

        _ = await service.startTimer(projectId: 100, taskId: 200, description: "work")
        await service.pauseTimer()
        #expect(service.timerState == TimerState.paused(activityId: 10, projectName: "Test Project"))

        await service.toggleTimer(for: 10, projectName: "Test Project")
        #expect(service.timerState == TimerState.running(activityId: 10, projectName: "Test Project"))
    }

    // MARK: - Continue Timer (via toggleTimer for different activity)

    @Test("toggleTimer for idle activity continues it (stops running + starts new)")
    @MainActor func continueTimerViaToggle() async {
        var api = makeStartableAPI()
        var stopCalledWith: [Int] = []
        api.stopTimerHandler = { activityId in
            stopCalledWith.append(activityId)
            return TestFactories.makeActivity(id: activityId, timerStartedAt: nil)
        }
        // startTimer for the continued activity returns activity 20
        api.startTimerHandler = { activityId in
            TestFactories.makeActivity(
                id: activityId, projectName: "Other Project",
                timerStartedAt: "2025-01-01T11:00:00Z"
            )
        }
        let (service, _) = makeService(api: api)

        // Start first timer
        _ = await service.startTimer(projectId: 100, taskId: 200, description: "first")
        #expect(service.timerState == TimerState.running(activityId: 10, projectName: "Test Project"))

        // Toggle a different activity ID → should stop current + continue on activity 20
        await service.toggleTimer(for: 20, projectName: "Other Project")

        #expect(stopCalledWith.contains(10), "Original timer should have been stopped")
        #expect(service.timerState == TimerState.running(activityId: 20, projectName: "Other Project"))
    }

    // MARK: - handleEmptySubmit

    @Test("handleEmptySubmit running → pause")
    @MainActor func handleEmptySubmitRunning() async {
        let api = makeStartableAPI()
        let (service, _) = makeService(api: api)

        _ = await service.startTimer(projectId: 100, taskId: 200, description: "work")
        #expect(service.timerState == TimerState.running(activityId: 10, projectName: "Test Project"))

        await service.handleEmptySubmit()
        #expect(service.timerState == TimerState.paused(activityId: 10, projectName: "Test Project"))
    }

    @Test("handleEmptySubmit paused → resume")
    @MainActor func handleEmptySubmitPaused() async {
        let api = makeStartableAPI()
        let (service, _) = makeService(api: api)

        _ = await service.startTimer(projectId: 100, taskId: 200, description: "work")
        await service.pauseTimer()
        #expect(service.timerState == TimerState.paused(activityId: 10, projectName: "Test Project"))

        await service.handleEmptySubmit()
        #expect(service.timerState == TimerState.running(activityId: 10, projectName: "Test Project"))
    }

    @Test("handleEmptySubmit idle → no-op")
    @MainActor func handleEmptySubmitIdle() async {
        let (service, _) = makeService()

        await service.handleEmptySubmit()
        #expect(service.timerState == TimerState.idle)
    }
}

/// Explicit request/response rendezvous: race tests do not rely on sleeps.
private actor TimerResponseLatch {
    private var requested = false
    private var requestWaiters: [CheckedContinuation<Void, Never>] = []
    private var response: CheckedContinuation<[MocoActivity], Never>?

    func receive() async -> [MocoActivity] {
        requested = true
        for waiter in requestWaiters { waiter.resume() }
        requestWaiters.removeAll()
        return await withCheckedContinuation { response = $0 }
    }

    func waitUntilRequested() async {
        if requested { return }
        await withCheckedContinuation { requestWaiters.append($0) }
    }

    func resolve(_ activities: [MocoActivity]) {
        response?.resume(returning: activities)
        response = nil
    }
}
