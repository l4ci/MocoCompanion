import Foundation

// MARK: - Session (from GET /session)

struct MocoSession: Codable, Sendable {
    let id: Int
    let uuid: String
}

/// User profile data from GET /users?ids[]=<id>.
struct MocoUserProfile: Codable, Sendable {
    let id: Int
    let firstname: String
    let lastname: String
    let avatarUrl: String?

    enum CodingKeys: String, CodingKey {
        case id, firstname, lastname
        case avatarUrl = "avatar_url"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        firstname = try container.decodeIfPresent(String.self, forKey: .firstname) ?? ""
        lastname = try container.decodeIfPresent(String.self, forKey: .lastname) ?? ""
        avatarUrl = try container.decodeIfPresent(String.self, forKey: .avatarUrl)
    }

    init(id: Int, firstname: String, lastname: String, avatarUrl: String?) {
        self.id = id
        self.firstname = firstname
        self.lastname = lastname
        self.avatarUrl = avatarUrl
    }
}
