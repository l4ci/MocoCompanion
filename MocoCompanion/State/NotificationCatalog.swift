import Foundation

/// Defines every notification the app can produce, with metadata for display and settings.
///
/// Each `NotificationType` knows:
/// - Whether it's dismissible (user can toggle it off) or persistent (always shown)
/// - Its default enabled state
/// - Where it appears (in-app toast, system notification, or persistent banner)
/// - Auto-dismiss duration for toasts
enum NotificationCatalog {

    /// Display channel for a notification.
    enum Channel: String, Codable, Sendable {
        /// macOS system notification (Notification Center).
        case system
    }

    /// Visual style for toast/banner.
    enum Style: String, Codable, Sendable {
        case info
        case success
        case warning
        case error
    }

    /// All notification types the app supports.
    enum NotificationType: String, CaseIterable, Identifiable, Sendable {
        // Timer lifecycle (in-app toasts)
        case timerStarted
        case timerResumed
        case timerStopped
        case timerContinued

        // Activity management (in-app toasts)
        case manualEntry
        case activityDuplicated
        case activityDeleted
        case descriptionUpdated
        case projectsRefreshed
        case favoritesLimitReached

        // Background alerts (system notifications)
        case idleReminder
        case forgottenTimer
        case endOfDaySummary

        // Budget warnings (system notifications)
        case budgetProjectWarning
        case budgetTaskWarning

        // Persistent banners (not toggleable)
        case yesterdayUnderBooked
        case apiError

        var id: String { rawValue }

        /// Human-readable label for the settings UI.
        var label: String {
            switch self {
            case .timerStarted: return String(localized: "notifLabel.timerStarted")
            case .timerResumed: return String(localized: "notifLabel.timerResumed")
            case .timerStopped: return String(localized: "notifLabel.timerStopped")
            case .timerContinued: return String(localized: "notifLabel.timerContinued")
            case .manualEntry: return String(localized: "notifLabel.manualEntry")
            case .activityDuplicated: return String(localized: "notifLabel.activityDuplicated")
            case .activityDeleted: return String(localized: "notifLabel.activityDeleted")
            case .descriptionUpdated: return String(localized: "notifLabel.descriptionUpdated")
            case .projectsRefreshed: return String(localized: "notifLabel.projectsRefreshed")
            case .favoritesLimitReached: return String(localized: "notifLabel.favoritesLimitReached")
            case .idleReminder: return String(localized: "notifLabel.idleReminder")
            case .forgottenTimer: return String(localized: "notifLabel.forgottenTimer")
            case .endOfDaySummary: return String(localized: "notifLabel.endOfDaySummary")
            case .budgetProjectWarning: return String(localized: "notifLabel.budgetProjectWarning")
            case .budgetTaskWarning: return String(localized: "notifLabel.budgetTaskWarning")
            case .yesterdayUnderBooked: return String(localized: "notifLabel.yesterdayUnderBooked")
            case .apiError: return String(localized: "notifLabel.apiError")
            }
        }

        /// Description shown in settings.
        var settingsDescription: String {
            switch self {
            case .timerStarted: return String(localized: "notifDesc.timerStarted")
            case .timerResumed: return String(localized: "notifDesc.timerResumed")
            case .timerStopped: return String(localized: "notifDesc.timerStopped")
            case .timerContinued: return String(localized: "notifDesc.timerContinued")
            case .manualEntry: return String(localized: "notifDesc.manualEntry")
            case .activityDuplicated: return String(localized: "notifDesc.activityDuplicated")
            case .activityDeleted: return String(localized: "notifDesc.activityDeleted")
            case .descriptionUpdated: return String(localized: "notifDesc.descriptionUpdated")
            case .projectsRefreshed: return String(localized: "notifDesc.projectsRefreshed")
            case .favoritesLimitReached: return String(localized: "notifDesc.favoritesLimitReached")
            case .idleReminder: return String(localized: "notifDesc.idleReminder")
            case .forgottenTimer: return String(localized: "notifDesc.forgottenTimer")
            case .endOfDaySummary: return String(localized: "notifDesc.endOfDaySummary")
            case .budgetProjectWarning: return String(localized: "notifDesc.budgetProjectWarning")
            case .budgetTaskWarning: return String(localized: "notifDesc.budgetTaskWarning")
            case .yesterdayUnderBooked: return String(localized: "notifDesc.yesterdayUnderBooked")
            case .apiError: return String(localized: "notifDesc.apiError")
            }
        }

        /// Where this notification appears.
        var channel: Channel { .system }

        /// Visual style.
        var style: Style {
            switch self {
            case .timerStarted, .timerResumed, .timerContinued: return .success
            case .timerStopped: return .info
            case .manualEntry, .activityDuplicated: return .success
            case .activityDeleted: return .warning
            case .descriptionUpdated, .projectsRefreshed: return .info
            case .favoritesLimitReached: return .warning
            case .idleReminder, .forgottenTimer, .endOfDaySummary: return .info
            case .budgetProjectWarning, .budgetTaskWarning: return .warning
            case .yesterdayUnderBooked: return .warning
            case .apiError: return .error
            }
        }

        /// SF Symbol name.
        var iconName: String {
            switch self {
            case .timerStarted, .timerResumed, .timerContinued: return "play.circle.fill"
            case .timerStopped: return "stop.circle.fill"
            case .manualEntry: return "clock.badge.checkmark"
            case .activityDuplicated: return "doc.on.doc.fill"
            case .activityDeleted: return "trash.circle.fill"
            case .descriptionUpdated: return "pencil.circle.fill"
            case .projectsRefreshed: return "arrow.clockwise.circle.fill"
            case .favoritesLimitReached: return "star.slash.fill"
            case .idleReminder: return "clock.badge.exclamationmark"
            case .forgottenTimer: return "timer"
            case .endOfDaySummary: return "chart.bar.fill"
            case .budgetProjectWarning, .budgetTaskWarning: return "exclamationmark.triangle.fill"
            case .yesterdayUnderBooked: return "exclamationmark.triangle.fill"
            case .apiError: return "exclamationmark.triangle.fill"
            }
        }

        /// Whether the user can toggle this notification on/off.
        /// Yesterday and API error notifications are always active.
        var isDismissible: Bool {
            switch self {
            case .yesterdayUnderBooked, .apiError: return false
            default: return true
            }
        }

        /// Default enabled state. Persistent notifications are always enabled.
        var defaultEnabled: Bool {
            switch self {
            case .descriptionUpdated, .projectsRefreshed: return false
            default: return true
            }
        }

        /// Grouping for settings UI.
        var settingsGroup: SettingsGroup {
            switch self {
            case .timerStarted, .timerResumed, .timerStopped, .timerContinued:
                return .timer
            case .activityDeleted, .descriptionUpdated, .projectsRefreshed, .manualEntry, .activityDuplicated, .favoritesLimitReached:
                return .activity
            case .idleReminder, .forgottenTimer, .endOfDaySummary:
                return .reminders
            case .budgetProjectWarning, .budgetTaskWarning:
                return .budget
            case .yesterdayUnderBooked, .apiError:
                return .alerts
            }
        }
    }

    /// Grouping for the settings notification list.
    enum SettingsGroup: String, CaseIterable {
        case timer
        case activity
        case reminders
        case budget
        case alerts

        var label: String {
            switch self {
            case .timer: return String(localized: "notifGroup.timer")
            case .activity: return String(localized: "notifGroup.activity")
            case .reminders: return String(localized: "notifGroup.reminders")
            case .budget: return String(localized: "notifGroup.budget")
            case .alerts: return String(localized: "notifGroup.alerts")
            }
        }

        var types: [NotificationType] {
            NotificationType.allCases.filter { $0.settingsGroup == self }
        }
    }
}
