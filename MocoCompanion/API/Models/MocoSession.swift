import Foundation

// MARK: - Session (from GET /session)

struct MocoSession: Codable, Sendable {
    let id: Int
    let uuid: String
}

/// User profile data from GET /users/{id}.
struct MocoUserProfile: Codable, Sendable {
    let id: Int
    let firstname: String
    let lastname: String
    let avatarUrl: String?

    enum CodingKeys: String, CodingKey {
        case id, firstname, lastname
        case avatarUrl = "avatar_url"
    }
}
