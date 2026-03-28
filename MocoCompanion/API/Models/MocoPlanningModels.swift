import Foundation

// MARK: - Planning Entries (from GET /planning_entries)

struct MocoPlanningEntry: Codable, Identifiable, Sendable {
    let id: Int
    let title: String?
    let startsOn: String
    let endsOn: String
    let hoursPerDay: Double
    let comment: String?
    let project: PlanningProject?
    let task: PlanningTask?
    let user: MocoUser

    enum CodingKeys: String, CodingKey {
        case id, title, comment, project, task, user
        case startsOn = "starts_on"
        case endsOn = "ends_on"
        case hoursPerDay = "hours_per_day"
    }
}

struct PlanningProject: Codable, Sendable {
    let id: Int
    let name: String
    let customerName: String?

    enum CodingKeys: String, CodingKey {
        case id, name
        case customerName = "customer_name"
    }
}

struct PlanningTask: Codable, Sendable {
    let id: Int
    let name: String
}
