import Foundation

/// Closure-based mock for SessionAPI (session, profile, assigned projects).
struct MockSessionAPI: SessionAPI, @unchecked Sendable {
    var fetchSessionHandler: () async throws -> MocoSession = {
        MocoSession(id: 42, uuid: "test-uuid")
    }
    var fetchUserProfileHandler: (Int) async throws -> MocoUserProfile = { id in
        MocoUserProfile(id: id, firstname: "Test", lastname: "User", avatarUrl: nil)
    }
    var fetchAssignedProjectsHandler: (Bool) async throws -> [MocoProject] = { _ in [] }

    func fetchSession() async throws -> MocoSession {
        try await fetchSessionHandler()
    }

    func fetchUserProfile(userId: Int) async throws -> MocoUserProfile {
        try await fetchUserProfileHandler(userId)
    }

    func fetchAssignedProjects(active: Bool) async throws -> [MocoProject] {
        try await fetchAssignedProjectsHandler(active)
    }
}
