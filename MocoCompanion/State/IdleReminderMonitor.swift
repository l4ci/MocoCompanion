import Foundation
import os

/// Monitors timer state and emits alerts:
/// 1. Idle reminder: no timer for 5+ minutes during working hours (rate-limited to 20min)
/// 2. Forgotten timer: running 3+ hours continuously (once per run)
/// 3. End-of-day summary: total hours at working hours end (once per day)
@MainActor
final class IdleReminderMonitor: PollingMonitor {
    let monitorName = "IdleReminder"
    let pollInterval: Duration = .seconds(60)

    private let timerService: TimerService
    private let activityService: ActivityService
    private let settings: SettingsStore

    /// When the timer last transitioned to idle.
    private var idleSince: Date?
    /// Tracks whether forgotten-timer has fired this continuous run.
    private var forgottenTimerFired = false

    private static let messages: [String] = [
        String(localized: "idle.msg1"),
        String(localized: "idle.msg2"),
        String(localized: "idle.msg3"),
        String(localized: "idle.msg4"),
        String(localized: "idle.msg5"),
        String(localized: "idle.msg6"),
        String(localized: "idle.msg7"),
        String(localized: "idle.msg8"),
        String(localized: "idle.msg9"),
        String(localized: "idle.msg10"),
        String(localized: "idle.msg11"),
    ]

    init(timerService: TimerService, activityService: ActivityService, settings: SettingsStore) {
        self.timerService = timerService
        self.activityService = activityService
        self.settings = settings
        // Seed idleSince based on current state
        if timerService.timerState == .idle {
            idleSince = Date()
        }
    }

    var isActive: Bool { true } // Always polls — checks are internally gated

    func check() async -> [MonitorAlert] {
        var alerts: [MonitorAlert] = []

        // End-of-day summary (check regardless of timer state)
        if let eod = checkEndOfDay() {
            await activityService.refreshTodayStats()
            alerts.append(eod)
        }

        // Forgotten timer (3h+)
        if let forgotten = checkForgottenTimer() {
            alerts.append(forgotten)
        }

        // Update idle tracking
        switch timerService.timerState {
        case .idle:
            if idleSince == nil {
                idleSince = Date()
                forgottenTimerFired = false
            }
        case .running, .paused:
            if idleSince != nil { idleSince = nil }
            return alerts // Don't check idle reminders when timer is active
        }

        // Working hours gate for idle reminders
        guard settings.schedule.isWithinWorkingHours(
            weekday: Calendar.current.component(.weekday, from: Date()),
            hour: Calendar.current.component(.hour, from: Date())
        ) else { return alerts }

        // Idle 5+ minutes
        if let start = idleSince, Date().timeIntervalSince(start) / 60 >= 5 {
            let msg = Self.messages.randomElement() ?? String(localized: "idle.default")
            alerts.append(MonitorAlert(
                type: .idleReminder,
                message: msg,
                dedupKey: "IdleReminder:idle",
                dedupStrategy: .rateLimited(20 * 60)
            ))
        }

        return alerts
    }

    func resetSession() {
        idleSince = nil
        forgottenTimerFired = false
    }

    // MARK: - Private Checks

    private func checkForgottenTimer() -> MonitorAlert? {
        guard case .running(_, let projectName) = timerService.timerState else { return nil }
        guard !forgottenTimerFired else { return nil }
        guard let activity = timerService.currentActivity,
              let startedAt = activity.timerStartedAt,
              let start = DateUtilities.parseISO8601(startedAt) else { return nil }

        let hoursRunning = Date().timeIntervalSince(start) / 3600.0
        guard hoursRunning >= 3 else { return nil }

        forgottenTimerFired = true
        return MonitorAlert(
            type: .forgottenTimer,
            message: String(format: "Timer running for %.0fh on %@. Still working?", hoursRunning, projectName),
            dedupKey: "IdleReminder:forgotten",
            dedupStrategy: .once
        )
    }

    private func checkEndOfDay() -> MonitorAlert? {
        let now = Date()
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: now)
        let hour = cal.component(.hour, from: now)
        let schedule = settings.schedule

        guard schedule.workingDays.contains(weekday) else { return nil }
        guard hour == schedule.hoursEnd else { return nil }

        return MonitorAlert(
            type: .endOfDaySummary,
            message: String(format: "You tracked %.1fh today (%.0f%% billable)",
                            activityService.todayTotalHours, activityService.todayBillablePercentage),
            dedupKey: "IdleReminder:eod",
            dedupStrategy: .perDay
        )
    }
}
