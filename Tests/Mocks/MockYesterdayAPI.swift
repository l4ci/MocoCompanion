import Foundation

/// Closure-based mock for YesterdayAPI (activities, employments, schedules).
struct MockYesterdayAPI: YesterdayAPI, @unchecked Sendable {
    var fetchActivitiesHandler: (String, String, Int?) async throws -> [MocoActivity] = { _, _, _ in [] }
    var fetchEmploymentsHandler: (String) async throws -> [MocoEmployment] = { _ in [] }
    var fetchSchedulesHandler: (String, String) async throws -> [MocoSchedule] = { _, _ in [] }

    func fetchActivities(from: String, to: String, userId: Int?) async throws -> [MocoActivity] {
        try await fetchActivitiesHandler(from, to, userId)
    }

    func fetchEmployments(from: String) async throws -> [MocoEmployment] {
        try await fetchEmploymentsHandler(from)
    }

    func fetchSchedules(from: String, to: String) async throws -> [MocoSchedule] {
        try await fetchSchedulesHandler(from, to)
    }
}
