import Testing
import Foundation
@testable import MocoCompanion

/// Covers `IdleReminderMonitor`'s two once-off checks:
/// - `checkForgottenTimer`: fires once a running timer has been going 3+
///   hours, not before, and only once per continuous run.
/// - `checkEndOfDay`: stays silent outside the configured working
///   weekday/hoursEnd window.
///
/// Both checks read `Calendar.current` components off an injected `clock`
/// closure, so tests fix `clock` to a known reference date instead of
/// depending on when the suite happens to run.
@MainActor
@Suite("IdleReminderMonitor")
struct IdleReminderMonitorTests {

    // MARK: - Helpers

    /// Build a TimerService + ActivityService + SettingsStore trio wired
    /// with in-memory/mock backends, following the pattern used by
    /// TimerServiceTests/TodayViewModelTests.
    private func makeServices() -> (TimerService, ActivityService, SettingsStore) {
        let timerAPI = MockTimerAPI()
        let activityAPI = MockActivityAPI()
        let dispatcher = NotificationDispatcher(isEnabledCheck: { _ in false })

        let timerService = TimerService(clientFactory: { timerAPI }, userIdProvider: { 42 })
        let activityService = ActivityService(
            clientFactory: { activityAPI },
            notificationDispatcher: dispatcher,
            userIdProvider: { 42 }
        )
        let settings = SettingsStore()
        return (timerService, activityService, settings)
    }

    /// Build a TimerService whose `startTimer` call yields a running
    /// activity with `timerStartedAt` set to `hoursAgo` hours before
    /// `referenceNow`. `currentActivity` is `private(set)`, so a running
    /// timer can only be produced by actually driving `startTimer`.
    private func makeRunningTimerService(hoursAgo: Double, referenceNow: Date) -> TimerService {
        var timerAPI = MockTimerAPI()
        let startedAt = ISO8601DateFormatter().string(from: referenceNow.addingTimeInterval(-hoursAgo * 3600))
        timerAPI.createActivityHandler = { date, projectId, taskId, desc, seconds, tag in
            TestFactories.makeActivity(
                id: 10, date: date, projectId: projectId, taskId: taskId,
                seconds: seconds, description: desc, tag: tag ?? "",
                timerStartedAt: startedAt
            )
        }
        return TimerService(clientFactory: { timerAPI }, userIdProvider: { 42 })
    }

    // MARK: - Forgotten Timer

    @Test("checkForgottenTimer does not fire before the 3-hour threshold")
    func forgottenTimerDoesNotFireBeforeThreshold() async {
        let referenceNow = Date(timeIntervalSince1970: 1_770_000_000) // fixed reference instant
        let (_, activityService, settings) = makeServices()
        let runningTimerService = makeRunningTimerService(hoursAgo: 2, referenceNow: referenceNow)
        _ = await runningTimerService.startTimer(projectId: 100, taskId: 200, description: "Working")

        // Isolate from the end-of-day check entirely.
        settings.workingDays = []

        let monitor = IdleReminderMonitor(
            timerService: runningTimerService,
            activityService: activityService,
            settings: settings,
            clock: { referenceNow }
        )

        let alerts = await monitor.check()
        #expect(!alerts.contains { $0.type == .forgottenTimer })
    }

    @Test("checkForgottenTimer fires once past the 3-hour threshold, not again on the next poll")
    func forgottenTimerFiresOncePastThreshold() async {
        let referenceNow = Date(timeIntervalSince1970: 1_770_000_000)
        let (_, activityService, settings) = makeServices()
        let runningTimerService = makeRunningTimerService(hoursAgo: 3.5, referenceNow: referenceNow)
        _ = await runningTimerService.startTimer(projectId: 100, taskId: 200, description: "Working")

        settings.workingDays = [] // isolate from end-of-day

        let monitor = IdleReminderMonitor(
            timerService: runningTimerService,
            activityService: activityService,
            settings: settings,
            clock: { referenceNow }
        )

        let firstAlerts = await monitor.check()
        #expect(firstAlerts.contains { $0.type == .forgottenTimer })

        let secondAlerts = await monitor.check()
        #expect(!secondAlerts.contains { $0.type == .forgottenTimer })
    }

    // MARK: - End of Day

    @Test("checkEndOfDay is silent when today is not a configured working day")
    func endOfDaySilentOnNonWorkingDay() async {
        let calendar = Calendar.current
        let referenceNow = calendar.date(from: DateComponents(year: 2026, month: 1, day: 5, hour: 17, minute: 0, second: 0))!
        let weekday = calendar.component(.weekday, from: referenceNow)
        let hour = calendar.component(.hour, from: referenceNow)

        let (timerService, activityService, settings) = makeServices()
        // Hour matches, but weekday is deliberately excluded.
        settings.workingHoursEnd = hour
        settings.workingDays = Set(1...7).subtracting([weekday])

        let monitor = IdleReminderMonitor(
            timerService: timerService,
            activityService: activityService,
            settings: settings,
            clock: { referenceNow }
        )

        let alerts = await monitor.check()
        #expect(!alerts.contains { $0.type == .endOfDaySummary })
    }

    @Test("checkEndOfDay is silent outside the configured hoursEnd window")
    func endOfDaySilentOutsideHoursEndWindow() async {
        let calendar = Calendar.current
        let referenceNow = calendar.date(from: DateComponents(year: 2026, month: 1, day: 5, hour: 17, minute: 0, second: 0))!
        let weekday = calendar.component(.weekday, from: referenceNow)
        let hour = calendar.component(.hour, from: referenceNow)

        let (timerService, activityService, settings) = makeServices()
        // Weekday matches, but hoursEnd is deliberately offset.
        settings.workingDays = [weekday]
        settings.workingHoursEnd = hour + 1

        let monitor = IdleReminderMonitor(
            timerService: timerService,
            activityService: activityService,
            settings: settings,
            clock: { referenceNow }
        )

        let alerts = await monitor.check()
        #expect(!alerts.contains { $0.type == .endOfDaySummary })
    }

    @Test("checkEndOfDay fires when both weekday and hoursEnd match the schedule")
    func endOfDayFiresWhenScheduleMatches() async {
        let calendar = Calendar.current
        let referenceNow = calendar.date(from: DateComponents(year: 2026, month: 1, day: 5, hour: 17, minute: 0, second: 0))!
        let weekday = calendar.component(.weekday, from: referenceNow)
        let hour = calendar.component(.hour, from: referenceNow)

        let (timerService, activityService, settings) = makeServices()
        settings.workingDays = [weekday]
        settings.workingHoursEnd = hour
        activityService.applyFetchedTodayActivities([
            TestFactories.makeShadowEntry(hours: 6.0)
        ])

        let monitor = IdleReminderMonitor(
            timerService: timerService,
            activityService: activityService,
            settings: settings,
            clock: { referenceNow }
        )

        let alerts = await monitor.check()
        #expect(alerts.contains { $0.type == .endOfDaySummary })
    }
}
