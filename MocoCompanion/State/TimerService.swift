import Foundation
import os

/// Syncs timer state changes to the activity list.
/// ActivityService conforms; TimerService depends on the protocol.
@MainActor
protocol ActivitySyncing: AnyObject {
    func upsertActivity(_ activity: ShadowEntry)
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
        guard let client = clientFactory() else {
            let error = MocoError.invalidConfiguration
            lastError = error
            logger.warning("Cannot start timer — API not configured")
            return .failure(error)
        }

        let tag = TagExtractor.extract(from: description)
        logger.info("startTimer: projectId=\(projectId) taskId=\(taskId) tag=\(tag ?? "nil")")

        // Stop any running timer quietly — no user-facing stop notification
        await stopRunningTimerQuietly(client: client)

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

            let activity = ShadowEntry.from(apiActivity)
            currentActivity = activity
            timerState = .running(activityId: apiActivity.id, projectName: activity.projectName)
            BreadcrumbTrail.shared.record("TimerService", "Timer started: projectId=\(projectId) taskId=\(taskId)")
            lastError = nil

            activitySync?.upsertActivity(activity)
            onEvent?(.started(projectId: projectId, taskId: taskId, description: description, projectName: activity.projectName))

            return .success(activity)
        } catch {
            handleError(error, label: "startTimer")
            await sync()
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
            activitySync?.upsertActivity(ShadowEntry.from(stopped))
        } catch {
            handleError(error, label: "pauseTimer")
        }
    }

    /// Resume the currently paused timer.
    func resumeTimer() async {
        guard let client = clientFactory() else { return }
        guard case .paused(let activityId, let projectName) = timerState else {
            logger.info("resumeTimer: no paused timer to resume")
            return
        }

        do {
            let startedApi = try await client.startTimer(activityId: activityId)
            let started = ShadowEntry.from(startedApi)
            currentActivity = started
            timerState = .running(activityId: activityId, projectName: projectName)
            logger.info("Timer resumed: activityId=\(activityId) project=\(projectName)")
            BreadcrumbTrail.shared.record("TimerService", "Timer resumed: activityId=\(activityId)")
            onEvent?(.resumed(projectName: projectName))
            activitySync?.upsertActivity(started)
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
        guard let client = clientFactory() else { return }
        guard case .running(let activityId, let projectName) = timerState else { return }

        do {
            _ = try await client.stopTimer(activityId: activityId)
            logger.info("Timer stopped: activityId=\(activityId) project=\(projectName)")
            BreadcrumbTrail.shared.record("TimerService", "Timer stopped: activityId=\(activityId)")
            onEvent?(.stopped)
        } catch {
            handleError(error, label: "stopTimer")
        }

        clearTimerState()
    }

    /// Sync timer state from the server.
    func sync() async {
        BreadcrumbTrail.shared.record("TimerService", "Sync requested")
        let activities = await syncCurrentTimer()
        // Push fetched activities to activity service
        if let activities {
            activitySync?.applyFetchedTodayActivities(activities)
        } else {
            await activitySync?.refreshTodayStats()
        }
    }

    /// Stop the timer if it is currently running or paused for the given activity.
    func stopTimerIfActive(activityId: Int) async {
        switch timerState {
        case .running(let id, _) where id == activityId,
             .paused(let id, _) where id == activityId:
            await stopTimer()
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
        guard let client = clientFactory() else { return }

        // Stop any running timer quietly — no user-facing stop notification
        await stopRunningTimerQuietly(client: client)

        do {
            let startedApi = try await client.startTimer(activityId: activityId)
            let started = ShadowEntry.from(startedApi)
            currentActivity = started
            timerState = .running(activityId: startedApi.id, projectName: projectName)
            lastError = nil
            logger.info("Continued timer on activityId=\(activityId) project=\(projectName)")
            BreadcrumbTrail.shared.record("TimerService", "Timer continued: activityId=\(activityId)")
            onEvent?(.continued(projectId: started.projectId, taskId: started.taskId, projectName: projectName))
            activitySync?.upsertActivity(started)
        } catch {
            handleError(error, label: "continueTimer")
            _ = await syncCurrentTimer()
        }
    }

    /// Stop any running timer without firing user-facing side effects.
    /// Used during the internal stop-then-start sequence (startTimer, continueTimer).
    /// This eliminates the old `suppressNextStopNotification` flag.
    private func stopRunningTimerQuietly(client: any TimerAPI) async {
        if case .running(let activityId, _) = timerState {
            do {
                let stopped = try await client.stopTimer(activityId: activityId)
                activitySync?.upsertActivity(ShadowEntry.from(stopped))
                logger.info("Quietly stopped running timer: activityId=\(activityId)")
            } catch {
                logger.error("stopRunningTimerQuietly failed: \(error.localizedDescription)")
            }
            clearTimerState()
            return
        }

        // Check server for externally running timers
        guard let userId = userIdProvider() else {
            logger.warning("stopRunningTimerQuietly skipped server check — userId not available")
            return
        }

        let today = DateUtilities.todayString()
        do {
            let activities = try await client.fetchActivities(from: today, to: today, userId: userId)
            if let running = activities.first(where: { $0.isTimerRunning }) {
                logger.info("Found externally running timer: activityId=\(running.id) — stopping it")
                _ = try await client.stopTimer(activityId: running.id)
                onEvent?(.externalTimerStopped)
            }
        } catch {
            logger.error("stopRunningTimerQuietly server check failed: \(error.localizedDescription)")
        }
    }

    private func syncCurrentTimer() async -> [ShadowEntry]? {
        guard let client = clientFactory() else { return nil }
        guard let userId = userIdProvider() else {
            logger.warning("syncCurrentTimer skipped — userId not available yet")
            return nil
        }
        let today = DateUtilities.todayString()

        do {
            let apiActivities = try await client.fetchActivities(from: today, to: today, userId: userId)
            let entries = apiActivities.map { ShadowEntry.from($0) }
            if let runningApi = apiActivities.first(where: { $0.isTimerRunning }) {
                let running = ShadowEntry.from(runningApi)
                if case .running(let currentId, _) = timerState, currentId == runningApi.id { return entries }
                if case .paused(let pausedId, let pausedProject) = timerState, pausedId != runningApi.id {
                    BreadcrumbTrail.shared.record("TimerService", "Paused timer \(pausedId) (\(pausedProject)) replaced by external timer \(runningApi.id)")
                    onEvent?(.pausedTimerReplaced(previousProjectName: pausedProject))
                }
                currentActivity = running
                timerState = .running(activityId: runningApi.id, projectName: running.projectName)
                logger.info("Synced running timer: activityId=\(runningApi.id) project=\(running.projectName)")
            } else if case .running = timerState {
                clearTimerState()
                logger.info("Timer stopped externally — cleared local state")
            }
            return entries
        } catch {
            logger.error("syncCurrentTimer failed: \(error.localizedDescription)")
            return nil
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
