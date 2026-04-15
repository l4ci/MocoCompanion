import Foundation
@testable import MocoCompanion

/// Factory helpers for creating test data. All methods return fully-formed model
/// instances with sensible defaults — override only the fields your test cares about.
enum TestFactories {

    // MARK: - MocoActivity

    /// Create a MocoActivity with sensible defaults. Override only what your test needs.
    static func makeActivity(
        id: Int = 1,
        date: String? = nil,
        projectId: Int = 100, projectName: String = "Test Project",
        taskId: Int = 200, taskName: String = "Test Task",
        customerId: Int = 300, customerName: String = "Test Customer",
        seconds: Int = 3600,
        hours: Double = 1.0,
        description: String = "",
        billable: Bool = true,
        tag: String = "",
        timerStartedAt: String? = nil,
        locked: Bool = false
    ) -> MocoActivity {
        MocoActivity(
            id: id,
            date: date ?? todayString(),
            hours: hours,
            seconds: seconds,
            workedSeconds: seconds,
            description: description,
            billed: false,
            billable: billable,
            tag: tag,
            project: ActivityProject(id: projectId, name: projectName, billable: billable),
            task: ActivityTask(id: taskId, name: taskName, billable: billable),
            customer: MocoCustomer(id: customerId, name: customerName),
            user: MocoUser(id: 42, firstname: "Test", lastname: "User"),
            hourlyRate: 100.0,
            timerStartedAt: timerStartedAt,
            locked: locked,
            createdAt: "2025-01-01T00:00:00Z",
            updatedAt: "2025-01-01T00:00:00Z"
        )
    }

    // MARK: - ShadowEntry

    static func makeShadowEntry(
        id: Int = 1,
        localId: String? = nil,
        date: String? = nil,
        projectId: Int = 100,
        projectName: String = "Test Project",
        taskId: Int = 200,
        taskName: String = "Test Task",
        customerId: Int = 300,
        customerName: String = "Test Customer",
        seconds: Int = 3600,
        hours: Double = 1.0,
        description: String = "",
        locked: Bool = false,
        startTime: String? = nil,
        syncStatus: SyncStatus = .synced
    ) -> ShadowEntry {
        let resolvedDate = date ?? todayString()
        return ShadowEntry(
            id: id,
            localId: localId,
            date: resolvedDate,
            hours: hours,
            seconds: seconds,
            workedSeconds: seconds,
            description: description,
            billed: false,
            billable: true,
            tag: "",
            projectId: projectId,
            projectName: projectName,
            projectBillable: true,
            taskId: taskId,
            taskName: taskName,
            taskBillable: true,
            customerId: customerId,
            customerName: customerName,
            userId: 42,
            userFirstname: "Test",
            userLastname: "User",
            hourlyRate: 100.0,
            timerStartedAt: nil,
            startTime: startTime,
            locked: locked,
            createdAt: "2025-01-01T00:00:00Z",
            updatedAt: "2025-01-01T00:00:00Z",
            sync: ShadowEntry.SyncMeta(
                status: syncStatus,
                localUpdatedAt: "2025-01-01T00:00:00Z",
                serverUpdatedAt: "2025-01-01T00:00:00Z",
                conflictFlag: false
            ),
            origin: ShadowEntry.Origin()
        )
    }

    // MARK: - MocoEmployment

    /// Create a MocoEmployment with sensible defaults (40h/week, 4+4 Mon-Fri).
    static func makeEmployment(
        id: Int = 1,
        weeklyTargetHours: Double = 40.0,
        patternAM: [Double] = [4, 4, 4, 4, 4],
        patternPM: [Double] = [4, 4, 4, 4, 4],
        from: String = "2024-01-01",
        to: String? = nil,
        userId: Int = 42
    ) -> MocoEmployment {
        var json: [String: Any] = [
            "id": id,
            "weekly_target_hours": weeklyTargetHours,
            "pattern": ["am": patternAM, "pm": patternPM],
            "from": from,
            "user": ["id": userId, "firstname": "Test", "lastname": "User"],
            "created_at": "2024-01-01T00:00:00Z",
            "updated_at": "2024-01-01T00:00:00Z",
        ]
        if let to { json["to"] = to } else { json["to"] = NSNull() }
        let data = try! JSONSerialization.data(withJSONObject: json)
        return try! JSONDecoder().decode(MocoEmployment.self, from: data)
    }

    // MARK: - MocoSchedule

    /// Create a MocoSchedule (absence entry) with sensible defaults.
    static func makeSchedule(
        id: Int = 1,
        date: String? = nil,
        userId: Int = 42,
        am: Bool = true,
        pm: Bool = true,
        assignmentId: Int = 1,
        assignmentName: String = "Vacation",
        assignmentType: String = "Absence"
    ) -> MocoSchedule {
        let resolvedDate = date ?? todayString()
        let json: [String: Any] = [
            "id": id,
            "date": resolvedDate,
            "comment": NSNull(),
            "am": am,
            "pm": pm,
            "assignment": ["id": assignmentId, "name": assignmentName, "type": assignmentType],
            "user": ["id": userId, "firstname": "Test", "lastname": "User"],
            "created_at": "2024-01-01T00:00:00Z",
            "updated_at": "2024-01-01T00:00:00Z",
        ]
        let data = try! JSONSerialization.data(withJSONObject: json)
        return try! JSONDecoder().decode(MocoSchedule.self, from: data)
    }

    // MARK: - MocoPlanningEntry

    /// Create a MocoPlanningEntry with sensible defaults (8h/day, today only).
    static func makePlanningEntry(
        id: Int = 1,
        projectId: Int = 100,
        projectName: String = "Test Project",
        taskId: Int = 200,
        taskName: String = "Test Task",
        hoursPerDay: Double = 8.0,
        startsOn: String? = nil,
        endsOn: String? = nil,
        userId: Int = 42
    ) -> MocoPlanningEntry {
        let resolvedDate = startsOn ?? todayString()
        let resolvedEnd = endsOn ?? resolvedDate
        let json: [String: Any] = [
            "id": id,
            "title": NSNull(),
            "starts_on": resolvedDate,
            "ends_on": resolvedEnd,
            "hours_per_day": hoursPerDay,
            "comment": NSNull(),
            "project": ["id": projectId, "name": projectName, "customer_name": "Test Customer"],
            "task": ["id": taskId, "name": taskName],
            "user": ["id": userId, "firstname": "Test", "lastname": "User"],
        ]
        let data = try! JSONSerialization.data(withJSONObject: json)
        return try! JSONDecoder().decode(MocoPlanningEntry.self, from: data)
    }

    // MARK: - MocoFullProject

    /// Create a MocoFullProject with sensible defaults (project billing, 100.0 rate, one task).
    static func makeFullProject(
        id: Int = 100,
        name: String = "Test Project",
        billingVariant: String = "project",
        hourlyRate: Double = 100.0,
        budget: Double? = 10000.0,
        tasks: [[String: Any]]? = nil
    ) -> MocoFullProject {
        let resolvedTasks: [[String: Any]] = tasks ?? [
            ["id": 200, "name": "Test Task", "active": true, "billable": true, "budget": NSNull(), "hourly_rate": NSNull()]
        ]
        var json: [String: Any] = [
            "id": id,
            "name": name,
            "identifier": "PROJ-\(id)",
            "active": true,
            "billable": true,
            "billing_variant": billingVariant,
            "hourly_rate": hourlyRate,
            "tasks": resolvedTasks,
        ]
        if let budget { json["budget"] = budget } else { json["budget"] = NSNull() }
        let data = try! JSONSerialization.data(withJSONObject: json)
        return try! JSONDecoder().decode(MocoFullProject.self, from: data)
    }

    // MARK: - MocoProjectReport

    /// Create a MocoProjectReport with sensible defaults (50% progress, 100h remaining).
    static func makeProjectReport(
        budgetTotal: Double? = 10000.0,
        budgetProgressInPercentage: Int? = 50,
        budgetRemaining: Double? = 5000.0,
        hoursTotal: Double? = 50.0,
        hoursBillable: Double? = 45.0,
        hoursRemaining: Double? = 100.0,
        costsByTask: [[String: Any]]? = nil
    ) -> MocoProjectReport {
        let resolvedCosts: [[String: Any]] = costsByTask ?? [
            ["id": 200, "name": "Test Task", "hours_total": 50.0, "total_costs": 5000.0]
        ]
        var json: [String: Any] = [
            "costs_by_task": resolvedCosts,
        ]
        json["budget_total"] = budgetTotal ?? NSNull()
        json["budget_progress_in_percentage"] = budgetProgressInPercentage ?? NSNull()
        json["budget_remaining"] = budgetRemaining ?? NSNull()
        json["hours_total"] = hoursTotal ?? NSNull()
        json["hours_billable"] = hoursBillable ?? NSNull()
        json["hours_remaining"] = hoursRemaining ?? NSNull()
        let data = try! JSONSerialization.data(withJSONObject: json)
        return try! JSONDecoder().decode(MocoProjectReport.self, from: data)
    }

    // MARK: - MocoProjectContract

    /// Create a MocoProjectContract with sensible defaults (user 42, rate 120.0).
    static func makeProjectContract(
        id: Int = 1,
        userId: Int = 42,
        firstname: String = "Test",
        lastname: String = "User",
        hourlyRate: Double = 120.0,
        budget: Double? = nil,
        active: Bool = true,
        billable: Bool = true
    ) -> MocoProjectContract {
        var json: [String: Any] = [
            "id": id,
            "user_id": userId,
            "firstname": firstname,
            "lastname": lastname,
            "billable": billable,
            "active": active,
            "hourly_rate": hourlyRate,
        ]
        if let budget { json["budget"] = budget } else { json["budget"] = NSNull() }
        let data = try! JSONSerialization.data(withJSONObject: json)
        return try! JSONDecoder().decode(MocoProjectContract.self, from: data)
    }

    // MARK: - Common Test Helpers

    /// A notification dispatcher that suppresses all notifications. Safe for unit tests.
    @MainActor
    static func makeStubDispatcher() -> NotificationDispatcher {
        NotificationDispatcher(isEnabledCheck: { _ in false })
    }

    // MARK: - TimerSideEffects

    /// Create a stub TimerSideEffects that suppresses all real side-effects
    /// (sounds, notifications, persistence). Safe for unit tests.
    @MainActor
    static func makeStubSideEffects() -> TimerSideEffects {
        TimerSideEffects(
            recencyTracker: RecencyTracker(),
            recentEntriesTracker: RecentEntriesTracker(),
            descriptionStore: DescriptionStore(),
            settings: SettingsStore(),
            notificationDispatcher: NotificationDispatcher(isEnabledCheck: { _ in false }),
            searchEntriesProvider: { [] },
            budgetRefresh: { _ in },
            budgetStatusProvider: { _, _ in .empty }
        )
    }

    // MARK: - Private

    private static func todayString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: Date())
    }
}
