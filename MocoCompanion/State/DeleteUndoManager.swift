import Foundation
import os

/// Manages activity deletion with undo support (5-second grace period).
/// Extracted from ActivityService to keep concerns separated.
@Observable
@MainActor
final class DeleteUndoManager {
    private let logger = Logger(category: "DeleteUndoManager")

    // MARK: - Types

    /// A pending delete that can be undone within the grace period.
    struct PendingDelete {
        let activity: MocoActivity
        let isYesterday: Bool
        let task: Task<Void, Never>
    }

    // MARK: - Observable State

    /// The currently pending delete, if any. Observable so the UI can show the undo toast.
    private(set) var pendingDelete: PendingDelete?

    // MARK: - Dependencies

    private let clientFactory: () -> (any ActivityAPI)?
    private let activityService: ActivityService
    private let notificationDispatcher: NotificationDispatcher

    /// Stops the timer before deleting a timed activity.
    var timerStopProvider: (any TimerStopProvider)?

    init(
        clientFactory: @escaping () -> (any ActivityAPI)?,
        activityService: ActivityService,
        notificationDispatcher: NotificationDispatcher
    ) {
        self.clientFactory = clientFactory
        self.activityService = activityService
        self.notificationDispatcher = notificationDispatcher
    }

    // MARK: - Delete with Undo

    func deleteActivity(activityId: Int) async {
        guard clientFactory() != nil else { return }

        // Stop timer if this activity is being timed
        await timerStopProvider?.stopTimerIfActive(activityId: activityId)

        // Capture the activity before removing it locally
        let activity = activityService.todayActivities.first(where: { $0.id == activityId })
            ?? activityService.yesterdayActivities.first(where: { $0.id == activityId })
        let wasYesterday = activityService.yesterdayActivities.contains { $0.id == activityId }

        // Cancel any existing pending delete (execute it immediately)
        await commitPendingDelete()

        // Remove locally for instant visual feedback
        activityService.removeLocal(activityId: activityId)
        notificationDispatcher.entryDeleted()

        guard let activity else {
            // Activity wasn't in local arrays — just delete server-side
            do {
                try await clientFactory()?.deleteActivity(activityId: activityId)
            } catch {
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

        pendingDelete = PendingDelete(activity: activity, isYesterday: wasYesterday, task: deleteTask)
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

        pendingDelete = nil
        logger.info("Undo delete: restored activity \(pending.activity.id)")
    }

    /// Immediately commit the pending delete (called on timeout or before a new delete).
    func commitPendingDelete() async {
        guard let pending = pendingDelete else { return }
        pending.task.cancel()
        pendingDelete = nil
        await executeDelete(activityId: pending.activity.id)
    }

    /// Execute the actual API delete.
    private func executeDelete(activityId: Int) async {
        guard let client = clientFactory() else { return }
        do {
            try await client.deleteActivity(activityId: activityId)
            logger.info("Deleted activity \(activityId) from server")
        } catch {
            handleError(error, label: "deleteActivity")
        }
        // Clear pending if this was the one
        if pendingDelete?.activity.id == activityId {
            pendingDelete = nil
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
