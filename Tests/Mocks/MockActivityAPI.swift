import Foundation
@testable import MocoCompanion

/// Closure-based mock for ActivityAPI. Uses distinct closure names for the three
/// `updateActivity` overloads to avoid ambiguity.
struct MockActivityAPI: ActivityAPI, @unchecked Sendable {
    var fetchActivitiesHandler: (String, String, Int?) async throws -> [MocoActivity] = { _, _, _ in [] }
    var createActivityHandler: (String, Int, Int, String, Int, String?) async throws -> MocoActivity = { _, _, _, _, _, _ in
        throw MocoError.serverError(statusCode: 500, message: "createActivity not stubbed")
    }
    var updateActivityDescTag: (Int, String, String?) async throws -> MocoActivity = { _, _, _ in
        throw MocoError.serverError(statusCode: 500, message: "updateActivity(descTag) not stubbed")
    }
    var updateActivityFull: (Int, String?, String?, Int?) async throws -> MocoActivity = { _, _, _, _ in
        throw MocoError.serverError(statusCode: 500, message: "updateActivity(full) not stubbed")
    }
    var deleteActivityHandler: (Int) async throws -> Void = { _ in
        throw MocoError.serverError(statusCode: 500, message: "deleteActivity not stubbed")
    }
    var fetchPlanningEntriesHandler: (String, Int?) async throws -> [MocoPlanningEntry] = { _, _ in [] }
    var fetchSchedulesHandler: (String, String) async throws -> [MocoSchedule] = { _, _ in [] }

    func fetchActivities(from: String, to: String, userId: Int?) async throws -> [MocoActivity] {
        try await fetchActivitiesHandler(from, to, userId)
    }

    func createActivity(date: String, projectId: Int, taskId: Int, description: String, seconds: Int, tag: String?) async throws -> MocoActivity {
        try await createActivityHandler(date, projectId, taskId, description, seconds, tag)
    }

    func updateActivity(activityId: Int, description: String, tag: String?) async throws -> MocoActivity {
        try await updateActivityDescTag(activityId, description, tag)
    }

    func updateActivity(activityId: Int, description: String?, tag: String?, seconds: Int?) async throws -> MocoActivity {
        try await updateActivityFull(activityId, description, tag, seconds)
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
}
