import Foundation
import os

/// Manages activity deletion with undo support (5-second grace period).
/// Extracted from ActivityService to keep concerns separated.
@Observable
@MainActor
final class DeleteUndoManager {
    private let logger = Logger(category: "DeleteUndoManager")
    private static let isoFormatter = ISO8601DateFormatter()

    // MARK: - Types

    /// A pending delete that can be undone within the grace period.
    struct PendingDelete {
        let activity: ShadowEntry
        let isYesterday: Bool
        /// The ShadowEntry that was in the store before we flipped it to
        /// `pendingDelete`. Kept so undo can restore the exact prior row.
        let originalShadow: ShadowEntry?
        let task: Task<Void, Never>
    }

    // MARK: - Observable State

    /// The currently pending delete, if any. Observable so the UI can show the undo toast.
    private(set) var pendingDelete: PendingDelete?

    // MARK: - Dependencies

    private let clientFactory: () -> (any ActivityAPI)?
    private let activityService: ActivityService
    private let shadowEntryStore: ShadowEntryStore
    private let notificationDispatcher: NotificationDispatcher

    /// Stops the timer before deleting a timed activity.
    var timerStopProvider: (any TimerStopProvider)?

    /// Called after any mutation that should fan out to other views (e.g.
    /// the autotracker timeline window). Set by the window owner while the
    /// window is visible; cleared on close.
    var onStoreChanged: (() async -> Void)?

    init(
        clientFactory: @escaping () -> (any ActivityAPI)?,
        activityService: ActivityService,
        shadowEntryStore: ShadowEntryStore,
        notificationDispatcher: NotificationDispatcher
    ) {
        self.clientFactory = clientFactory
        self.activityService = activityService
        self.shadowEntryStore = shadowEntryStore
        self.notificationDispatcher = notificationDispatcher
    }

    // MARK: - Delete with Undo

    func deleteActivity(activityId: Int) async {
        guard clientFactory() != nil else { return }

        // Check if the activity is locked — reject deletion
        let activity = activityService.todayActivities.first(where: { $0.id == activityId })
            ?? activityService.yesterdayActivities.first(where: { $0.id == activityId })
        if let activity, activity.isReadOnly {
            logger.warning("Cannot delete locked/billed entry \(activityId)")
            return
        }

        // Stop timer if this activity is being timed
        await timerStopProvider?.stopTimerIfActive(activityId: activityId)

        let wasYesterday = activityService.yesterdayActivities.contains { $0.id == activityId }

        // Cancel any existing pending delete (execute it immediately)
        await commitPendingDelete()

        // Remove locally for instant visual feedback in TodayView
        activityService.removeLocal(activityId: activityId)
        notificationDispatcher.entryDeleted()

        // Mirror into the shared SQLite store so any other open view (the
        // autotracker timeline window in particular) instantly hides this
        // entry. We flip its syncStatus to .pendingDelete and snapshot the
        // original row so undoDelete can restore the exact prior state.
        let originalShadow = await markShadowPendingDelete(id: activityId)
        await onStoreChanged?()

        guard let activity else {
            // Activity wasn't in local arrays — just delete server-side
            do {
                try await clientFactory()?.deleteActivity(activityId: activityId)
                await shadowDeleteOrLog(id: activityId, label: "deleteActivity (orphan)")
            } catch MocoError.notFound {
                // Server doesn't have it anyway — safe to clear the local tombstone
                logger.info("Activity \(activityId) already gone from server")
                await shadowDeleteOrLog(id: activityId, label: "deleteActivity (orphan, server-404)")
            } catch {
                // Leave the shadow row as .pendingDelete so the next sync can retry.
                handleError(error, label: "deleteActivity")
            }
            return
        }

        // Start a delayed delete — can be undone within 5 seconds
        let deleteTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            await self?.executeDelete(activityId: activityId)
        }

        pendingDelete = PendingDelete(
            activity: activity,
            isYesterday: wasYesterday,
            originalShadow: originalShadow,
            task: deleteTask
        )
    }

    /// Look up the ShadowEntry for `activityId` and flip it to
    /// `pendingDelete`. Returns the pre-flip row for undo. Nil if the row
    /// is not in the store (e.g. hasn't been synced locally yet).
    private func markShadowPendingDelete(id: Int) async -> ShadowEntry? {
        do {
            guard let existing = try await shadowEntryStore.entry(id: id) else {
                return nil
            }
            var updated = existing
            updated.sync.status = .pendingDelete
            updated.sync.localUpdatedAt = Self.isoFormatter.string(from: Date.now)
            try await shadowEntryStore.update(updated)
            return existing
        } catch {
            logger.error("markShadowPendingDelete(\(id)) failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Undo the pending delete — restore the activity to the local array.
    func undoDelete() {
        guard let pending = pendingDelete else { return }
        pending.task.cancel()

        if pending.isYesterday {
            activityService.restoreYesterday(pending.activity)
        } else {
            activityService.restoreToday(pending.activity)
        }

        // Roll back the shadow store flip so the autotracker sees the
        // entry again.
        if let original = pending.originalShadow {
            Task { [weak self] in
                do {
                    try await self?.shadowEntryStore.update(original)
                    await self?.onStoreChanged?()
                } catch {
                    self?.logger.error("undoDelete store restore failed: \(error.localizedDescription)")
                }
            }
        }

        pendingDelete = nil
        logger.info("Undo delete: restored activity \(pending.activity.id ?? 0)")
    }

    /// Immediately commit the pending delete (called on timeout or before a new delete).
    func commitPendingDelete() async {
        guard let pending = pendingDelete else { return }
        pending.task.cancel()
        pendingDelete = nil
        guard let activityId = pending.activity.id else {
            pendingDelete = nil
            return
        }
        await executeDelete(activityId: activityId)
    }

    /// Execute the actual API delete, then hard-remove the shadow row.
    /// The row is already flipped to `.pendingDelete` at this point, so
    /// the autotracker UI is already hiding it. We do not need to
    /// broadcast again on success.
    private func executeDelete(activityId: Int) async {
        guard let client = clientFactory() else { return }
        do {
            try await client.deleteActivity(activityId: activityId)
            logger.info("Deleted activity \(activityId) from server")
            await shadowDeleteOrLog(id: activityId, label: "executeDelete")
        } catch MocoError.notFound {
            // Server doesn't have it anyway — safe to clear the local tombstone
            logger.info("Activity \(activityId) already gone from server")
            await shadowDeleteOrLog(id: activityId, label: "executeDelete (server-404)")
        } catch {
            // Leave the shadow row as .pendingDelete so the next sync can retry.
            handleError(error, label: "deleteActivity")
        }
        if pendingDelete?.activity.id == activityId {
            pendingDelete = nil
        }
    }

    /// Hard-delete the shadow row after a successful (or 404) server delete.
    /// Failure here means the row stays as `.pendingDelete` indefinitely —
    /// invisible in the UI but blocking the row id. Log explicitly so it
    /// shows up in post-mortems; the next sync pass will retry.
    private func shadowDeleteOrLog(id: Int, label: String) async {
        do {
            try await shadowEntryStore.delete(id: id)
        } catch {
            logger.error("\(label) shadow-store delete failed (id=\(id)): \(error.localizedDescription)")
            Task { await AppLogger.shared.app("\(label) shadow-store delete failed: \(error.localizedDescription)", level: .error, context: "DeleteUndoManager") }
        }
    }

    // MARK: - Private

    private func handleError(_ error: any Error, label: String) {
        let mocoError = MocoError.from(error)
        notificationDispatcher.apiError(mocoError)
        logger.error("\(label) failed: \(error.localizedDescription)")
        Task { await AppLogger.shared.app("\(label) failed: \(error.localizedDescription)", level: .error, context: "DeleteUndoManager") }
    }
}
