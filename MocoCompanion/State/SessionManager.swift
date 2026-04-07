import AppKit
import Foundation
import os

/// Owns user session, profile, avatar, yesterday warning, and offline queue sync.
/// Extracted from AppState to separate session concerns from service wiring.
@Observable
@MainActor
final class SessionManager {
    private let logger = Logger(category: "SessionManager")

    private(set) var currentUserId: Int?
    private(set) var currentUserProfile: MocoUserProfile?
    private(set) var cachedAvatarImage: NSImage?
    var yesterdayWarning: YesterdayWarning?

    /// Mutable box captured by service closures. Updated when currentUserId changes.
    let userIdBox: ValueBox<Int?>

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
        }
    }

    /// Recheck yesterday warning using local data. Called after activity edits/deletes.
    func recheckYesterdayWarning(yesterdayActivities: [MocoActivity]) {
        guard let warning = yesterdayWarning else { return }
        let yesterdayHours = yesterdayActivities.reduce(0.0) { $0 + $1.hours }
        let ratio = yesterdayHours / warning.expectedHours
        if ratio >= YesterdayCheckManager.threshold {
            yesterdayWarning = nil
        } else {
            yesterdayWarning = YesterdayWarning(bookedHours: yesterdayHours, expectedHours: warning.expectedHours)
        }
    }

    /// Sync queued entries after reconnecting. Deduplicates against existing activities.
    func syncQueuedEntries(
        queue: EntryQueue,
        client: (any MocoClientProtocol)?,
        userId: Int?,
        dispatcher: NotificationDispatcher,
        onSynced: () async -> Void
    ) async {
        guard !queue.isEmpty else { return }
        guard let client else { return }
        guard let userId else { return }

        logger.info("Syncing \(queue.count) queued entries")
        var syncedCount = 0

        for entry in queue.entries {
            do {
                let existing = try await client.fetchActivities(from: entry.date, to: entry.date, userId: userId)
                let isDuplicate = existing.contains { activity in
                    activity.project.id == entry.projectId
                    && activity.task.id == entry.taskId
                    && activity.description == entry.description
                }
                if isDuplicate {
                    logger.info("Skipping duplicate queued entry for \(entry.projectName)")
                    queue.remove(id: entry.id)
                    continue
                }
                _ = try await client.createActivity(
                    date: entry.date, projectId: entry.projectId, taskId: entry.taskId,
                    description: entry.description, seconds: entry.seconds, tag: entry.tag
                )
                queue.remove(id: entry.id)
                syncedCount += 1
                logger.info("Synced queued entry for \(entry.projectName)")
            } catch {
                logger.error("Failed to sync queued entry: \(error.localizedDescription)")
                break
            }
        }

        if syncedCount > 0 {
            let message = String(localized: "offline.synced \(syncedCount)")
            dispatcher.send(.projectsRefreshed, message: message)
            await onSynced()
        }
    }
}
