import Testing
import Foundation
@testable import MocoCompanion

@Suite("AppRecordStore")
struct AppRecordStoreTests {

    private func makeStore() throws -> AppRecordStore {
        try AppRecordStore(inMemory: true)
    }

    private func makeRecord(
        timestamp: Date = Date(),
        bundleId: String = "com.apple.Safari",
        name: String = "Safari",
        windowTitle: String? = nil,
        duration: TimeInterval = 10
    ) -> AppRecord {
        AppRecord(
            id: nil,
            timestamp: timestamp,
            appBundleId: bundleId,
            appName: name,
            windowTitle: windowTitle,
            durationSeconds: duration
        )
    }

    @Test func insertAndQuery() async throws {
        let store = try makeStore()
        let now = Date()
        let record = makeRecord(timestamp: now, bundleId: "com.apple.Xcode", name: "Xcode", windowTitle: nil, duration: 30)
        await store.insert(record)

        let results = await store.records(for: now)
        #expect(results.count == 1)
        let r = results[0]
        #expect(r.id != nil)
        #expect(r.appBundleId == "com.apple.Xcode")
        #expect(r.appName == "Xcode")
        #expect(r.windowTitle == nil)
        #expect(r.durationSeconds == 30)
    }

    @Test func queryByDateFilters() async throws {
        let store = try makeStore()
        let today = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!

        await store.insert(makeRecord(timestamp: today, name: "Today App"))
        await store.insert(makeRecord(timestamp: yesterday, name: "Yesterday App"))

        let todayResults = await store.records(for: today)
        #expect(todayResults.count == 1)
        #expect(todayResults[0].appName == "Today App")

        let yesterdayResults = await store.records(for: yesterday)
        #expect(yesterdayResults.count == 1)
        #expect(yesterdayResults[0].appName == "Yesterday App")
    }

    @Test func recordCount() async throws {
        let store = try makeStore()
        #expect(await store.recordCount() == 0)

        for i in 0..<5 {
            await store.insert(makeRecord(name: "App \(i)"))
        }
        #expect(await store.recordCount() == 5)
    }

    @Test func cleanupOlderThan() async throws {
        let store = try makeStore()
        let old = Calendar.current.date(byAdding: .day, value: -10, to: Date())!
        let recent = Date()

        await store.insert(makeRecord(timestamp: old, name: "Old App"))
        await store.insert(makeRecord(timestamp: recent, name: "Recent App"))
        #expect(await store.recordCount() == 2)

        await store.cleanup(olderThan: 5)
        #expect(await store.recordCount() == 1)

        let results = await store.records(for: recent)
        #expect(results.count == 1)
        #expect(results[0].appName == "Recent App")
    }

    @Test func emptyQuery() async throws {
        let store = try makeStore()
        let results = await store.records(for: Date())
        #expect(results.isEmpty)
    }

    @Test("Legacy midnight records are clipped per day without rewriting storage")
    func legacyMidnightRecordIsClipped() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let start = calendar.date(from: DateComponents(year: 2026, month: 6, day: 15, hour: 23, minute: 50))!
        let nextDay = calendar.date(from: DateComponents(year: 2026, month: 6, day: 16))!
        let store = try makeStore()
        await store.insert(makeRecord(timestamp: start, windowTitle: "Document", duration: 1800))
        let before = await store.records(for: start, calendar: calendar)
        let after = await store.records(for: nextDay, calendar: calendar)
        #expect(before.map(\.durationSeconds) == [600])
        #expect(after.map(\.durationSeconds) == [1200])
        #expect(after.first?.timestamp == nextDay)
        #expect(before.first?.id == after.first?.id)
        #expect(after.first?.windowTitle == "Document")
        #expect(await store.recordCount() == 1)
        #expect(await store.records(for: start, calendar: calendar) == before)
    }

    @Test("Legacy overlap queries use 23- and 25-hour local days", arguments: [3, 10])
    func legacyDSTRecordIsClipped(month: Int) async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let day = month == 3 ? 29 : 25
        let start = calendar.date(from: DateComponents(year: 2026, month: month, day: day - 1, hour: 23, minute: 50))!
        let middle = calendar.date(from: DateComponents(year: 2026, month: month, day: day))!
        let end = calendar.date(from: DateComponents(year: 2026, month: month, day: day + 1, hour: 0, minute: 20))!
        let store = try makeStore()
        await store.insert(makeRecord(timestamp: start, duration: end.timeIntervalSince(start)))
        let before = await store.records(for: start, calendar: calendar)
        let during = await store.records(for: middle, calendar: calendar)
        let after = await store.records(for: end, calendar: calendar)
        #expect(before.map(\.durationSeconds) == [600])
        #expect(during.map(\.durationSeconds) == [Double(month == 3 ? 23 : 25) * 3600])
        #expect(after.map(\.durationSeconds) == [1200])
        #expect((before + during + after).reduce(0) { $0 + $1.durationSeconds } == end.timeIntervalSince(start))
    }

    @Test("Overlap queries exclude records ending at day start and starting at day end")
    func overlapQueryUsesHalfOpenDays() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = calendar.date(from: DateComponents(year: 2026, month: 6, day: 15))!
        let nextDay = calendar.date(byAdding: .day, value: 1, to: day)!
        let store = try makeStore()
        await store.insert(makeRecord(timestamp: day.addingTimeInterval(-600), duration: 600))
        await store.insert(makeRecord(timestamp: nextDay, duration: 600))
        #expect(await store.records(for: day, calendar: calendar).isEmpty)
        await store.insert(makeRecord(timestamp: day, duration: 600))
        #expect(await store.records(for: day, calendar: calendar).map(\.durationSeconds) == [600])
    }

    // MARK: - Boundary / Negative Tests

    @Test func cleanupWithZeroDaysRemovesEverything() async throws {
        let store = try makeStore()
        let past = Calendar.current.date(byAdding: .minute, value: -5, to: Date())!
        await store.insert(makeRecord(timestamp: past))
        await store.insert(makeRecord(timestamp: past))
        #expect(await store.recordCount() == 2)

        await store.cleanup(olderThan: 0)
        #expect(await store.recordCount() == 0)
    }

    @Test func cleanupWithLargeDaysRemovesNothing() async throws {
        let store = try makeStore()
        await store.insert(makeRecord())
        await store.insert(makeRecord())
        #expect(await store.recordCount() == 2)

        await store.cleanup(olderThan: 99999)
        #expect(await store.recordCount() == 2)
    }
}
