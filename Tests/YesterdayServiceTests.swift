import Testing
import Foundation
@testable import MocoCompanion

@Suite("YesterdayService")
struct YesterdayServiceTests {

    // MARK: - Helpers

    /// Local noon avoids timezone assumptions while fixing the weekday.
    private static func date(_ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: day, hour: 12))!
    }

    private static var yesterdayString: String { DateUtilities.dateString(date(6)) }

    @MainActor
    private func makeService(
        api: MockYesterdayAPI? = MockYesterdayAPI(),
        isConfigured: Bool = true,
        userIdProvider: @escaping () -> Int? = { 42 },
        now: @escaping () -> Date = { Self.date(7) }
    ) -> YesterdayService {
        let settings = SettingsStore()
        if isConfigured {
            settings.subdomain = "test"
            settings.apiKey = "test-key"
        }
        return YesterdayService(
            settings: settings,
            clientFactory: { api },
            userIdProvider: userIdProvider,
            now: now
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
        let yStr = Self.yesterdayString

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
        let yStr = Self.yesterdayString

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
        var fetchEmploymentsCalled = false
        var api = MockYesterdayAPI()
        api.fetchEmploymentsHandler = { _ in
            fetchEmploymentsCalled = true
            return [TestFactories.makeEmployment()]
        }
        let service = makeService(api: api, now: { Self.date(5) })
        service.warning = YesterdayWarning(bookedHours: 0, expectedHours: 8)
        let alerts = await service.check()

        #expect(alerts.isEmpty)
        #expect(!fetchEmploymentsCalled)
        #expect(service.warning == nil)
    }

    // MARK: - Absence Skip

    @Test("check skips days with absences — returns empty and clears warning")
    @MainActor func absenceSkipReturnsEmpty() async {
        let yStr = Self.yesterdayString

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

        let activities = [TestFactories.makeShadowEntry(hours: 7.0)]
        service.recheckLocally(yesterdayActivities: activities)

        // 7/8 = 87.5% >= 85% → warning cleared
        #expect(service.warning == nil)
    }

    @Test("recheckLocally updates warning when still below threshold")
    @MainActor func localRecheckUpdatesWarning() {
        let service = makeService()
        service.warning = YesterdayWarning(bookedHours: 3.0, expectedHours: 8.0)

        let activities = [TestFactories.makeShadowEntry(hours: 4.0)]
        service.recheckLocally(yesterdayActivities: activities)

        // 4/8 = 50% < 85% → warning updated with new hours
        #expect(service.warning != nil)
        #expect(service.warning?.bookedHours == 4.0)
    }

    @Test("recheckLocally is no-op when no warning exists")
    @MainActor func localRecheckNoOpWithoutWarning() {
        let service = makeService()
        #expect(service.warning == nil)

        let activities = [TestFactories.makeShadowEntry(hours: 1.0)]
        service.recheckLocally(yesterdayActivities: activities)

        #expect(service.warning == nil)
    }
    @Test("No employment or zero expected hours clears an existing same-day warning")
    @MainActor func noWorkRequirementClearsWarning() async {
        for noEmployment in [true, false] {
            var hasWork = true
            var api = MockYesterdayAPI()
            api.fetchEmploymentsHandler = { _ in
                if hasWork { return [TestFactories.makeEmployment()] }
                if noEmployment { return [] }
                return [TestFactories.makeEmployment(patternAM: [0, 0, 0, 0, 0], patternPM: [0, 0, 0, 0, 0])]
            }
            let service = makeService(api: api)
            _ = await service.check()
            #expect(service.warning != nil)
            hasWork = false
            let alerts = await service.check()
            #expect(alerts.isEmpty)
            #expect(service.warning == nil)
        }
    }

    @Test("Same-day API errors preserve the warning; a new target day clears it")
    @MainActor func targetDayChangeAndErrors() async {
        var current = Self.date(7)
        var fail = false
        var api = MockYesterdayAPI()
        api.fetchEmploymentsHandler = { _ in
            if fail { throw MocoError.serverError(statusCode: 500, message: "Offline") }
            return [TestFactories.makeEmployment()]
        }
        let service = makeService(api: api, now: { current })
        _ = await service.check()
        #expect(service.warning != nil)
        fail = true
        _ = await service.check()
        #expect(service.warning != nil)
        current = Self.date(8)
        _ = await service.check()
        #expect(service.warning == nil)
    }

    @Test("A previous weekday warning is cleared on the weekend without fetching")
    @MainActor func weekdayToWeekendClearsWarning() async {
        var current = Self.date(3) // Saturday checks Friday.
        var calls = 0
        var api = MockYesterdayAPI()
        api.fetchEmploymentsHandler = { _ in
            calls += 1
            return [TestFactories.makeEmployment()]
        }
        let service = makeService(api: api, now: { current })
        _ = await service.check()
        #expect(service.warning != nil)
        current = Self.date(4) // Sunday checks Saturday.
        _ = await service.check()
        #expect(service.warning == nil)
        #expect(calls == 1)
    }

    @Test("A target day change clears warnings even without a client")
    @MainActor func targetDayChangeWithoutClient() async {
        var current = Self.date(7)
        var api = MockYesterdayAPI()
        api.fetchEmploymentsHandler = { _ in [TestFactories.makeEmployment()] }
        var available = true
        let service = YesterdayService(
            settings: SettingsStore(), clientFactory: { available ? api : nil },
            userIdProvider: { 42 }, now: { current }
        )
        _ = await service.check()
        #expect(service.warning != nil)
        available = false
        _ = await service.check()
        #expect(service.warning != nil)
        current = Self.date(8)
        _ = await service.check()
        #expect(service.warning == nil)
    }

}
