import AppKit
import Foundation
import os

/// Owns user session, profile, avatar, and offline queue sync.
/// Extracted from AppState to separate session concerns from service wiring.
@Observable
@MainActor
final class SessionManager {
    private let logger = Logger(category: "SessionManager")

    private(set) var currentUserId: Int?
    private(set) var currentUserProfile: MocoUserProfile?
    private(set) var cachedAvatarImage: NSImage?

    /// Mutable box captured by service closures. Updated when currentUserId changes.
    let userIdBox: ValueBox<Int?>

    var syncState: SyncState?
    var notifications: NotificationDispatcher?

    init(userIdBox: ValueBox<Int?>) {
        self.userIdBox = userIdBox
    }

    func fetchSession(client: (any MocoClientProtocol)?) async {
        guard let client else { return }
        do {
            let session = try await client.fetchSession()
            currentUserId = session.id
            userIdBox.value = session.id
            logger.info("Session: userId=\(session.id)")

            // Fetch profile via /users?ids[]=<id> — works for all users,
            // unlike /users/<id> which requires admin permissions.
            let profile = try await client.fetchUserProfile(userId: session.id)
            currentUserProfile = profile
            logger.info("Profile: \(profile.firstname) \(profile.lastname)")

            if let urlStr = profile.avatarUrl, let url = URL(string: urlStr) {
                do {
                    let (data, _) = try await URLSession.shared.data(from: url)
                    if let image = NSImage(data: data) {
                        cachedAvatarImage = image
                        logger.info("Avatar image cached")
                    }
                } catch {
                    logger.warning("Avatar download failed: \(error.localizedDescription)")
                }
            }
        } catch {
            logger.error("fetchSession failed: \(error.localizedDescription)")
            let mocoError = MocoError.from(error)
            syncState?.setLastError(mocoError)
            notifications?.apiError(mocoError)
        }
    }


}
