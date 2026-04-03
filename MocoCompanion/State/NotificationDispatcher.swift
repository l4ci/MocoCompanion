import Foundation
import UserNotifications
import os

/// Abstraction for notification dispatch — allows test doubles.
@MainActor
protocol NotificationSending {
    func send(_ type: NotificationCatalog.NotificationType, message: String)
}

/// Unified notification dispatch — single entry point for all app notifications.
/// Routes all notifications to macOS system notifications (Notification Center).
/// Checks SettingsStore for enabled state before dispatching.
@MainActor
final class NotificationDispatcher: NotificationSending {
    private let logger = Logger(category: "Notifications")

    // MARK: - Dependencies

    private let isEnabledCheck: (NotificationCatalog.NotificationType) -> Bool

    init(isEnabledCheck: @escaping (NotificationCatalog.NotificationType) -> Bool = { _ in true }) {
        self.isEnabledCheck = isEnabledCheck
    }

    // MARK: - Single Entry Point

    /// Send a notification via macOS Notification Center.
    /// Checks enabled state before dispatching.
    func send(_ type: NotificationCatalog.NotificationType, message: String) {
        guard isEnabledCheck(type) else {
            logger.debug("Notification disabled: \(type.rawValue)")
            return
        }

        postSystemNotification(type: type, message: message)
    }

    // MARK: - System Notifications

    /// Request permission to show system notifications. Called once on app launch.
    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                Logger(category: "Notifications").error("Notification authorization failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Private

    private func postSystemNotification(type: NotificationCatalog.NotificationType, message: String) {
        let content = UNMutableNotificationContent()
        content.title = type.label
        content.body = message
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "\(type.rawValue)-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        Task {
            do {
                try await UNUserNotificationCenter.current().add(request)
                logger.info("Notification: \(type.rawValue) — \(message)")
            } catch {
                logger.error("Failed to post notification: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Convenience Methods

extension NotificationDispatcher {
    func timerStarted(projectName: String) {
        send(.timerStarted, message: String(localized: "notification.timerStarted") + " " + projectName)
    }

    func timerStopped(projectName: String? = nil) {
        let msg = projectName.map { String(localized: "notification.timerStopped") + " " + $0 } ?? String(localized: "notification.timerStopped")
        send(.timerStopped, message: msg)
    }

    func timerPaused(projectName: String) {
        send(.timerStopped, message: String(localized: "notification.timerStopped") + " " + projectName)
    }

    func timerResumed(projectName: String) {
        send(.timerResumed, message: String(localized: "notification.timerResumed") + " " + projectName)
    }

    func timerContinued(projectName: String) {
        send(.timerContinued, message: String(localized: "notification.timerContinued") + " " + projectName)
    }

    func entryUpdated() {
        send(.descriptionUpdated, message: String(localized: "notification.entryUpdated"))
    }

    func entryDeleted() {
        send(.activityDeleted, message: String(localized: "notification.entryDeleted"))
    }

    func descriptionUpdated() {
        send(.descriptionUpdated, message: String(localized: "notification.descriptionUpdated"))
    }

    func manualEntry(projectName: String, hours: Double) {
        let formatted = String(format: "%.1fh", hours)
        send(.manualEntry, message: "Booked \(formatted) for \(projectName)")
    }

    func entryDuplicated(projectName: String, hours: Double) {
        let formatted = String(format: "%.1fh", hours)
        send(.activityDuplicated, message: "Duplicated \(formatted) for \(projectName)")
    }

    func apiError(_ error: MocoError) {
        send(.apiError, message: error.errorDescription ?? "Unknown error")
    }

    func budgetWarning(projectName: String, badge: BudgetBadge) {
        switch badge {
        case .taskCritical:
            send(.budgetTaskWarning, message: String(localized: "notification.budgetTaskWarning") + " " + projectName)
        case .projectCritical, .projectWarning:
            send(.budgetProjectWarning, message: String(localized: "notification.budgetProjectWarning") + " " + projectName)
        case .none:
            break
        }
    }
}
