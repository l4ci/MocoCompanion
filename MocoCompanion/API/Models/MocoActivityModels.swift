import Foundation

// MARK: - Activities (from GET /activities, POST /activities)

struct MocoActivity: Codable, Identifiable, Sendable, Equatable {
    let id: Int
    let date: String
    let hours: Double
    let seconds: Int
    let workedSeconds: Int
    let description: String
    let billed: Bool
    let billable: Bool
    let tag: String
    let project: ActivityProject
    let task: ActivityTask
    let customer: MocoCustomer
    let user: MocoUser
    let hourlyRate: Double
    let timerStartedAt: String?
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id, date, hours, seconds, description, billed, billable, tag
        case project, task, customer, user
        case workedSeconds = "worked_seconds"
        case hourlyRate = "hourly_rate"
        case timerStartedAt = "timer_started_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    /// Whether the timer is currently running on this activity.
    var isTimerRunning: Bool {
        timerStartedAt != nil
    }
}

/// Nested project representation inside an activity response.
struct ActivityProject: Codable, Identifiable, Sendable, Equatable {
    let id: Int
    let name: String
    let billable: Bool
}

/// Nested task representation inside an activity response.
struct ActivityTask: Codable, Identifiable, Sendable, Equatable {
    let id: Int
    let name: String
    let billable: Bool
}

struct MocoUser: Codable, Identifiable, Sendable, Equatable {
    let id: Int
    let firstname: String
    let lastname: String
}

// MARK: - Request Bodies

struct CreateActivityRequest: Encodable, Sendable {
    let date: String
    let projectId: Int
    let taskId: Int
    let description: String
    let seconds: Int
    let tag: String?

    enum CodingKeys: String, CodingKey {
        case date, description, seconds, tag
        case projectId = "project_id"
        case taskId = "task_id"
    }
}

struct UpdateActivityRequest: Encodable, Sendable {
    let projectId: Int?
    let taskId: Int?
    let description: String?
    let tag: String?
    let seconds: Int?

    enum CodingKeys: String, CodingKey {
        case description, tag, seconds
        case projectId = "project_id"
        case taskId = "task_id"
    }

    /// Update description and tag only.
    init(description: String, tag: String?) {
        self.projectId = nil
        self.taskId = nil
        self.description = description
        self.tag = tag
        self.seconds = nil
    }

    /// Update any combination of fields.
    init(projectId: Int? = nil, taskId: Int? = nil, description: String? = nil, tag: String? = nil, seconds: Int? = nil) {
        self.projectId = projectId
        self.taskId = taskId
        self.description = description
        self.tag = tag
        self.seconds = seconds
    }
}
