import Foundation

/// Closure-based mock for the full MocoClientProtocol (SessionAPI + TimerAPI + ActivityAPI + BudgetAPI + YesterdayAPI).
/// Used by SessionManager and ProjectCatalog tests that require the composite protocol.
struct MockMocoClient: MocoClientProtocol, @unchecked Sendable {

    // MARK: - SessionAPI

    var fetchSessionHandler: () async throws -> MocoSession = {
        throw MocoError.serverError(statusCode: 500, message: "fetchSession not stubbed")
    }
    var fetchUserProfileHandler: (Int) async throws -> MocoUserProfile = { _ in
        throw MocoError.serverError(statusCode: 500, message: "fetchUserProfile not stubbed")
    }
    var fetchAssignedProjectsHandler: (Bool) async throws -> [MocoProject] = { _ in [] }

    func fetchSession() async throws -> MocoSession {
        try await fetchSessionHandler()
    }

    func fetchUserProfile(userId: Int) async throws -> MocoUserProfile {
        try await fetchUserProfileHandler(userId)
    }

    func fetchAssignedProjects(active: Bool) async throws -> [MocoProject] {
        try await fetchAssignedProjectsHandler(active)
    }

    // MARK: - TimerAPI

    var fetchActivitiesHandler: (String, String, Int?) async throws -> [MocoActivity] = { _, _, _ in [] }
    var createActivityHandler: (String, Int, Int, String, Int, String?) async throws -> MocoActivity = { _, _, _, _, _, _ in
        throw MocoError.serverError(statusCode: 500, message: "createActivity not stubbed")
    }
    var startTimerHandler: (Int) async throws -> MocoActivity = { _ in
        throw MocoError.serverError(statusCode: 500, message: "startTimer not stubbed")
    }
    var stopTimerHandler: (Int) async throws -> MocoActivity = { _ in
        throw MocoError.serverError(statusCode: 500, message: "stopTimer not stubbed")
    }

    func fetchActivities(from: String, to: String, userId: Int?) async throws -> [MocoActivity] {
        try await fetchActivitiesHandler(from, to, userId)
    }

    func createActivity(date: String, projectId: Int, taskId: Int, description: String, seconds: Int, tag: String?) async throws -> MocoActivity {
        try await createActivityHandler(date, projectId, taskId, description, seconds, tag)
    }

    func startTimer(activityId: Int) async throws -> MocoActivity {
        try await startTimerHandler(activityId)
    }

    func stopTimer(activityId: Int) async throws -> MocoActivity {
        try await stopTimerHandler(activityId)
    }

    // MARK: - ActivityAPI

    var updateActivityDescTagHandler: (Int, String, String?) async throws -> MocoActivity = { _, _, _ in
        throw MocoError.serverError(statusCode: 500, message: "updateActivity(descTag) not stubbed")
    }
    var updateActivityFullHandler: (Int, String?, String?, Int?) async throws -> MocoActivity = { _, _, _, _ in
        throw MocoError.serverError(statusCode: 500, message: "updateActivity(full) not stubbed")
    }
    var deleteActivityHandler: (Int) async throws -> Void = { _ in }
    var fetchPlanningEntriesHandler: (String, Int?) async throws -> [MocoPlanningEntry] = { _, _ in [] }
    var fetchSchedulesHandler: (String, String) async throws -> [MocoSchedule] = { _, _ in [] }

    func updateActivity(activityId: Int, description: String, tag: String?) async throws -> MocoActivity {
        try await updateActivityDescTagHandler(activityId, description, tag)
    }

    func updateActivity(activityId: Int, description: String?, tag: String?, seconds: Int?) async throws -> MocoActivity {
        try await updateActivityFullHandler(activityId, description, tag, seconds)
    }

    func updateActivity(activityId: Int, projectId: Int?, taskId: Int?, description: String?, tag: String?, seconds: Int?) async throws -> MocoActivity {
        throw MocoError.serverError(statusCode: 500, message: "updateActivity(reassign) not stubbed")
    }

    func deleteActivity(activityId: Int) async throws {
        try await deleteActivityHandler(activityId)
    }

    func fetchPlanningEntries(period: String, userId: Int?) async throws -> [MocoPlanningEntry] {
        try await fetchPlanningEntriesHandler(period, userId)
    }

    func fetchSchedules(from: String, to: String) async throws -> [MocoSchedule] {
        try await fetchSchedulesHandler(from, to)
    }

    // MARK: - BudgetAPI

    var fetchProjectHandler: (Int) async throws -> MocoFullProject = { _ in
        throw MocoError.serverError(statusCode: 500, message: "fetchProject not stubbed")
    }
    var fetchProjectReportHandler: (Int) async throws -> MocoProjectReport = { _ in
        throw MocoError.serverError(statusCode: 500, message: "fetchProjectReport not stubbed")
    }
    var fetchProjectContractsHandler: (Int) async throws -> [MocoProjectContract] = { _ in [] }

    func fetchProject(id: Int) async throws -> MocoFullProject {
        try await fetchProjectHandler(id)
    }

    func fetchProjectReport(projectId: Int) async throws -> MocoProjectReport {
        try await fetchProjectReportHandler(projectId)
    }

    func fetchProjectContracts(projectId: Int) async throws -> [MocoProjectContract] {
        try await fetchProjectContractsHandler(projectId)
    }

    // MARK: - YesterdayAPI

    var fetchEmploymentsHandler: (String) async throws -> [MocoEmployment] = { _ in [] }

    func fetchEmployments(from: String) async throws -> [MocoEmployment] {
        try await fetchEmploymentsHandler(from)
    }
}
