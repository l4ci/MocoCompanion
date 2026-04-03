import Foundation
import os

/// Manages activity data: CRUD operations, today/yesterday stats, and data refresh.
/// Uses optimistic local updates after mutations (upserts API responses into local arrays)
/// instead of full refetches. Full refresh reserved for periodic sync only.
@Observable
@MainActor
final class ActivityService {
    private let logger = Logger(category: "ActivityService")

    // MARK: - Observable State

    private(set) var todayActivities: [MocoActivity] = []
    private(set) var todayTotalHours: Double = 0
    private(set) var todayBillablePercentage: Double = 0
    private(set) var yesterdayActivities: [MocoActivity] = []
    private(set) var todayPlanningEntries: [MocoPlanningEntry] = []
    private(set) var tomorrowPlanningEntries: [MocoPlanningEntry] = []

    /// Absences keyed by date string "YYYY-MM-DD".
    private(set) var absences: [String: MocoSchedule] = [:]

    /// Cached sorted arrays — invalidated when activities change.
    private var _sortedToday: [MocoActivity]?
    private var _sortedYesterday: [MocoActivity]?

    /// A planned task that the user hasn't tracked time on yet today.
    struct UnplannedTask: Identifiable {
        let planningEntry: MocoPlanningEntry
        var id: Int { planningEntry.id }
        var projectId: Int { planningEntry.project?.id ?? 0 }
        var taskId: Int { planningEntry.task?.id ?? 0 }
        var projectName: String { planningEntry.project?.name ?? "Unknown" }
        var customerName: String { planningEntry.project?.customerName ?? "" }
        var taskName: String { planningEntry.task?.name ?? "Unknown" }
        var plannedHours: Double { planningEntry.hoursPerDay }
    }

    // MARK: - Dependencies

    private let clientFactory: () -> (any ActivityAPI)?
    private let sideEffects: TimerSideEffects
    private let userIdProvider: () -> Int?

    /// Called by coordinator to stop timer before deleting a timed activity.
    var onNeedTimerStop: ((Int) async -> Void)?
    /// Called when yesterday's activities change locally (edit, delete, refresh).
    var onYesterdayDataChanged: (() -> Void)?

    init(
        clientFactory: @escaping () -> (any ActivityAPI)?,
        sideEffects: TimerSideEffects,
        userIdProvider: @escaping () -> Int? = { nil }
    ) {
        self.clientFactory = clientFactory
        self.sideEffects = sideEffects
        self.userIdProvider = userIdProvider
    }

    // MARK: - Derived State (cached)

    var sortedTodayActivities: [MocoActivity] {
        if let cached = _sortedToday { return cached }
        let sorted = todayActivities.sorted { a, b in
            if a.isTimerRunning && !b.isTimerRunning { return true }
            if !a.isTimerRunning && b.isTimerRunning { return false }
            return a.updatedAt > b.updatedAt
        }
        _sortedToday = sorted
        return sorted
    }

    var sortedYesterdayActivities: [MocoActivity] {
        if let cached = _sortedYesterday { return cached }
        let sorted = yesterdayActivities.sorted { $0.updatedAt > $1.updatedAt }
        _sortedYesterday = sorted
        return sorted
    }

    // MARK: - Data Refresh (full fetch — for periodic sync)

    func refreshTodayStats() async {
        guard let client = clientFactory() else { return }
        guard let userId = userIdProvider() else {
            logger.warning("refreshTodayStats skipped — userId not available yet")
            return
        }
        let today = DateUtilities.todayString()

        do {
            let activities = try await client.fetchActivities(from: today, to: today, userId: userId)
            applyFetchedTodayActivities(activities)
        } catch {
            logger.error("refreshTodayStats failed: \(error.localizedDescription)")
        }
    }

    /// Apply already-fetched today activities without making an API call.
    /// Used by timer sync to avoid a duplicate fetch.
    func applyFetchedTodayActivities(_ activities: [MocoActivity]) {
        todayActivities = activities
        recomputeTodayStats()
        invalidateSortedCaches()
        logger.info("Today sync: \(activities.count) entries")
    }

    func refreshYesterdayActivities() async {
        guard let client = clientFactory() else { return }
        guard let userId = userIdProvider() else {
            logger.warning("refreshYesterdayActivities skipped — userId not available yet")
            return
        }
        guard let yesterday = DateUtilities.yesterdayString() else { return }

        do {
            let activities = try await client.fetchActivities(from: yesterday, to: yesterday, userId: userId)
            yesterdayActivities = activities
            _sortedYesterday = nil
            onYesterdayDataChanged?()
            logger.info("Yesterday sync: \(activities.count) entries")
        } catch {
            logger.error("refreshYesterdayActivities failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Planning

    func refreshTodayPlanning() async {
        guard let client = clientFactory() else { return }
        guard let userId = userIdProvider() else {
            logger.warning("refreshTodayPlanning skipped — userId not available yet")
            return
        }
        let today = DateUtilities.todayString()
        let period = "\(today):\(today)"

        do {
            let entries = try await client.fetchPlanningEntries(period: period, userId: userId)
            todayPlanningEntries = entries
            logger.info("Planning: \(entries.count) entries for today")
        } catch {
            logger.error("refreshTodayPlanning failed: \(error.localizedDescription)")
        }
    }

    /// Fetch tomorrow's planning entries.
    func refreshTomorrowPlanning() async {
        guard let client = clientFactory() else { return }
        guard let userId = userIdProvider() else {
            logger.warning("refreshTomorrowPlanning skipped — userId not available yet")
            return
        }
        guard let tomorrow = DateUtilities.tomorrowString() else { return }
        let period = "\(tomorrow):\(tomorrow)"

        do {
            let entries = try await client.fetchPlanningEntries(period: period, userId: userId)
            tomorrowPlanningEntries = entries
            logger.info("Tomorrow planning: \(entries.count) entries")
        } catch {
            logger.error("refreshTomorrowPlanning failed: \(error.localizedDescription)")
        }
    }

    /// Fetch today + tomorrow planning entries in a single API call.
    func refreshAllPlanning() async {
        guard let client = clientFactory() else { return }
        guard let userId = userIdProvider() else {
            logger.warning("refreshAllPlanning skipped — userId not available yet")
            return
        }
        let today = DateUtilities.todayString()
        guard let tomorrow = DateUtilities.tomorrowString() else {
            // Fallback: just fetch today
            await refreshTodayPlanning()
            return
        }
        let period = "\(today):\(tomorrow)"

        do {
            let allEntries = try await client.fetchPlanningEntries(period: period, userId: userId)
            let todayEntries = allEntries.filter { $0.startsOn <= today && $0.endsOn >= today }
            let tomorrowEntries = allEntries.filter { $0.startsOn <= tomorrow && $0.endsOn >= tomorrow }
            todayPlanningEntries = todayEntries
            tomorrowPlanningEntries = tomorrowEntries
            logger.info("Planning: \(todayEntries.count) today, \(tomorrowEntries.count) tomorrow (1 API call)")
        } catch {
            logger.error("refreshAllPlanning failed: \(error.localizedDescription)")
        }
    }

    /// Fetch absences (schedules) for yesterday, today, and tomorrow.
    func refreshAbsences() async {
        guard let client = clientFactory() else { return }
        guard let userId = userIdProvider() else {
            logger.warning("refreshAbsences skipped — userId not available yet")
            return
        }
        guard let yesterday = DateUtilities.yesterdayString(),
              let tomorrow = DateUtilities.tomorrowString() else { return }

        do {
            let schedules = try await client.fetchSchedules(from: yesterday, to: tomorrow)
            // Filter to current user and index by date
            var result: [String: MocoSchedule] = [:]
            for schedule in schedules {
                if schedule.user.id == userId {
                    result[schedule.date] = schedule
                }
            }
            absences = result
            logger.info("Absences: \(result.count) days")
        } catch {
            logger.error("refreshAbsences failed: \(error.localizedDescription)")
        }
    }

    /// Get absence info for a specific date, if any.
    func absence(for date: String) -> MocoSchedule? {
        absences[date]
    }

    func plannedHours(projectId: Int, taskId: Int) -> Double? {
        let matching = todayPlanningEntries.filter { $0.project?.id == projectId && $0.task?.id == taskId }
        guard !matching.isEmpty else { return nil }
        return matching.reduce(0) { $0 + $1.hoursPerDay }
    }

    var unplannedTasks: [UnplannedTask] {
        let trackedKeys = Set(todayActivities.map { "\($0.project.id)-\($0.task.id)" })
        return todayPlanningEntries.compactMap { entry in
            guard let project = entry.project, let task = entry.task else { return nil }
            let key = "\(project.id)-\(task.id)"
            if trackedKeys.contains(key) { return nil }
            return UnplannedTask(planningEntry: entry)
        }
    }

    // MARK: - CRUD (optimistic local updates)

    func updateDescription(activityId: Int, description: String) async {
        guard let client = clientFactory() else { return }
        let tag = TagExtractor.extract(from: description)
        let apiDescription = TagExtractor.stripTags(from: description)

        do {
            let updated = try await client.updateActivity(activityId: activityId, description: apiDescription, tag: tag)
            upsertToday(updated)
            sideEffects.onDescriptionUpdated()
        } catch {
            handleError(error, label: "updateDescription")
        }
    }

    // MARK: - Undo Delete

    /// A pending delete that can be undone within the grace period.
    struct PendingDelete {
        let activity: MocoActivity
        let isYesterday: Bool
        let task: Task<Void, Never>
    }

    /// The currently pending delete, if any. Observable so the UI can show the undo toast.
    private(set) var pendingDelete: PendingDelete?

    func deleteActivity(activityId: Int) async {
        guard let client = clientFactory() else { return }

        // Stop timer if this activity is being timed (via coordinator callback)
        await onNeedTimerStop?(activityId)

        // Capture the activity before removing it locally
        let activity = todayActivities.first(where: { $0.id == activityId })
            ?? yesterdayActivities.first(where: { $0.id == activityId })
        let wasYesterday = yesterdayActivities.contains { $0.id == activityId }

        // Cancel any existing pending delete (execute it immediately)
        await commitPendingDelete()

        // Remove locally for instant visual feedback
        removeLocal(activityId: activityId)
        sideEffects.onActivityDeleted()

        guard let activity else {
            // Activity wasn't in local arrays — just delete server-side
            do { try await client.deleteActivity(activityId: activityId) } catch { handleError(error, label: "deleteActivity") }
            return
        }

        // Start a delayed delete — can be undone within 5 seconds
        let deleteTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            await self?.executeDelete(activityId: activityId)
        }

        pendingDelete = PendingDelete(activity: activity, isYesterday: wasYesterday, task: deleteTask)
    }

    /// Undo the pending delete — restore the activity to the local array.
    func undoDelete() {
        guard let pending = pendingDelete else { return }
        pending.task.cancel()

        if pending.isYesterday {
            yesterdayActivities.append(pending.activity)
            _sortedYesterday = nil
            onYesterdayDataChanged?()
        } else {
            todayActivities.append(pending.activity)
            recomputeTodayStats()
            invalidateSortedCaches()
        }

        pendingDelete = nil
        logger.info("Undo delete: restored activity \(pending.activity.id)")
    }

    /// Immediately commit the pending delete (called on timeout or before a new delete).
    func commitPendingDelete() async {
        guard let pending = pendingDelete else { return }
        pending.task.cancel()
        pendingDelete = nil
        await executeDelete(activityId: pending.activity.id)
    }

    /// Execute the actual API delete.
    private func executeDelete(activityId: Int) async {
        guard let client = clientFactory() else { return }
        do {
            try await client.deleteActivity(activityId: activityId)
            logger.info("Deleted activity \(activityId) from server")
        } catch {
            handleError(error, label: "deleteActivity")
        }
        // Clear pending if this was the one
        if pendingDelete?.activity.id == activityId {
            pendingDelete = nil
        }
    }

    func editActivity(activityId: Int, seconds: Int, description: String? = nil, tag: String? = nil) async {
        guard let client = clientFactory() else { return }

        do {
            let updated = try await client.updateActivity(
                activityId: activityId, description: description, tag: tag, seconds: seconds
            )
            upsertToday(updated)
            upsertYesterday(updated)
            sideEffects.onActivityEdited()
        } catch {
            handleError(error, label: "editActivity")
        }
    }

    func reassignActivity(activityId: Int, projectId: Int, taskId: Int) async {
        guard let client = clientFactory() else { return }

        do {
            let updated = try await client.updateActivity(
                activityId: activityId, projectId: projectId, taskId: taskId,
                description: nil, tag: nil, seconds: nil
            )
            upsertToday(updated)
            upsertYesterday(updated)
            sideEffects.onActivityEdited()
        } catch {
            handleError(error, label: "reassignActivity")
        }
    }

    func bookManualEntry(
        date: String, projectId: Int, taskId: Int, description: String, seconds: Int
    ) async -> Result<MocoActivity, MocoError> {
        guard let client = clientFactory() else { return .failure(.invalidConfiguration) }

        let tag = TagExtractor.extract(from: description)
        let apiDescription = TagExtractor.stripTags(from: description)

        do {
            let created = try await client.createActivity(
                date: date, projectId: projectId, taskId: taskId,
                description: apiDescription, seconds: seconds, tag: tag
            )
            appendToday(created)
            sideEffects.onManualEntry(
                projectId: projectId, taskId: taskId, description: description,
                projectName: created.project.name, hours: Double(seconds) / 3600.0
            )
            return .success(created)
        } catch {
            handleError(error, label: "bookManualEntry")
            return .failure(MocoError.from(error))
        }
    }

    func duplicateToToday(activity: MocoActivity) async -> Result<MocoActivity, MocoError> {
        guard let client = clientFactory() else { return .failure(.invalidConfiguration) }

        let today = DateUtilities.todayString()
        do {
            let created = try await client.createActivity(
                date: today, projectId: activity.project.id, taskId: activity.task.id,
                description: activity.description, seconds: activity.seconds,
                tag: activity.tag.isEmpty ? nil : activity.tag
            )
            appendToday(created)
            sideEffects.onDuplicated(projectName: created.project.name, hours: created.hours)
            return .success(created)
        } catch {
            handleError(error, label: "duplicateToToday")
            return .failure(MocoError.from(error))
        }
    }

    // MARK: - Local State Mutations (optimistic)

    /// Public: upsert an activity from an external source (e.g., TimerService after pause/resume).
    func upsertActivity(_ activity: MocoActivity) {
        upsertToday(activity)
    }

    /// Insert or update an activity in the today array.
    private func upsertToday(_ activity: MocoActivity) {
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
    private func upsertYesterday(_ activity: MocoActivity) {
        if let idx = yesterdayActivities.firstIndex(where: { $0.id == activity.id }) {
            yesterdayActivities[idx] = activity
            _sortedYesterday = nil
            onYesterdayDataChanged?()
        }
    }

    /// Append a newly created activity to today.
    private func appendToday(_ activity: MocoActivity) {
        todayActivities.append(activity)
        recomputeTodayStats()
        invalidateSortedCaches()
    }

    /// Remove an activity from both today and yesterday arrays.
    private func removeLocal(activityId: Int) {
        let hadYesterday = yesterdayActivities.contains { $0.id == activityId }
        todayActivities.removeAll { $0.id == activityId }
        yesterdayActivities.removeAll { $0.id == activityId }
        recomputeTodayStats()
        invalidateSortedCaches()
        _sortedYesterday = nil
        if hadYesterday { onYesterdayDataChanged?() }
    }

    /// Recompute today's stats from the local activities array.
    private func recomputeTodayStats() {
        let total = todayActivities.reduce(0.0) { $0 + $1.hours }
        let billable = todayActivities.filter(\.billable).reduce(0.0) { $0 + $1.hours }
        todayTotalHours = total
        todayBillablePercentage = total > 0 ? (billable / total) * 100.0 : 0
    }

    /// Invalidate cached sorted arrays so they recompute on next access.
    private func invalidateSortedCaches() {
        _sortedToday = nil
        _sortedYesterday = nil
    }

    // MARK: - Private

    private func handleError(_ error: any Error, label: String) {
        let mocoError = MocoError.from(error)
        sideEffects.onError(mocoError)
        logger.error("\(label) failed: \(error.localizedDescription)")
        Task { await AppLogger.shared.app("\(label) failed: \(error.localizedDescription)", level: .error, context: "ActivityService") }
    }
}
