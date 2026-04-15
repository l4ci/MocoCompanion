import Foundation
import os

/// Capability for recording project/task usage for recency and autocomplete.
/// ActivityService depends on this instead of the concrete TimerSideEffects type.
@MainActor
protocol UsageRecording: AnyObject {
    func recordUsage(projectId: Int, taskId: Int, description: String)
}

/// Manages activity data: CRUD operations, today/yesterday stats, and data refresh.
/// Uses optimistic local updates after mutations (upserts API responses into local arrays)
/// instead of full refetches. Full refresh reserved for periodic sync only.
///
/// Planning data is managed by PlanningStore; delete/undo by DeleteUndoManager.
/// Forwarding properties maintain backward compatibility for callers.
@Observable
@MainActor
final class ActivityService: ActivitySyncing {
    private let logger = Logger(category: "ActivityService")

    // MARK: - Observable State

    private(set) var todayActivities: [ShadowEntry] = []
    private(set) var todayTotalHours: Double = 0
    private(set) var todayBillablePercentage: Double = 0
    private(set) var yesterdayActivities: [ShadowEntry] = []

    /// Cached sorted arrays — invalidated when activities change.
    @ObservationIgnored private var _sortedToday: [ShadowEntry]?
    @ObservationIgnored private var _sortedYesterday: [ShadowEntry]?

    // MARK: - Dependencies

    private let clientFactory: () -> (any ActivityAPI)?
    private let notificationDispatcher: NotificationDispatcher
    private let userIdProvider: () -> Int?

    /// Records usage for recency/autocomplete after manual entries.
    weak var usageRecorder: (any UsageRecording)?

    /// Rechecks yesterday warning when yesterday activities change locally.
    weak var yesterdayService: YesterdayService?

    /// Shadow DB sync engine — when set, reads go through the local DB instead of API.
    var syncEngine: SyncEngine?

    /// Fired after mutations that change the shadow store, so the timeline can reload.
    var onStoreChanged: (() async -> Void)?

    init(
        clientFactory: @escaping () -> (any ActivityAPI)?,
        notificationDispatcher: NotificationDispatcher,
        userIdProvider: @escaping () -> Int? = { nil }
    ) {
        self.clientFactory = clientFactory
        self.notificationDispatcher = notificationDispatcher
        self.userIdProvider = userIdProvider
    }

    // MARK: - Derived State (cached)

    var sortedTodayActivities: [ShadowEntry] {
        if let cached = _sortedToday { return cached }
        let sorted = todayActivities.sorted { a, b in
            if a.isTimerRunning && !b.isTimerRunning { return true }
            if !a.isTimerRunning && b.isTimerRunning { return false }
            return a.updatedAt > b.updatedAt
        }
        _sortedToday = sorted
        return sorted
    }

    var sortedYesterdayActivities: [ShadowEntry] {
        if let cached = _sortedYesterday { return cached }
        let sorted = yesterdayActivities.sorted { $0.updatedAt > $1.updatedAt }
        _sortedYesterday = sorted
        return sorted
    }

    // MARK: - Data Refresh (full fetch — for periodic sync)

    func refreshTodayStats() async {
        let today = DateUtilities.todayString()

        if let syncEngine {
            let activities = await syncEngine.refresh(date: today)
            applyFetchedTodayActivities(activities)
            return
        }

        guard let client = clientFactory() else { return }
        guard let userId = userIdProvider() else {
            logger.warning("refreshTodayStats skipped — userId not available yet")
            return
        }

        do {
            let activities = try await client.fetchActivities(from: today, to: today, userId: userId)
            applyFetchedTodayActivities(activities.map { ShadowEntry.from($0) })
        } catch {
            logger.error("refreshTodayStats failed: \(error.localizedDescription)")
        }
    }

    /// Load today's entries from the local shadow store without any API call.
    /// Used on tab switch to show instant results from SQLite.
    func loadTodayFromStore() async {
        guard let syncEngine else { return }
        let activities = await syncEngine.entries(forDate: DateUtilities.todayString())
        applyFetchedTodayActivities(activities)
    }

    /// Load yesterday's entries from the local shadow store without any API call.
    func loadYesterdayFromStore() async {
        guard let syncEngine, let yesterday = DateUtilities.yesterdayString() else { return }
        let activities = await syncEngine.entries(forDate: yesterday)
        yesterdayActivities = activities
        _sortedYesterday = nil
        yesterdayService?.recheckLocally(yesterdayActivities: yesterdayActivities)
    }

    /// Apply already-fetched today activities without making an API call.
    /// Used by timer sync to avoid a duplicate fetch.
    func applyFetchedTodayActivities(_ activities: [ShadowEntry]) {
        todayActivities = activities
        recomputeTodayStats()
        invalidateSortedCaches()
        logger.info("Today sync: \(activities.count) entries")
    }

    func refreshYesterdayActivities() async {
        if let syncEngine, let yesterday = DateUtilities.yesterdayString() {
            await syncEngine.sync(dates: [yesterday])
            let activities = await syncEngine.entries(forDate: yesterday)
            yesterdayActivities = activities
            _sortedYesterday = nil
            yesterdayService?.recheckLocally(yesterdayActivities: yesterdayActivities)
            logger.info("Yesterday sync: \(activities.count) entries")
            return
        }

        guard let client = clientFactory() else { return }
        guard let userId = userIdProvider() else {
            logger.warning("refreshYesterdayActivities skipped — userId not available yet")
            return
        }
        guard let yesterday = DateUtilities.yesterdayString() else { return }

        do {
            let activities = try await client.fetchActivities(from: yesterday, to: yesterday, userId: userId)
            yesterdayActivities = activities.map { ShadowEntry.from($0) }
            _sortedYesterday = nil
            yesterdayService?.recheckLocally(yesterdayActivities: yesterdayActivities)
            logger.info("Yesterday sync: \(activities.count) entries")
        } catch {
            logger.error("refreshYesterdayActivities failed: \(error.localizedDescription)")
        }
    }

    // MARK: - CRUD (optimistic local updates)

    func updateDescription(activityId: Int, description: String) async {
        let tag = TagExtractor.extract(from: description)
        let apiDescription = TagExtractor.stripTags(from: description)

        if let syncEngine {
            do {
                try await syncEngine.updateEntry(id: activityId, description: apiDescription, tag: tag)
                let activities = await syncEngine.entries(forDate: DateUtilities.todayString())
                applyFetchedTodayActivities(activities)
                await onStoreChanged?()
                notificationDispatcher.descriptionUpdated()
            } catch {
                handleError(error, label: "updateDescription")
            }
            return
        }

        guard let client = clientFactory() else { return }
        do {
            let updated = try await client.updateActivity(activityId: activityId, description: apiDescription, tag: tag)
            upsertToday(ShadowEntry.from(updated))
            notificationDispatcher.descriptionUpdated()
        } catch {
            handleError(error, label: "updateDescription")
        }
    }

    func editActivity(activityId: Int, seconds: Int, description: String? = nil, tag: String? = nil) async {
        if let syncEngine {
            do {
                try await syncEngine.updateEntry(id: activityId, description: description, tag: tag, seconds: seconds)
                let today = DateUtilities.todayString()
                let activities = await syncEngine.entries(forDate: today)
                applyFetchedTodayActivities(activities)
                await refreshYesterdayActivities()
                await onStoreChanged?()
                notificationDispatcher.entryUpdated()
            } catch {
                handleError(error, label: "editActivity")
            }
            return
        }

        guard let client = clientFactory() else { return }
        do {
            let updated = try await client.updateActivity(
                activityId: activityId, description: description, tag: tag, seconds: seconds
            )
            let entry = ShadowEntry.from(updated)
            upsertToday(entry)
            upsertYesterday(entry)
            notificationDispatcher.entryUpdated()
        } catch {
            handleError(error, label: "editActivity")
        }
    }

    func reassignActivity(activityId: Int, projectId: Int, taskId: Int) async {
        if let syncEngine {
            do {
                try await syncEngine.updateEntry(id: activityId, projectId: projectId, taskId: taskId)
                let today = DateUtilities.todayString()
                let activities = await syncEngine.entries(forDate: today)
                applyFetchedTodayActivities(activities)
                await refreshYesterdayActivities()
                await onStoreChanged?()
                notificationDispatcher.entryUpdated()
            } catch {
                handleError(error, label: "reassignActivity")
            }
            return
        }

        guard let client = clientFactory() else { return }
        do {
            let updated = try await client.updateActivity(
                activityId: activityId, projectId: projectId, taskId: taskId,
                description: nil, tag: nil, seconds: nil
            )
            let entry = ShadowEntry.from(updated)
            upsertToday(entry)
            upsertYesterday(entry)
            notificationDispatcher.entryUpdated()
        } catch {
            handleError(error, label: "reassignActivity")
        }
    }

    func bookManualEntry(
        date: String, projectId: Int, taskId: Int, description: String, seconds: Int
    ) async -> Result<ShadowEntry, MocoError> {
        guard let client = clientFactory() else { return .failure(.invalidConfiguration) }

        let tag = TagExtractor.extract(from: description)
        let apiDescription = TagExtractor.stripTags(from: description)

        do {
            let created = try await client.createActivity(
                date: date, projectId: projectId, taskId: taskId,
                description: apiDescription, seconds: seconds, tag: tag
            )
            let entry = ShadowEntry.from(created)
            try? await syncEngine?.insertSynced(entry)
            appendToday(entry)
            usageRecorder?.recordUsage(projectId: projectId, taskId: taskId, description: description)
            notificationDispatcher.manualEntry(projectName: entry.projectName, hours: Double(seconds) / 3600.0)
            return .success(entry)
        } catch {
            handleError(error, label: "bookManualEntry")
            return .failure(MocoError.from(error))
        }
    }

    func duplicateToToday(entry source: ShadowEntry) async -> Result<ShadowEntry, MocoError> {
        guard let client = clientFactory() else { return .failure(.invalidConfiguration) }

        let today = DateUtilities.todayString()
        do {
            let created = try await client.createActivity(
                date: today, projectId: source.projectId, taskId: source.taskId,
                description: source.description, seconds: source.seconds,
                tag: source.tag.isEmpty ? nil : source.tag
            )
            let entry = ShadowEntry.from(created)
            try? await syncEngine?.insertSynced(entry)
            appendToday(entry)
            notificationDispatcher.entryDuplicated(projectName: entry.projectName, hours: entry.hours)
            return .success(entry)
        } catch {
            handleError(error, label: "duplicateToToday")
            return .failure(MocoError.from(error))
        }
    }

    // MARK: - Local State Mutations (optimistic)

    /// Public: upsert an activity from an external source (e.g., TimerService after pause/resume).
    func upsertActivity(_ activity: ShadowEntry) {
        upsertToday(activity)
    }

    /// Remove an activity from both today and yesterday arrays.
    /// Called by DeleteUndoManager for instant visual feedback on delete.
    func removeLocal(activityId: Int) {
        let hadYesterday = yesterdayActivities.contains { $0.id == activityId }
        todayActivities.removeAll { $0.id == activityId }
        yesterdayActivities.removeAll { $0.id == activityId }
        recomputeTodayStats()
        invalidateSortedCaches()
        _sortedYesterday = nil
        if hadYesterday { yesterdayService?.recheckLocally(yesterdayActivities: yesterdayActivities) }
    }

    /// Restore a today activity after undo. Called by DeleteUndoManager.
    func restoreToday(_ activity: ShadowEntry) {
        todayActivities.append(activity)
        recomputeTodayStats()
        invalidateSortedCaches()
    }

    /// Restore a yesterday activity after undo. Called by DeleteUndoManager.
    func restoreYesterday(_ activity: ShadowEntry) {
        yesterdayActivities.append(activity)
        _sortedYesterday = nil
        yesterdayService?.recheckLocally(yesterdayActivities: yesterdayActivities)
    }

    /// Insert or update an activity in the today array.
    private func upsertToday(_ activity: ShadowEntry) {
        if let idx = todayActivities.firstIndex(where: { $0.id == activity.id }) {
            todayActivities[idx] = activity
        }
        // If the activity's date is today but wasn't in the list (e.g., date changed), add it
        if activity.date == DateUtilities.todayString() && !todayActivities.contains(where: { $0.id == activity.id }) {
            todayActivities.append(activity)
        }
        recomputeTodayStats()
        invalidateSortedCaches()
    }

    /// Update an activity in the yesterday array if present.
    private func upsertYesterday(_ activity: ShadowEntry) {
        if let idx = yesterdayActivities.firstIndex(where: { $0.id == activity.id }) {
            yesterdayActivities[idx] = activity
            _sortedYesterday = nil
            yesterdayService?.recheckLocally(yesterdayActivities: yesterdayActivities)
        }
    }

    /// Append a newly created activity to today.
    private func appendToday(_ activity: ShadowEntry) {
        todayActivities.append(activity)
        recomputeTodayStats()
        invalidateSortedCaches()
    }

    /// Recompute today's stats from the local activities array.
    private func recomputeTodayStats() {
        todayTotalHours = todayActivities.totalHours
        todayBillablePercentage = todayActivities.billablePercentage
    }

    /// Invalidate cached sorted arrays so they recompute on next access.
    private func invalidateSortedCaches() {
        _sortedToday = nil
        _sortedYesterday = nil
    }

    // MARK: - Private

    private func handleError(_ error: any Error, label: String) {
        let mocoError = MocoError.from(error)
        notificationDispatcher.apiError(mocoError)
        logger.error("\(label) failed: \(error.localizedDescription)")
        Task { await AppLogger.shared.app("\(label) failed: \(error.localizedDescription)", level: .error, context: "ActivityService") }
    }
}
