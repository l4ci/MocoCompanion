import Foundation
import os

/// Manages planning data: today/tomorrow planning entries, absences, and unplanned tasks.
/// Extracted from ActivityService to keep concerns separated.
@Observable
@MainActor
final class PlanningStore {
    private let logger = Logger(category: "PlanningStore")

    // MARK: - Observable State

    private(set) var todayPlanningEntries: [MocoPlanningEntry] = []
    private(set) var tomorrowPlanningEntries: [MocoPlanningEntry] = []

    /// Absences keyed by date string "YYYY-MM-DD".
    private(set) var absences: [String: MocoSchedule] = [:]

    // MARK: - Dependencies

    var notifications: NotificationDispatcher?

    private let clientFactory: () -> (any ActivityAPI)?
    private let userIdProvider: () -> Int?
    private let todayActivitiesProvider: () -> [ShadowEntry]

    init(
        clientFactory: @escaping () -> (any ActivityAPI)?,
        userIdProvider: @escaping () -> Int?,
        todayActivitiesProvider: @escaping () -> [ShadowEntry]
    ) {
        self.clientFactory = clientFactory
        self.userIdProvider = userIdProvider
        self.todayActivitiesProvider = todayActivitiesProvider
    }

    // MARK: - Refresh

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
            notifications?.apiError(MocoError.from(error))
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
            notifications?.apiError(MocoError.from(error))
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
            notifications?.apiError(MocoError.from(error))
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
            notifications?.apiError(MocoError.from(error))
        }
    }

    // MARK: - Queries

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
        let activities = todayActivitiesProvider()
        let trackedKeys = Set(activities.map { "\($0.projectId)-\($0.taskId)" })
        return todayPlanningEntries.compactMap { entry in
            guard let project = entry.project, let task = entry.task else { return nil }
            let key = "\(project.id)-\(task.id)"
            if trackedKeys.contains(key) { return nil }
            return UnplannedTask(planningEntry: entry)
        }
    }

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
}
