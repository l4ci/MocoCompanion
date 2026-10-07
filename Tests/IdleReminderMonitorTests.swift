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

    @Test("Forgotten reminders rearm for replacement, resume, and task changes", arguments: [0, 1, 2])
    func forgottenReminderUsesSessionIdentity(change: Int) async throws {
        let now = Date(timeIntervalSince1970: 1_770_000_000)
        let start = ISO8601DateFormatter().string(from: now.addingTimeInterval(-5 * 3600))
        let resumed = ISO8601DateFormatter().string(from: now.addingTimeInterval(-4 * 3600))
        var activity = TestFactories.makeActivity(id: 10, timerStartedAt: start)
        var api = MockTimerAPI()
        api.fetchActivitiesHandler = { _, _, _ in [activity] }
        api.createActivityHandler = { _, _, _, _, _, _ in activity }
        api.stopTimerHandler = { id in TestFactories.makeActivity(id: id) }
        api.startTimerHandler = { _ in activity }
        let timer = TimerService(clientFactory: { api }, userIdProvider: { 42 })
        await timer.sync()
        let (_, activities, settings) = makeServices()
        settings.workingDays = []
        let monitor = IdleReminderMonitor(
            timerService: timer, activityService: activities, settings: settings, clock: { now }
        )
        var ledger = DedupLedger()
        let first = try #require(await monitor.check().first { $0.type == .forgottenTimer })
        #expect(ledger.shouldFire(first, now: now))
        ledger.markFired(first, at: now)
        #expect(await monitor.check().isEmpty)

        switch change {
        case 0: // External running-to-running replacement, with the same start time.
            activity = TestFactories.makeActivity(id: 11, timerStartedAt: start)
            await timer.sync()
        case 1: // Pause/resume entirely between polls, keeping the activity ID.
            await timer.pauseTimer()
            activity = TestFactories.makeActivity(id: 10, timerStartedAt: resumed)
            await timer.resumeTimer()
        default: // Task change in the same project.
            activity = TestFactories.makeActivity(id: 10, taskId: 201, timerStartedAt: start)
            _ = await timer.startTimer(projectId: 100, taskId: 201, description: "New task")
        }
        let second = try #require(await monitor.check().first { $0.type == .forgottenTimer })
        #expect(second.dedupKey != first.dedupKey)
        #expect(ledger.shouldFire(second, now: now))
        ledger.markFired(second, at: now)
        #expect(!ledger.shouldFire(second, now: now))
        #expect(await monitor.check().isEmpty)
    }

    @Test("End-of-day summary uses refreshed totals and only refreshes inside the schedule")
    func endOfDayUsesRefreshedTotals() async throws {
        let now = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 5, hour: 17))!
        var fetches = 0
        var api = MockActivityAPI()
        api.fetchActivitiesHandler = { _, _, _ in
            fetches += 1
            return [TestFactories.makeActivity(hours: 8.5)]
        }
        let (timer, _, settings) = makeServices()
        let activities = ActivityService(
            clientFactory: { api }, notificationDispatcher: TestFactories.makeStubDispatcher(),
            userIdProvider: { 42 }
        )
        activities.applyFetchedTodayActivities([TestFactories.makeShadowEntry(hours: 2)])
        settings.workingDays = []
        settings.workingHoursEnd = 17
        let monitor = IdleReminderMonitor(
            timerService: timer, activityService: activities, settings: settings, clock: { now }
        )
        #expect(await monitor.check().isEmpty)
        #expect(fetches == 0)
        settings.workingDays = [Calendar.current.component(.weekday, from: now)]
        settings.workingHoursEnd = 18
        _ = await monitor.check()
        #expect(fetches == 0)
        settings.workingHoursEnd = 17
        let alert = try #require(await monitor.check().first { $0.type == .endOfDaySummary })
        let hours = 8.5.formatted(.number.precision(.fractionLength(1)))
        #expect(alert.message == String(localized: "eod.fullDay \(hours)"))
        #expect(activities.todayTotalHours == 8.5)
        #expect(fetches == 1)
    }

}
