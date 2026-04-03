import Testing
import Foundation

@Suite("YesterdayCheckManager")
struct YesterdayCheckManagerTests {

    // MARK: - Helpers

    /// Compute yesterday's date string and weekday for test assertions.
    private static var yesterday: (date: Date, dateString: String, weekday: Int) {
        let cal = Calendar.current
        let y = cal.date(byAdding: .day, value: -1, to: Date())!
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return (y, formatter.string(from: y), cal.component(.weekday, from: y))
    }

    /// Whether yesterday is a weekday (Mon-Fri).
    private static var yesterdayIsWeekday: Bool {
        let wd = yesterday.weekday
        return wd >= 2 && wd <= 6
    }

    @MainActor
    private func makeManager(
        api: MockYesterdayAPI? = MockYesterdayAPI(),
        isConfigured: Bool = true,
        userIdProvider: @escaping () -> Int? = { 42 },
        warningCapture: @escaping (YesterdayWarning?) -> Void = { _ in }
    ) -> YesterdayCheckManager {
        let settings = SettingsStore()
        // SettingsStore.isConfigured depends on subdomain + apiKey being non-empty.
        if isConfigured {
            settings.subdomain = "test"
            settings.apiKey = "test-key"
        }
        return YesterdayCheckManager(
            settings: settings,
            clientFactory: { api },
            userIdProvider: userIdProvider,
            setWarning: warningCapture
        )
    }

    // MARK: - Nil Client

    @Test("check returns empty when clientFactory returns nil")
    @MainActor func nilClientReturnsEmpty() async {
        let manager = makeManager(api: nil)
        let alerts = await manager.check()
        #expect(alerts.isEmpty)
    }

    // MARK: - No Employment Data

    @Test("check returns empty when no employments exist")
    @MainActor func noEmploymentsReturnsEmpty() async {
        var api = MockYesterdayAPI()
        api.fetchEmploymentsHandler = { _ in [] }
        let manager = makeManager(api: api)
        let alerts = await manager.check()
        #expect(alerts.isEmpty)
    }

    // MARK: - Under-booked (alert path)

    @Test("check returns alert when booked hours below 85% threshold")
    @MainActor func underBookedReturnsAlert() async {
        // This test only produces an alert if yesterday was a weekday.
        guard Self.yesterdayIsWeekday else { return }

        let yStr = Self.yesterday.dateString
        var capturedWarning: YesterdayWarning?

        var api = MockYesterdayAPI()
        // 8h expected (4+4)
        api.fetchEmploymentsHandler = { _ in
            [TestFactories.makeEmployment()]
        }
        // No absences
        api.fetchSchedulesHandler = { _, _ in [] }
        // Only 3h booked → 3/8 = 37.5% < 85%
        api.fetchActivitiesHandler = { from, to, userId in
            [TestFactories.makeActivity(date: yStr, seconds: 10800, hours: 3.0)]
        }

        let manager = makeManager(api: api, warningCapture: { capturedWarning = $0 })
        let alerts = await manager.check()

        #expect(alerts.count == 1)
        #expect(alerts.first?.type == .yesterdayUnderBooked)
        #expect(capturedWarning != nil)
        #expect(capturedWarning?.bookedHours == 3.0)
    }

    // MARK: - Sufficiently booked (no alert)

    @Test("check returns empty when booked hours meet 85% threshold")
    @MainActor func sufficientlyBookedReturnsEmpty() async {
        guard Self.yesterdayIsWeekday else { return }

        let yStr = Self.yesterday.dateString
        var capturedWarning: YesterdayWarning?

        var api = MockYesterdayAPI()
        api.fetchEmploymentsHandler = { _ in
            [TestFactories.makeEmployment()]
        }
        api.fetchSchedulesHandler = { _, _ in [] }
        // 7h booked → 7/8 = 87.5% >= 85%
        api.fetchActivitiesHandler = { _, _, _ in
            [TestFactories.makeActivity(date: yStr, seconds: 25200, hours: 7.0)]
        }

        let manager = makeManager(api: api, warningCapture: { capturedWarning = $0 })
        let alerts = await manager.check()

        #expect(alerts.isEmpty)
        // Warning should be cleared (set to nil)
        #expect(capturedWarning == nil)
    }

    // MARK: - Weekend Skip

    @Test("check skips weekends — returns empty regardless of employment data")
    @MainActor func weekendSkipReturnsEmpty() async {
        // If yesterday is a weekend, this tests the guard naturally.
        // If yesterday is a weekday, this documents that the weekend guard
        // can't be triggered today and tests the non-skip path instead.
        guard !Self.yesterdayIsWeekday else {
            // On weekdays, verify that the test for "no employments" still works
            // (we can't trigger the weekend guard when yesterday is a weekday)
            var api = MockYesterdayAPI()
            api.fetchEmploymentsHandler = { _ in [] }
            let manager = makeManager(api: api)
            let alerts = await manager.check()
            #expect(alerts.isEmpty)
            return
        }

        // Yesterday IS a weekend day — the guard should skip before any API call
        var fetchEmploymentsCalled = false
        var api = MockYesterdayAPI()
        api.fetchEmploymentsHandler = { _ in
            fetchEmploymentsCalled = true
            return [TestFactories.makeEmployment()]
        }
        let manager = makeManager(api: api)
        let alerts = await manager.check()

        #expect(alerts.isEmpty)
        // On a weekend, employments should never be fetched
        #expect(!fetchEmploymentsCalled)
    }

    // MARK: - Absence Skip

    @Test("check skips days with absences — returns empty and clears warning")
    @MainActor func absenceSkipReturnsEmpty() async {
        guard Self.yesterdayIsWeekday else { return }

        let yStr = Self.yesterday.dateString
        var capturedWarning: YesterdayWarning? = YesterdayWarning(bookedHours: 0, expectedHours: 8)

        var api = MockYesterdayAPI()
        api.fetchEmploymentsHandler = { _ in
            [TestFactories.makeEmployment()]
        }
        // Return an absence for yesterday
        api.fetchSchedulesHandler = { _, _ in
            [TestFactories.makeSchedule(date: yStr, userId: 42)]
        }

        let manager = makeManager(api: api, warningCapture: { capturedWarning = $0 })
        let alerts = await manager.check()

        #expect(alerts.isEmpty)
        // Warning should be cleared on absence
        #expect(capturedWarning == nil)
    }
}
