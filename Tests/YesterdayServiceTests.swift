import Testing
import Foundation
@testable import MocoCompanion

@Suite("YesterdayService")
struct YesterdayServiceTests {

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
    private func makeService(
        api: MockYesterdayAPI? = MockYesterdayAPI(),
        isConfigured: Bool = true,
        userIdProvider: @escaping () -> Int? = { 42 }
    ) -> YesterdayService {
        let settings = SettingsStore()
        if isConfigured {
            settings.subdomain = "test"
            settings.apiKey = "test-key"
        }
        return YesterdayService(
            settings: settings,
            clientFactory: { api },
            userIdProvider: userIdProvider
        )
    }

    // MARK: - Nil Client

    @Test("check returns empty when clientFactory returns nil")
    @MainActor func nilClientReturnsEmpty() async {
        let service = makeService(api: nil)
        let alerts = await service.check()
        #expect(alerts.isEmpty)
    }

    // MARK: - No Employment Data

    @Test("check returns empty when no employments exist")
    @MainActor func noEmploymentsReturnsEmpty() async {
        var api = MockYesterdayAPI()
        api.fetchEmploymentsHandler = { _ in [] }
        let service = makeService(api: api)
        let alerts = await service.check()
        #expect(alerts.isEmpty)
    }

    // MARK: - Under-booked (alert path)

    @Test("check returns alert and sets warning when booked hours below 85% threshold")
    @MainActor func underBookedReturnsAlert() async {
        guard Self.yesterdayIsWeekday else { return }

        let yStr = Self.yesterday.dateString

        var api = MockYesterdayAPI()
        api.fetchEmploymentsHandler = { _ in
            [TestFactories.makeEmployment()]
        }
        api.fetchSchedulesHandler = { _, _ in [] }
        api.fetchActivitiesHandler = { from, to, userId in
            [TestFactories.makeActivity(date: yStr, seconds: 10800, hours: 3.0)]
        }

        let service = makeService(api: api)
        let alerts = await service.check()

        #expect(alerts.count == 1)
        #expect(alerts.first?.type == .yesterdayUnderBooked)
        #expect(service.warning != nil)
        #expect(service.warning?.bookedHours == 3.0)
    }

    // MARK: - Sufficiently booked (no alert)

    @Test("check returns empty and clears warning when booked hours meet 85% threshold")
    @MainActor func sufficientlyBookedReturnsEmpty() async {
        guard Self.yesterdayIsWeekday else { return }

        let yStr = Self.yesterday.dateString

        var api = MockYesterdayAPI()
        api.fetchEmploymentsHandler = { _ in
            [TestFactories.makeEmployment()]
        }
        api.fetchSchedulesHandler = { _, _ in [] }
        api.fetchActivitiesHandler = { _, _, _ in
            [TestFactories.makeActivity(date: yStr, seconds: 25200, hours: 7.0)]
        }

        let service = makeService(api: api)
        let alerts = await service.check()

        #expect(alerts.isEmpty)
        #expect(service.warning == nil)
    }

    // MARK: - Weekend Skip

    @Test("check skips weekends — returns empty regardless of employment data")
    @MainActor func weekendSkipReturnsEmpty() async {
        guard !Self.yesterdayIsWeekday else {
            var api = MockYesterdayAPI()
            api.fetchEmploymentsHandler = { _ in [] }
            let service = makeService(api: api)
            let alerts = await service.check()
            #expect(alerts.isEmpty)
            return
        }

        var fetchEmploymentsCalled = false
        var api = MockYesterdayAPI()
        api.fetchEmploymentsHandler = { _ in
            fetchEmploymentsCalled = true
            return [TestFactories.makeEmployment()]
        }
        let service = makeService(api: api)
        let alerts = await service.check()

        #expect(alerts.isEmpty)
        #expect(!fetchEmploymentsCalled)
    }

    // MARK: - Absence Skip

    @Test("check skips days with absences — returns empty and clears warning")
    @MainActor func absenceSkipReturnsEmpty() async {
        guard Self.yesterdayIsWeekday else { return }

        let yStr = Self.yesterday.dateString

        var api = MockYesterdayAPI()
        api.fetchEmploymentsHandler = { _ in
            [TestFactories.makeEmployment()]
        }
        api.fetchSchedulesHandler = { _, _ in
            [TestFactories.makeSchedule(date: yStr, userId: 42)]
        }

        let service = makeService(api: api)
        // Pre-set a warning to verify it gets cleared
        service.warning = YesterdayWarning(bookedHours: 0, expectedHours: 8)
        let alerts = await service.check()

        #expect(alerts.isEmpty)
        #expect(service.warning == nil)
    }

    // MARK: - Local recheck

    @Test("recheckLocally clears warning when hours cross threshold")
    @MainActor func localRecheckClearsWarning() {
        let service = makeService()
        service.warning = YesterdayWarning(bookedHours: 3.0, expectedHours: 8.0)

        let activities = [TestFactories.makeActivity(hours: 7.0)]
        service.recheckLocally(yesterdayActivities: activities)

        // 7/8 = 87.5% >= 85% → warning cleared
        #expect(service.warning == nil)
    }

    @Test("recheckLocally updates warning when still below threshold")
    @MainActor func localRecheckUpdatesWarning() {
        let service = makeService()
        service.warning = YesterdayWarning(bookedHours: 3.0, expectedHours: 8.0)

        let activities = [TestFactories.makeActivity(hours: 4.0)]
        service.recheckLocally(yesterdayActivities: activities)

        // 4/8 = 50% < 85% → warning updated with new hours
        #expect(service.warning != nil)
        #expect(service.warning?.bookedHours == 4.0)
    }

    @Test("recheckLocally is no-op when no warning exists")
    @MainActor func localRecheckNoOpWithoutWarning() {
        let service = makeService()
        #expect(service.warning == nil)

        let activities = [TestFactories.makeActivity(hours: 1.0)]
        service.recheckLocally(yesterdayActivities: activities)

        #expect(service.warning == nil)
    }
}
