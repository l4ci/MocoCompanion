import Foundation
import os

/// Syncs timer state changes to the activity list.
/// ActivityService conforms; TimerService depends on the protocol.
@MainActor
protocol ActivitySyncing: AnyObject {
    /// Mirror a server response into the canonical activity arrays,
    /// preserving local-only origin metadata from any prior local row.
    /// `MocoActivity` (not `ShadowEntry`) is the input so callers can't
    /// accidentally pass a zero-origin row. Returns the merged shadow so
    /// the caller can also update its own in-memory state with the same
    /// row (e.g., `TimerService.currentActivity`).
    @discardableResult
    func upsertActivity(fromServer activity: MocoActivity) -> ShadowEntry
    func reconcileTimerSnapshot(_ activities: [MocoActivity], forDate date: String) async throws -> [ShadowEntry]
    func applyFetchedTodayActivities(_ activities: [ShadowEntry])
    func refreshTodayStats() async
}

/// Owns the timer lifecycle: start, pause, resume, stop, continue, toggle.
/// Pure timer state machine — activity CRUD is delegated to ActivityService.
///
/// The `suppressNextStopNotification` flag is eliminated: `stopRunningTimerQuietly`
/// calls the API without triggering user-facing side effects, used only during
/// the internal stop-then-start sequence.
@Observable
@MainActor
final class TimerService: TimerStopProvider {
    private let logger = Logger(category: "TimerService")

    // MARK: - Observable State

    private(set) var timerState: TimerState = .idle
    private(set) var currentActivity: ShadowEntry?
    var lastError: MocoError?

    /// The ID of the currently running or paused activity, or nil if idle.
    var activeActivityId: Int? {
        switch timerState {
        case .idle: nil
        case .running(let id, _): id
        case .paused(let id, _): id
        }
    }

    // MARK: - Events

    /// Discrete events emitted after timer state transitions.
    enum Event: Sendable {
        case started(projectId: Int, taskId: Int, description: String, projectName: String)
        case paused(projectName: String)
        case resumed(projectName: String)
        case stopped
        case continued(projectId: Int, taskId: Int, projectName: String)
        case externalTimerStopped
        case pausedTimerReplaced(previousProjectName: String)
        case error(MocoError)
    }

    /// Event handler — set by the composition root to wire side effects.
    var onEvent: ((Event) -> Void)?

    // MARK: - Dependencies

    private let clientFactory: () -> (any TimerAPI)?
    private let userIdProvider: () -> Int?
    private weak var activitySync: (any ActivitySyncing)?

    // Network awaits make MainActor methods reentrant. Mutations and snapshot
    // publication share this queue; background fetches do not hold it.
    @ObservationIgnored private var operationInProgress = false
    @ObservationIgnored private var operationWaiters: [CheckedContinuation<Void, Never>] = []
    @ObservationIgnored private var mutationGeneration: UInt64 = 0
    @ObservationIgnored private var syncSequence: UInt64 = 0

    private func acquireOperation() async {
        if operationInProgress {
            await withCheckedContinuation { operationWaiters.append($0) }
        } else {
            operationInProgress = true
        }
    }

    private func releaseOperation() {
        if operationWaiters.isEmpty {
            operationInProgress = false
        } else {
            operationWaiters.removeFirst().resume()
        }
    }

    private func beginMutation() async {
        await acquireOperation()
        mutationGeneration &+= 1
    }

    private func endMutation() {
        mutationGeneration &+= 1
        releaseOperation()
    }

    init(
        clientFactory: @escaping () -> (any TimerAPI)?,
        userIdProvider: @escaping () -> Int? = { nil },
        activitySync: (any ActivitySyncing)? = nil
    ) {
        self.clientFactory = clientFactory
        self.userIdProvider = userIdProvider
        self.activitySync = activitySync
    }

    // MARK: - Public API

    /// Start a new timer for a project+task. Stops any running timer first.
    func startTimer(projectId: Int, taskId: Int, description: String) async -> Result<ShadowEntry, MocoError> {
        await beginMutation()
        defer { endMutation() }
        guard let client = clientFactory() else {
            let error = MocoError.invalidConfiguration
            lastError = error
            logger.warning("Cannot start timer — API not configured")
            return .failure(error)
        }

        let tag = TagExtractor.extract(from: description)
        logger.info("startTimer: projectId=\(projectId) taskId=\(taskId) tag=\(tag ?? "nil")")

        // Stop any running timer quietly — no user-facing stop notification
        do {
            try await stopRunningTimerQuietly(client: client)
        } catch {
            handleError(error, label: "stop before start")
            return .failure(MocoError.from(error))
        }

        let today = DateUtilities.todayString()

        do {
            let apiDescription = TagExtractor.stripTags(from: description)
            let created = try await client.createActivity(
                date: today, projectId: projectId, taskId: taskId,
                description: apiDescription, seconds: 0, tag: tag
            )
            logger.info("Created activity id=\(created.id) project=\(created.project.name)")

            var apiActivity = created
            if !created.isTimerRunning {
                apiActivity = try await client.startTimer(activityId: created.id)
                logger.info("Timer started via explicit startTimer call")
            } else {
                logger.info("Timer already running after createActivity — skipping startTimer")
            }

            // Brand-new create: no prior local row to merge from. The
            // upsertActivity(fromServer:) path internally falls back to
            // `from()` when no local row exists, so origin stays zeroed —
            // which is correct here.
            let activity = activitySync?.upsertActivity(fromServer: apiActivity)
                ?? ShadowEntry.from(apiActivity)
            currentActivity = activity
            timerState = .running(activityId: apiActivity.id, projectName: activity.projectName)
            BreadcrumbTrail.shared.record("TimerService", "Timer started: projectId=\(projectId) taskId=\(taskId)")
            lastError = nil

            onEvent?(.started(projectId: projectId, taskId: taskId, description: description, projectName: activity.projectName))

            return .success(activity)
        } catch {
            handleError(error, label: "startTimer")
            await recoverTimerState(client: client)
            return .failure(MocoError.from(error))
        }
    }

    /// Context-aware toggle: running → pause, paused → resume, idle entry → continue.
    func toggleTimer(for activityId: Int, projectName: String) async {
        switch timerState {
        case .running(let runningId, _) where runningId == activityId:
            await pauseTimer()
        case .paused(let pausedId, _) where pausedId == activityId:
            await resumeTimer()
        default:
            await continueTimer(activityId: activityId, projectName: projectName)
        }
    }

    /// Pause the currently running timer.
    func pauseTimer() async {
        await beginMutation()
        defer { endMutation() }
        guard let client = clientFactory() else { return }
        guard case .running(let activityId, let projectName) = timerState else {
            logger.info("pauseTimer: no running timer to pause")
            return
        }

        do {
            let stopped = try await client.stopTimer(activityId: activityId)
            timerState = .paused(activityId: activityId, projectName: projectName)
            logger.info("Timer paused: activityId=\(activityId) project=\(projectName)")
            BreadcrumbTrail.shared.record("TimerService", "Timer paused: activityId=\(activityId)")
            onEvent?(.paused(projectName: projectName))
            currentActivity = activitySync?.upsertActivity(fromServer: stopped) ?? ShadowEntry.from(stopped)
        } catch {
            handleError(error, label: "pauseTimer")
        }
    }

    /// Resume the currently paused timer.
    func resumeTimer() async {
        await beginMutation()
        defer { endMutation() }
        guard let client = clientFactory() else { return }
        guard case .paused(let activityId, let projectName) = timerState else {
            logger.info("resumeTimer: no paused timer to resume")
            return
        }

        do {
            let startedApi = try await client.startTimer(activityId: activityId)
            let started = activitySync?.upsertActivity(fromServer: startedApi)
                ?? ShadowEntry.from(startedApi)
            currentActivity = started
            timerState = .running(activityId: activityId, projectName: projectName)
            logger.info("Timer resumed: activityId=\(activityId) project=\(projectName)")
            BreadcrumbTrail.shared.record("TimerService", "Timer resumed: activityId=\(activityId)")
            onEvent?(.resumed(projectName: projectName))
        } catch {
            handleError(error, label: "resumeTimer")
        }
    }

    /// Toggle the timer based on current state (used for empty-submit).
    func handleEmptySubmit() async {
        switch timerState {
        case .running:
            await pauseTimer()
        case .paused:
            await resumeTimer()
        case .idle:
            logger.info("handleEmptySubmit: no timer to toggle")
        }
    }

    /// Stop the currently running timer completely.
    func stopTimer() async {
        await beginMutation()
        defer { endMutation() }
        guard let client = clientFactory() else { return }
        guard case .running(let activityId, let projectName) = timerState else { return }

        do {
            let stopped = try await client.stopTimer(activityId: activityId)
            activitySync?.upsertActivity(fromServer: stopped)
            clearTimerStateIfTracking(activityId)
            lastError = nil
            logger.info("Timer stopped: activityId=\(activityId) project=\(projectName)")
            BreadcrumbTrail.shared.record("TimerService", "Timer stopped: activityId=\(activityId)")
            onEvent?(.stopped)
        } catch {
            handleError(error, label: "stopTimer")
        }

    }

    /// Sync timer state from the server.
    func sync() async {
        guard !operationInProgress, let client = clientFactory(),
              let userId = userIdProvider() else { return }
        let generation = mutationGeneration
        syncSequence &+= 1
        let sequence = syncSequence
        let today = DateUtilities.todayString()
        BreadcrumbTrail.shared.record("TimerService", "Sync requested")
        do {
            let activities = try await client.fetchActivities(from: today, to: today, userId: userId)
            await acquireOperation()
            defer { releaseOperation() }
            guard generation == mutationGeneration, sequence == syncSequence,
                  today == DateUtilities.todayString(), !Task.isCancelled else { return }
            // Hold the queue through store reconciliation and publication. A timer
            // mutation cannot start halfway through applying this snapshot.
            try await applyTimerSnapshot(activities, forDate: today)
        } catch {
            logger.error("Timer sync failed: \(error.localizedDescription)")
        }
    }

    /// Stop the timer if it is currently running or paused for the given activity.
    func stopTimerIfActive(activityId: Int) async {
        await beginMutation()
        defer { endMutation() }
        switch timerState {
        case .paused(let id, _) where id == activityId:
            clearTimerState()
        case .running(let id, _) where id == activityId:
            guard let client = clientFactory() else { return }
            do {
                let stopped = try await client.stopTimer(activityId: id)
                activitySync?.upsertActivity(fromServer: stopped)
                clearTimerStateIfTracking(id)
                lastError = nil
                onEvent?(.stopped)
            } catch {
                handleError(error, label: "stopTimerIfActive")
            }
        default: break
        }
    }

    /// Whether an entry is the currently paused timer.
    func isPausedActivity(_ entry: ShadowEntry) -> Bool {
        if case .paused(let id, _) = timerState { return entry.id == id }
        return false
    }

    // MARK: - Private

    private func clearTimerState() {
        currentActivity = nil
        timerState = .idle
    }

    private func clearTimerStateIfTracking(_ activityId: Int) {
        switch timerState {
        case .running(let id, _) where id == activityId: clearTimerState()
        case .paused(let id, _) where id == activityId: clearTimerState()
        default: break
        }
    }

    private func continueTimer(activityId: Int, projectName: String) async {
        await beginMutation()
        defer { endMutation() }
        guard let client = clientFactory() else { return }

        // Stop any running timer quietly — no user-facing stop notification
        do {
            try await stopRunningTimerQuietly(client: client)
        } catch {
            handleError(error, label: "stop before continue")
            return
        }

        do {
            let startedApi = try await client.startTimer(activityId: activityId)
            let started = activitySync?.upsertActivity(fromServer: startedApi)
                ?? ShadowEntry.from(startedApi)
            currentActivity = started
            timerState = .running(activityId: startedApi.id, projectName: projectName)
            lastError = nil
            logger.info("Continued timer on activityId=\(activityId) project=\(projectName)")
            BreadcrumbTrail.shared.record("TimerService", "Timer continued: activityId=\(activityId)")
            onEvent?(.continued(projectId: started.projectId, taskId: started.taskId, projectName: projectName))
        } catch {
            handleError(error, label: "continueTimer")
            await recoverTimerState(client: client)
        }
    }

    /// Stop any running timer without firing user-facing side effects.
    /// Used during the internal stop-then-start sequence (startTimer, continueTimer).
    /// This eliminates the old `suppressNextStopNotification` flag.
    private func stopRunningTimerQuietly(client: any TimerAPI) async throws {
        if case .running(let activityId, _) = timerState {
            let stopped = try await client.stopTimer(activityId: activityId)
            activitySync?.upsertActivity(fromServer: stopped)
            clearTimerStateIfTracking(activityId)
            return
        }

        guard let userId = userIdProvider() else {
            throw MocoError.invalidConfiguration
        }
        let today = DateUtilities.todayString()
        let activities = try await client.fetchActivities(from: today, to: today, userId: userId)
        if let running = activities.first(where: { $0.isTimerRunning }) {
            // Keep the discovered running timer visible if stopping it fails.
            currentActivity = activitySync?.upsertActivity(fromServer: running) ?? ShadowEntry.from(running)
            timerState = .running(activityId: running.id, projectName: running.project.name)
            let stopped = try await client.stopTimer(activityId: running.id)
            activitySync?.upsertActivity(fromServer: stopped)
            clearTimerStateIfTracking(running.id)
            onEvent?(.externalTimerStopped)
        }
    }

    /// Called only while holding the operation queue.
    private func recoverTimerState(client: any TimerAPI) async {
        guard let userId = userIdProvider() else { return }
        let today = DateUtilities.todayString()
        do {
            let activities = try await client.fetchActivities(from: today, to: today, userId: userId)
            try await applyTimerSnapshot(activities, forDate: today)
        } catch {
            logger.error("Timer recovery failed: \(error.localizedDescription)")
        }
    }

    private func applyTimerSnapshot(_ activities: [MocoActivity], forDate date: String) async throws {
        let entries: [ShadowEntry]
        if let activitySync {
            entries = try await activitySync.reconcileTimerSnapshot(activities, forDate: date)
        } else {
            entries = activities.map { ShadowEntry.from($0) }
        }
        guard date == DateUtilities.todayString() else { return }
        activitySync?.applyFetchedTodayActivities(entries)
        if let runningApi = activities.first(where: { $0.isTimerRunning }) {
            if case .paused(let pausedId, let pausedProject) = timerState, pausedId != runningApi.id {
                onEvent?(.pausedTimerReplaced(previousProjectName: pausedProject))
            }
            currentActivity = entries.first { $0.id == runningApi.id } ?? ShadowEntry.from(runningApi)
            timerState = .running(activityId: runningApi.id, projectName: runningApi.project.name)
        } else if case .running = timerState {
            clearTimerState()
        }
    }

    private func handleError(_ error: any Error, label: String) {
        BreadcrumbTrail.shared.record("TimerService", "Error: \(label) — \(error.localizedDescription)")
        let mocoError = MocoError.from(error)
        lastError = mocoError
        onEvent?(.error(mocoError))
        logger.error("\(label) failed: \(error.localizedDescription)")
        Task { await AppLogger.shared.app("\(label) failed: \(error.localizedDescription)", level: .error, context: "TimerService") }
    }
}
