import Foundation

/// Handles all side-effects triggered by timer operations.
/// Owns recency tracking, recent entries, description autocomplete, sound feedback,
/// and notification dispatch. TimerService calls a single method per event instead
/// of orchestrating 3-5 individual side-effects inline.
@MainActor
final class TimerSideEffects {
    private let recencyTracker: RecencyTracker
    private let recentEntriesTracker: RecentEntriesTracker
    private let descriptionStore: DescriptionStore
    private let settings: SettingsStore
    private let notificationDispatcher: NotificationDispatcher
    private let searchEntriesProvider: () -> [SearchEntry]
    private let budgetRefresh: (Int) async -> Void
    private let budgetStatusProvider: (Int, Int?) -> BudgetStatus

    /// When true, the next `onTimerStopped` call skips its notification.
    /// Set before an internal stop-then-start (timer switch) to avoid noise.
    private var suppressNextStopNotification = false

    init(
        recencyTracker: RecencyTracker,
        recentEntriesTracker: RecentEntriesTracker,
        descriptionStore: DescriptionStore,
        settings: SettingsStore,
        notificationDispatcher: NotificationDispatcher,
        searchEntriesProvider: @escaping () -> [SearchEntry],
        budgetRefresh: @escaping (Int) async -> Void = { _ in },
        budgetStatusProvider: @escaping (Int, Int?) -> BudgetStatus = { _, _ in .empty }
    ) {
        self.recencyTracker = recencyTracker
        self.recentEntriesTracker = recentEntriesTracker
        self.descriptionStore = descriptionStore
        self.settings = settings
        self.notificationDispatcher = notificationDispatcher
        self.searchEntriesProvider = searchEntriesProvider
        self.budgetRefresh = budgetRefresh
        self.budgetStatusProvider = budgetStatusProvider
    }

    // MARK: - Timer Events

    /// A new timer was started via the quick-entry flow.
    func onTimerStarted(projectId: Int, taskId: Int, description: String, projectName: String) {
        recordUsage(projectId: projectId, taskId: taskId, description: description)
        playSound(.start)
        notificationDispatcher.send(.timerStarted, message: String(localized: "notification.timerStarted") + " " + projectName)
        Task {
            await budgetRefresh(projectId)
            dispatchBudgetWarning(projectId: projectId, taskId: taskId, projectName: projectName)
        }
    }

    /// Timer was paused (API stop, but state stays tracked).
    func onTimerPaused(projectName: String) {
        playSound(.stop)
        notificationDispatcher.send(.timerStopped, message: String(localized: "notification.timerStopped") + " " + projectName)
    }

    /// Timer was resumed.
    func onTimerResumed(projectName: String) {
        playSound(.start)
        notificationDispatcher.send(.timerResumed, message: String(localized: "notification.timerResumed") + " " + projectName)
    }

    /// Timer was stopped completely.
    func onTimerStopped() {
        playSound(.stop)
        if suppressNextStopNotification {
            suppressNextStopNotification = false
        } else {
            notificationDispatcher.send(.timerStopped, message: String(localized: "notification.timerStopped"))
        }
    }

    /// Mark that the next stop is part of a switch — suppress its notification.
    func suppressStopNotification() {
        suppressNextStopNotification = true
    }

    /// An existing timer was continued (started on a previous entry).
    func onTimerContinued(projectId: Int, taskId: Int, projectName: String) {
        playSound(.start)
        notificationDispatcher.send(.timerContinued, message: String(localized: "notification.timerContinued") + " " + projectName)
        Task {
            await budgetRefresh(projectId)
            dispatchBudgetWarning(projectId: projectId, taskId: taskId, projectName: projectName)
        }
    }

    /// An activity's description or hours were edited.
    func onActivityEdited() {
        notificationDispatcher.send(.descriptionUpdated, message: String(localized: "notification.entryUpdated"))
    }

    /// A description was updated (no hours change).
    func onDescriptionUpdated() {
        notificationDispatcher.send(.descriptionUpdated, message: String(localized: "notification.descriptionUpdated"))
    }

    /// An activity was deleted.
    func onActivityDeleted() {
        notificationDispatcher.send(.activityDeleted, message: String(localized: "notification.entryDeleted"))
    }

    /// A manual time entry was booked (no timer).
    func onManualEntry(projectId: Int, taskId: Int, description: String, projectName: String, hours: Double) {
        recordUsage(projectId: projectId, taskId: taskId, description: description)
        let formatted = String(format: "%.1fh", hours)
        notificationDispatcher.send(.manualEntry, message: "Booked \(formatted) for \(projectName)")
    }

    /// An entry was duplicated to today.
    func onDuplicated(projectName: String, hours: Double) {
        let formatted = String(format: "%.1fh", hours)
        notificationDispatcher.send(.activityDuplicated, message: "Duplicated \(formatted) for \(projectName)")
    }

    /// An externally running timer was stopped (during startTimer flow).
    func onExternalTimerStopped() {
        playSound(.stop)
    }

    /// An API error occurred. Dispatches error notification.
    func onError(_ error: MocoError) {
        notificationDispatcher.send(.apiError, message: error.errorDescription ?? "Unknown error")
    }

    // MARK: - Private

    private enum SoundType { case start, stop }

    /// Check budget status and dispatch a warning notification if warranted.
    private func dispatchBudgetWarning(projectId: Int, taskId: Int, projectName: String) {
        let status = budgetStatusProvider(projectId, taskId)
        switch status.effectiveBadge {
        case .taskCritical:
            let msg = String(localized: "notification.budgetTaskWarning") + " " + projectName
            notificationDispatcher.send(.budgetTaskWarning, message: msg)
        case .projectCritical, .projectWarning:
            let msg = String(localized: "notification.budgetProjectWarning") + " " + projectName
            notificationDispatcher.send(.budgetProjectWarning, message: msg)
        case .none:
            break
        }
    }

    private func playSound(_ type: SoundType) {
        guard settings.sound.enabled else { return }
        switch type {
        case .start: SoundFeedback.playStart()
        case .stop: SoundFeedback.playStop()
        }
    }

    private func recordUsage(projectId: Int, taskId: Int, description: String) {
        recencyTracker.recordUsage(projectId: projectId)
        let entries = searchEntriesProvider()
        if let searchEntry = entries.first(where: { $0.projectId == projectId && $0.taskId == taskId }) {
            recentEntriesTracker.record(
                projectId: projectId, taskId: taskId,
                customerName: searchEntry.customerName, projectName: searchEntry.projectName,
                taskName: searchEntry.taskName, description: description
            )
        }
        descriptionStore.record(description)
    }
}
