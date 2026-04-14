import Foundation

// MARK: - Session (from GET /session)

struct MocoSession: Codable, Sendable {
    let id: Int
    let uuid: String
    /// Firstname — returned by the /session endpoint alongside id/uuid.
    let firstname: String
    let lastname: String
    /// Avatar URL — may be nil if the user hasn't uploaded one.
    let avatarUrl: String?

    enum CodingKeys: String, CodingKey {
        case id, uuid, firstname, lastname
        case avatarUrl = "avatar_url"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        uuid = try container.decodeIfPresent(String.self, forKey: .uuid) ?? ""
        firstname = try container.decodeIfPresent(String.self, forKey: .firstname) ?? ""
        lastname = try container.decodeIfPresent(String.self, forKey: .lastname) ?? ""
        avatarUrl = try container.decodeIfPresent(String.self, forKey: .avatarUrl)
    }
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
