import Foundation

/// Mock API client returning realistic demo data for screenshots.
/// Activated via Settings > Debug > Demo Mode (requires restart).
final class DemoMocoClient: MocoClientProtocol, @unchecked Sendable {

    // MARK: - Shared Data

    private static let userId = 42
    private static let user = MocoUser(id: userId, firstname: "Anna", lastname: "Müller")
    private static let now = ISO8601DateFormatter().string(from: .now)

    private static let customers = (
        weber:      MocoCustomer(id: 101, name: "Designstudio Weber"),
        techstart:  MocoCustomer(id: 102, name: "TechStart GmbH"),
        stadtwerke: MocoCustomer(id: 103, name: "Stadtwerke Musterstadt")
    )

    // MARK: - Projects

    static let projects: [MocoProject] = [
        MocoProject(
            id: 201, identifier: "WR-24", name: "Website Relaunch", active: true, billable: true,
            color: "#3B82F6", customer: customers.weber,
            tasks: [
                MocoTask(id: 301, name: "Design", active: true, billable: true),
                MocoTask(id: 302, name: "Entwicklung", active: true, billable: true),
                MocoTask(id: 303, name: "Projektmanagement", active: true, billable: true),
            ],
            contract: MocoContract(userId: userId, active: true)
        ),
        MocoProject(
            id: 202, identifier: "TS-APP", name: "Mobile App", active: true, billable: true,
            color: "#10B981", customer: customers.techstart,
            tasks: [
                MocoTask(id: 304, name: "iOS Development", active: true, billable: true),
                MocoTask(id: 305, name: "QA Testing", active: true, billable: true),
                MocoTask(id: 306, name: "Meetings", active: true, billable: false),
            ],
            contract: MocoContract(userId: userId, active: true)
        ),
        MocoProject(
            id: 203, identifier: "SW-INT", name: "Intranet Portal", active: true, billable: true,
            color: "#F59E0B", customer: customers.stadtwerke,
            tasks: [
                MocoTask(id: 307, name: "Backend", active: true, billable: true),
                MocoTask(id: 308, name: "Frontend", active: true, billable: true),
                MocoTask(id: 309, name: "Dokumentation", active: true, billable: false),
            ],
            contract: MocoContract(userId: userId, active: true)
        ),
        MocoProject(
            id: 204, identifier: "INT", name: "Internal", active: true, billable: false,
            color: "#8B5CF6", customer: MocoCustomer(id: 100, name: "Eigene Firma GmbH"),
            tasks: [
                MocoTask(id: 310, name: "Administration", active: true, billable: false),
                MocoTask(id: 311, name: "Team Meeting", active: true, billable: false),
                MocoTask(id: 312, name: "Weiterbildung", active: true, billable: false),
            ],
            contract: nil
        ),
    ]

    // MARK: - Activities

    private static func todayActivities() -> [MocoActivity] {
        let today = DateUtilities.todayString()
        return [
            MocoActivity(
                id: 1001, date: today, hours: 1.5, seconds: 5400, workedSeconds: 5400,
                description: "Header-Konzept überarbeiten", billed: false, billable: true, tag: "",
                project: ActivityProject(id: 201, name: "Website Relaunch", billable: true),
                task: ActivityTask(id: 301, name: "Design", billable: true),
                customer: customers.weber, user: user, hourlyRate: 120,
                createdAt: now, updatedAt: now
            ),
            MocoActivity(
                id: 1002, date: today, hours: 0.5, seconds: 1800, workedSeconds: 1800,
                description: "Daily Standup", billed: false, billable: false, tag: "",
                project: ActivityProject(id: 204, name: "Internal", billable: false),
                task: ActivityTask(id: 311, name: "Team Meeting", billable: false),
                customer: MocoCustomer(id: 100, name: "Eigene Firma GmbH"), user: user, hourlyRate: 0,
                createdAt: now, updatedAt: now
            ),
            MocoActivity(
                id: 1003, date: today, hours: 1.75, seconds: 6300, workedSeconds: 6300,
                description: "Push-Notifications implementieren", billed: false, billable: true, tag: "",
                project: ActivityProject(id: 202, name: "Mobile App", billable: true),
                task: ActivityTask(id: 304, name: "iOS Development", billable: true),
                customer: customers.techstart, user: user, hourlyRate: 130,
                timerStartedAt: ISO8601DateFormatter().string(from: .now),
                createdAt: now, updatedAt: now
            ),
            MocoActivity(
                id: 1004, date: today, hours: 1.0, seconds: 3600, workedSeconds: 3600,
                description: "REST API Endpunkte erweitern", billed: false, billable: true, tag: "",
                project: ActivityProject(id: 203, name: "Intranet Portal", billable: true),
                task: ActivityTask(id: 307, name: "Backend", billable: true),
                customer: customers.stadtwerke, user: user, hourlyRate: 120,
                createdAt: now, updatedAt: now
            ),
            MocoActivity(
                id: 1005, date: today, hours: 0.75, seconds: 2700, workedSeconds: 2700,
                description: "Responsive Fixes für Tablet-Ansicht", billed: false, billable: true, tag: "",
                project: ActivityProject(id: 201, name: "Website Relaunch", billable: true),
                task: ActivityTask(id: 302, name: "Entwicklung", billable: true),
                customer: customers.weber, user: user, hourlyRate: 120,
                createdAt: now, updatedAt: now
            ),
        ]
    }

    // MARK: - SessionAPI

    func fetchSession() async throws -> MocoSession {
        MocoSession(id: Self.userId, uuid: "demo-uuid-\(Self.userId)")
    }

    func fetchUserProfile(userId: Int) async throws -> MocoUserProfile {
        MocoUserProfile(id: Self.userId, firstname: "Anna", lastname: "Müller", avatarUrl: nil)
    }

    func fetchAssignedProjects(active: Bool) async throws -> [MocoProject] {
        Self.projects
    }

    // MARK: - TimerAPI

    func fetchActivities(from: String, to: String, userId: Int?) async throws -> [MocoActivity] {
        Self.todayActivities().filter { $0.date >= from && $0.date <= to }
    }

    func createActivity(date: String, projectId: Int, taskId: Int, description: String, seconds: Int, tag: String?) async throws -> MocoActivity {
        let project = Self.projects.first { $0.id == projectId }
        let task = project?.tasks.first { $0.id == taskId }
        return MocoActivity(
            id: Int.random(in: 2000...9999), date: date, hours: Double(seconds) / 3600.0,
            seconds: seconds, workedSeconds: seconds, description: description,
            billed: false, billable: project?.billable ?? true, tag: tag ?? "",
            project: ActivityProject(id: projectId, name: project?.name ?? "Project", billable: project?.billable ?? true),
            task: ActivityTask(id: taskId, name: task?.name ?? "Task", billable: task?.billable ?? true),
            customer: project?.customer ?? MocoCustomer(id: 0, name: "Unknown"),
            user: Self.user, hourlyRate: 120,
            timerStartedAt: seconds == 0 ? Self.now : nil,
            createdAt: Self.now, updatedAt: Self.now
        )
    }

    func startTimer(activityId: Int) async throws -> MocoActivity {
        if var activity = Self.todayActivities().first(where: { $0.id == activityId }) {
            return MocoActivity(
                id: activity.id, date: activity.date, hours: activity.hours,
                seconds: activity.seconds, workedSeconds: activity.workedSeconds,
                description: activity.description, billed: activity.billed,
                billable: activity.billable, tag: activity.tag,
                project: activity.project, task: activity.task,
                customer: activity.customer, user: activity.user,
                hourlyRate: activity.hourlyRate,
                timerStartedAt: Self.now,
                createdAt: activity.createdAt, updatedAt: Self.now
            )
        }
        throw MocoError.notFound
    }

    func stopTimer(activityId: Int) async throws -> MocoActivity {
        if let activity = Self.todayActivities().first(where: { $0.id == activityId }) {
            return MocoActivity(
                id: activity.id, date: activity.date, hours: activity.hours,
                seconds: activity.seconds, workedSeconds: activity.workedSeconds,
                description: activity.description, billed: activity.billed,
                billable: activity.billable, tag: activity.tag,
                project: activity.project, task: activity.task,
                customer: activity.customer, user: activity.user,
                hourlyRate: activity.hourlyRate,
                timerStartedAt: nil,
                createdAt: activity.createdAt, updatedAt: Self.now
            )
        }
        throw MocoError.notFound
    }

    // MARK: - ActivityAPI

    func updateActivity(activityId: Int, description: String, tag: String?) async throws -> MocoActivity {
        guard let activity = Self.todayActivities().first(where: { $0.id == activityId }) else {
            throw MocoError.notFound
        }
        return MocoActivity(
            id: activity.id, date: activity.date, hours: activity.hours,
            seconds: activity.seconds, workedSeconds: activity.workedSeconds,
            description: description, billed: activity.billed,
            billable: activity.billable, tag: tag ?? activity.tag,
            project: activity.project, task: activity.task,
            customer: activity.customer, user: activity.user,
            hourlyRate: activity.hourlyRate, timerStartedAt: activity.timerStartedAt,
            createdAt: activity.createdAt, updatedAt: Self.now
        )
    }

    func updateActivity(activityId: Int, description: String?, tag: String?, seconds: Int?) async throws -> MocoActivity {
        guard let activity = Self.todayActivities().first(where: { $0.id == activityId }) else {
            throw MocoError.notFound
        }
        return MocoActivity(
            id: activity.id, date: activity.date,
            hours: seconds.map { Double($0) / 3600.0 } ?? activity.hours,
            seconds: seconds ?? activity.seconds,
            workedSeconds: seconds ?? activity.workedSeconds,
            description: description ?? activity.description,
            billed: activity.billed, billable: activity.billable,
            tag: tag ?? activity.tag,
            project: activity.project, task: activity.task,
            customer: activity.customer, user: activity.user,
            hourlyRate: activity.hourlyRate, timerStartedAt: activity.timerStartedAt,
            createdAt: activity.createdAt, updatedAt: Self.now
        )
    }

    func updateActivity(activityId: Int, projectId: Int?, taskId: Int?, description: String?, tag: String?, seconds: Int?) async throws -> MocoActivity {
        try await updateActivity(activityId: activityId, description: description, tag: tag, seconds: seconds)
    }

    func deleteActivity(activityId: Int) async throws {
        // no-op in demo mode
    }

    func fetchPlanningEntries(period: String, userId: Int?) async throws -> [MocoPlanningEntry] {
        let today = DateUtilities.todayString()
        return [
            MocoPlanningEntry(
                id: 501, title: nil, startsOn: today, endsOn: today, hoursPerDay: 4,
                comment: nil,
                project: PlanningProject(id: 201, name: "Website Relaunch", customerName: "Designstudio Weber"),
                task: PlanningTask(id: 301, name: "Design"),
                user: Self.user
            ),
            MocoPlanningEntry(
                id: 502, title: nil, startsOn: today, endsOn: today, hoursPerDay: 4,
                comment: nil,
                project: PlanningProject(id: 202, name: "Mobile App", customerName: "TechStart GmbH"),
                task: PlanningTask(id: 304, name: "iOS Development"),
                user: Self.user
            ),
        ]
    }

    func fetchSchedules(from: String, to: String) async throws -> [MocoSchedule] {
        []
    }

    // MARK: - BudgetAPI

    func fetchProject(id: Int) async throws -> MocoFullProject {
        throw MocoError.notFound
    }

    func fetchProjectReport(projectId: Int) async throws -> MocoProjectReport {
        throw MocoError.notFound
    }

    func fetchProjectContracts(projectId: Int) async throws -> [MocoProjectContract] {
        []
    }

    // MARK: - YesterdayAPI

    func fetchEmployments(from: String) async throws -> [MocoEmployment] {
        [
            MocoEmployment(
                id: 1, weeklyTargetHours: 40,
                pattern: EmploymentPattern(am: [4, 4, 4, 4, 4], pm: [4, 4, 4, 4, 4]),
                from: "2024-01-01", to: nil, user: Self.user,
                createdAt: Self.now, updatedAt: Self.now
            ),
        ]
    }
}
