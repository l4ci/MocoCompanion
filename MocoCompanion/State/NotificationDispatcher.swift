import Foundation
import UserNotifications
import os

/// Abstraction for notification dispatch — allows test doubles.
@MainActor
protocol NotificationSending {
    func send(_ type: NotificationCatalog.NotificationType, message: String, userInfo: [String: String])
}

extension NotificationSending {
    func send(_ type: NotificationCatalog.NotificationType, message: String) {
        send(type, message: message, userInfo: [:])
    }
}

/// Unified notification dispatch — single entry point for all app notifications.
/// Routes all notifications to macOS system notifications (Notification Center).
/// Checks SettingsStore for enabled state before dispatching.
@MainActor
final class NotificationDispatcher: NotificationSending {
    private let logger = Logger(category: "Notifications")
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    // MARK: - Dependencies

    private let isEnabledCheck: (NotificationCatalog.NotificationType) -> Bool

    init(isEnabledCheck: @escaping (NotificationCatalog.NotificationType) -> Bool = { _ in true }) {
        self.isEnabledCheck = isEnabledCheck
    }

    // MARK: - Single Entry Point

    /// Send a notification via macOS Notification Center.
    /// Checks enabled state before dispatching.
    func send(_ type: NotificationCatalog.NotificationType, message: String, userInfo: [String: String] = [:]) {
        guard isEnabledCheck(type) else {
            logger.debug("Notification disabled: \(type.rawValue)")
            return
        }

        postSystemNotification(type: type, message: message, userInfo: userInfo)
    }

    // MARK: - Notification Actions

    /// Action identifier for "Open Autotracker" button on notifications.
    nonisolated static let openAutotrackerActionId = "openAutotracker"
    /// Category for notifications that offer an "Open Autotracker" action.
    nonisolated static let autotrackerCategoryId = "autotrackerCategory"

    // MARK: - System Notifications

    /// Request permission and register notification categories. Called once on app launch.
    static func requestAuthorization() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                Logger(category: "Notifications").error("Notification authorization failed: \(error.localizedDescription)")
            }
        }

        // Register category with "Open Autotracker" action
        let openAction = UNNotificationAction(
            identifier: openAutotrackerActionId,
            title: "Open Autotracker",
            options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: autotrackerCategoryId,
            actions: [openAction],
            intentIdentifiers: []
        )
        center.setNotificationCategories([category])
    }

    // MARK: - Private

    private func postSystemNotification(type: NotificationCatalog.NotificationType, message: String, userInfo: [String: String] = [:]) {
        let content = UNMutableNotificationContent()
        content.title = type.label
        content.body = message
        content.sound = .default

        // Attach "Open Autotracker" action for relevant notification types
        if type == .endOfDaySummary || type == .yesterdayUnderBooked {
            content.categoryIdentifier = Self.autotrackerCategoryId
            // Embed the target date so the action handler can navigate there
            let targetDate: Date
            if type == .yesterdayUnderBooked {
                targetDate = Calendar.current.date(byAdding: .day, value: -1, to: Date.now) ?? Date.now
            } else {
                targetDate = Date.now
            }
            content.userInfo["targetDate"] = Self.dateFormatter.string(from: targetDate)
        }
        if !userInfo.isEmpty {
            for (k, v) in userInfo { content.userInfo[k] = v }
        }

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
        let formatted = "\(hours.formatted(.number.precision(.fractionLength(1))))h"
        send(.manualEntry, message: "Booked \(formatted) for \(projectName)")
    }

    func entryDuplicated(projectName: String, hours: Double) {
        let formatted = "\(hours.formatted(.number.precision(.fractionLength(1))))h"
        send(.activityDuplicated, message: "Duplicated \(formatted) for \(projectName)")
    }

    func favoritesLimitReached() {
        send(.favoritesLimitReached, message: String(localized: "notification.favoritesLimitReached"))
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
