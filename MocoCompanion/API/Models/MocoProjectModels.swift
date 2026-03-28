import Foundation

// MARK: - Projects (from GET /projects/assigned)

struct MocoProject: Codable, Identifiable, Sendable {
    let id: Int
    let identifier: String
    let name: String
    let active: Bool
    let billable: Bool
    let customer: MocoCustomer
    let tasks: [MocoTask]
    let contract: MocoContract?
}

struct MocoTask: Codable, Identifiable, Sendable {
    let id: Int
    let name: String
    let active: Bool
    let billable: Bool
}

struct MocoCustomer: Codable, Identifiable, Sendable, Equatable {
    let id: Int
    let name: String
}

struct MocoContract: Codable, Sendable {
    let userId: Int
    let active: Bool

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case active
    }
}
