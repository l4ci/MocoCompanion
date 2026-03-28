import Foundation
import UserNotifications
import os

/// Unified notification dispatch — single entry point for all app notifications.
/// Routes all notifications to macOS system notifications (Notification Center).
/// Checks SettingsStore for enabled state before dispatching.
@MainActor
final class NotificationDispatcher {
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
