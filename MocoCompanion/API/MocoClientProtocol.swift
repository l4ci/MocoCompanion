import Foundation

// MARK: - Role Protocols
// Each service declares only the API surface it needs.
// MocoClient conforms to all. Test mocks implement 2-5 methods instead of 17.

/// Session, profile, and project catalog endpoints.
protocol SessionAPI: Sendable {
    func fetchSession() async throws -> MocoSession
    func fetchUserProfile(userId: Int) async throws -> MocoUserProfile
    func fetchAssignedProjects(active: Bool) async throws -> [MocoProject]
}

/// Timer lifecycle: fetch activities, create, start/stop timer.
protocol TimerAPI: Sendable {
    func fetchActivities(from: String, to: String, userId: Int?) async throws -> [MocoActivity]
    func createActivity(date: String, projectId: Int, taskId: Int, description: String, seconds: Int, tag: String?) async throws -> MocoActivity
    func startTimer(activityId: Int) async throws -> MocoActivity
    func stopTimer(activityId: Int) async throws -> MocoActivity
}

/// Activity CRUD, planning, and schedules.
protocol ActivityAPI: Sendable {
    func fetchActivities(from: String, to: String, userId: Int?) async throws -> [MocoActivity]
    func createActivity(date: String, projectId: Int, taskId: Int, description: String, seconds: Int, tag: String?) async throws -> MocoActivity
    func updateActivity(activityId: Int, description: String, tag: String?) async throws -> MocoActivity
    func updateActivity(activityId: Int, description: String?, tag: String?, seconds: Int?) async throws -> MocoActivity
    func updateActivity(activityId: Int, projectId: Int?, taskId: Int?, description: String?, tag: String?, seconds: Int?) async throws -> MocoActivity
    func deleteActivity(activityId: Int) async throws
    func fetchPlanningEntries(period: String, userId: Int?) async throws -> [MocoPlanningEntry]
    func fetchSchedules(from: String, to: String) async throws -> [MocoSchedule]
}

/// Budget data: full project details, reports, contracts.
protocol BudgetAPI: Sendable {
    func fetchProject(id: Int) async throws -> MocoFullProject
    func fetchProjectReport(projectId: Int) async throws -> MocoProjectReport
    func fetchProjectContracts(projectId: Int) async throws -> [MocoProjectContract]
}

/// Yesterday check: activities, employments, schedules.
protocol YesterdayAPI: Sendable {
    func fetchActivities(from: String, to: String, userId: Int?) async throws -> [MocoActivity]
    func fetchEmployments(from: String) async throws -> [MocoEmployment]
    func fetchSchedules(from: String, to: String) async throws -> [MocoSchedule]
}

// MARK: - Composite Protocol

/// Full API surface — union of all role protocols.
/// Used at the wiring site (AppState) where one factory serves all consumers.
typealias MocoClientProtocol = SessionAPI & TimerAPI & ActivityAPI & BudgetAPI & YesterdayAPI

// MARK: - Default Parameter Extensions

extension SessionAPI {
    func fetchAssignedProjects() async throws -> [MocoProject] {
        try await fetchAssignedProjects(active: true)
    }
}

extension TimerAPI {
    func createActivity(date: String, projectId: Int, taskId: Int, description: String, seconds: Int = 0, tag: String? = nil) async throws -> MocoActivity {
        try await createActivity(date: date, projectId: projectId, taskId: taskId, description: description, seconds: seconds, tag: tag)
    }
}

extension ActivityAPI {
    func createActivity(date: String, projectId: Int, taskId: Int, description: String, seconds: Int = 0, tag: String? = nil) async throws -> MocoActivity {
        try await createActivity(date: date, projectId: projectId, taskId: taskId, description: description, seconds: seconds, tag: tag)
    }
}
