import Foundation
import os

/// Syncs queued offline entries to the Moco API after reconnection.
/// Deduplicates by checking existing activities for each entry date — prevents
/// double-booking if the same entry was created via another client while offline.
///
/// Extracted from SessionManager, which owns session identity. Sync logic is a
/// separate responsibility.
@MainActor
final class OfflineSyncService {
    private let logger = Logger(category: "OfflineSync")
    private let clientFactory: () -> (any MocoClientProtocol)?

    init(clientFactory: @escaping () -> (any MocoClientProtocol)?) {
        self.clientFactory = clientFactory
    }

    /// Sync all queued entries. Removes successfully synced or duplicate entries from the queue.
    /// Calls `onSynced` with the count of newly created entries (>0 only).
    func sync(
        queue: EntryQueue,
        userId: Int,
        onSynced: @escaping (Int) async -> Void
    ) async {
        guard !queue.isEmpty else { return }
        guard let client = clientFactory() else { return }

        logger.info("Syncing \(queue.count) queued entries for userId=\(userId)")
        var syncedCount = 0
        var failedCount = 0

        // Coalesce the duplicate check by fetching each distinct date
        // exactly once. Previously an N-entry queue with all-same-date did
        // N full activity fetches — quadratic in the worst case.
        var existingByDate: [String: [MocoActivity]] = [:]

        for entry in queue.entries {
            do {
                let existing: [MocoActivity]
                if let cached = existingByDate[entry.date] {
                    existing = cached
                } else {
                    let fetched = try await client.fetchActivities(
                        from: entry.date,
                        to: entry.date,
                        userId: userId
                    )
                    existingByDate[entry.date] = fetched
                    existing = fetched
                }

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
                // We just created an activity that future entries in this
                // batch might duplicate — invalidate the date cache so
                // subsequent entries on the same day refetch.
                existingByDate.removeValue(forKey: entry.date)
                logger.info("Synced queued entry for \(entry.projectName)")
            } catch {
                logger.error("Failed to sync queued entry: \(error.localizedDescription)")
                failedCount += 1
                continue
            }
        }

        if failedCount > 0 {
            logger.warning("Sync complete: \(syncedCount) succeeded, \(failedCount) failed (kept in queue for retry)")
        }
        if syncedCount > 0 {
            await onSynced(syncedCount)
        }
    }
}
