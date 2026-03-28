import Foundation

// MARK: - User Employments (from GET /users/employments)

struct MocoEmployment: Codable, Identifiable, Sendable {
    let id: Int
    let weeklyTargetHours: Double
    let pattern: EmploymentPattern
    let from: String
    let to: String?
    let user: MocoUser
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id, pattern, from, to, user
        case weeklyTargetHours = "weekly_target_hours"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct EmploymentPattern: Codable, Sendable {
    let am: [Double]
    let pm: [Double]

    func expectedHours(weekdayIndex: Int) -> Double {
        guard weekdayIndex >= 0 && weekdayIndex < 5 else { return 0 }
        return am[weekdayIndex] + pm[weekdayIndex]
    }
}

// MARK: - Schedules / Absences (from GET /schedules)

struct MocoSchedule: Codable, Identifiable, Sendable {
    let id: Int
    let date: String
    let comment: String?
    let am: Bool
    let pm: Bool
    let assignment: ScheduleAssignment
    let user: MocoUser
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id, date, comment, am, pm, assignment, user
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct ScheduleAssignment: Codable, Sendable {
    let id: Int
    let name: String
    let type: String
}
