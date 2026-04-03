import Foundation

/// Closure-based mock for TimerAPI. Each method delegates to a stored closure,
/// defaulting to safe stubs (empty array for fetches, throwing for mutations).
struct MockTimerAPI: TimerAPI, @unchecked Sendable {
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
}
