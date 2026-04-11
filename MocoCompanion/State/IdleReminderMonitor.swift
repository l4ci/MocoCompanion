import Foundation
import os

/// Monitors timer state and emits alerts:
/// 1. Idle reminder: no timer for 5+ minutes during working hours (rate-limited to 20min)
/// 2. Forgotten timer: running 3+ hours continuously (once per run)
/// 3. End-of-day summary: total hours at working hours end (once per day)
@MainActor
final class IdleReminderMonitor: PollingMonitor {
    let monitorName = "IdleReminder"

    /// Dynamic poll cadence. When the panel is visible, we tick every 60s so
    /// the idle threshold resolves quickly. When the panel is hidden, bump
    /// to 5 min — the worst case is that an idle reminder surfaces up to 5 min
    /// late, which is fine given the 5-min idle threshold itself. The EOD
    /// check still catches the `hour == hoursEnd` window because any hour is
    /// at least 60 min wide.
    var pollInterval: Duration {
        PanelVisibility.shared.isVisible ? .seconds(60) : .seconds(300)
    }

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
        String(localized: "idle.msg12"),
        String(localized: "idle.msg13"),
        String(localized: "idle.msg14"),
        String(localized: "idle.msg15"),
        String(localized: "idle.msg16"),
        String(localized: "idle.msg17"),
        String(localized: "idle.msg18"),
        String(localized: "idle.msg19"),
        String(localized: "idle.msg20"),
        String(localized: "idle.msg21"),
        String(localized: "idle.msg22"),
        String(localized: "idle.msg23"),
        String(localized: "idle.msg24"),
        String(localized: "idle.msg25"),
        String(localized: "idle.msg26"),
        String(localized: "idle.msg27"),
        String(localized: "idle.msg28"),
        String(localized: "idle.msg29"),
        String(localized: "idle.msg30"),
        String(localized: "idle.msg31"),
        String(localized: "idle.msg32"),
        String(localized: "idle.msg33"),
        String(localized: "idle.msg34"),
        String(localized: "idle.msg35"),
        String(localized: "idle.msg36"),
        String(localized: "idle.msg37"),
        String(localized: "idle.msg38"),
        String(localized: "idle.msg39"),
        String(localized: "idle.msg40"),
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
        let hours = String(format: "%.0f", hoursRunning)
        return MonitorAlert(
            type: .forgottenTimer,
            message: String(localized: "forgotten.message \(hours) \(projectName)"),
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

        let hours = activityService.todayTotalHours
        let message: String
        if hours >= 8 {
            message = String(localized: "eod.fullDay \(String(format: "%.1f", hours))")
        } else if hours >= 4 {
            message = String(localized: "eod.solidDay \(String(format: "%.1f", hours))")
        } else if hours > 0 {
            message = String(localized: "eod.lightDay \(String(format: "%.1f", hours))")
        } else {
            message = String(localized: "eod.noEntries")
        }

        return MonitorAlert(
            type: .endOfDaySummary,
            message: message,
            dedupKey: "IdleReminder:eod",
            dedupStrategy: .perDay
        )
    }
}
