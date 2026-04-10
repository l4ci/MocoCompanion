import Testing
import Foundation
@testable import MocoCompanion

@MainActor
@Suite("AppRecordStore")
struct AppRecordStoreTests {

    private func makeStore() -> AppRecordStore {
        AppRecordStore(inMemory: true)
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

    @Test func insertAndQuery() {
        let store = makeStore()
        let now = Date()
        let record = makeRecord(timestamp: now, bundleId: "com.apple.Xcode", name: "Xcode", windowTitle: nil, duration: 30)
        store.insert(record)

        let results = store.records(for: now)
        #expect(results.count == 1)
        let r = results[0]
        #expect(r.id != nil)
        #expect(r.appBundleId == "com.apple.Xcode")
        #expect(r.appName == "Xcode")
        #expect(r.windowTitle == nil)
        #expect(r.durationSeconds == 30)
    }

    @Test func queryByDateFilters() {
        let store = makeStore()
        let today = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!

        store.insert(makeRecord(timestamp: today, name: "Today App"))
        store.insert(makeRecord(timestamp: yesterday, name: "Yesterday App"))

        let todayResults = store.records(for: today)
        #expect(todayResults.count == 1)
        #expect(todayResults[0].appName == "Today App")

        let yesterdayResults = store.records(for: yesterday)
        #expect(yesterdayResults.count == 1)
        #expect(yesterdayResults[0].appName == "Yesterday App")
    }

    @Test func recordCount() {
        let store = makeStore()
        #expect(store.recordCount() == 0)

        for i in 0..<5 {
            store.insert(makeRecord(name: "App \(i)"))
        }
        #expect(store.recordCount() == 5)
    }

    @Test func cleanupOlderThan() {
        let store = makeStore()
        let old = Calendar.current.date(byAdding: .day, value: -10, to: Date())!
        let recent = Date()

        store.insert(makeRecord(timestamp: old, name: "Old App"))
        store.insert(makeRecord(timestamp: recent, name: "Recent App"))
        #expect(store.recordCount() == 2)

        store.cleanup(olderThan: 5)
        #expect(store.recordCount() == 1)

        let results = store.records(for: recent)
        #expect(results.count == 1)
        #expect(results[0].appName == "Recent App")
    }

    @Test func emptyQuery() {
        let store = makeStore()
        let results = store.records(for: Date())
        #expect(results.isEmpty)
    }

    // MARK: - Boundary / Negative Tests

    @Test func cleanupWithZeroDaysRemovesEverything() {
        let store = makeStore()
        let past = Calendar.current.date(byAdding: .minute, value: -5, to: Date())!
        store.insert(makeRecord(timestamp: past))
        store.insert(makeRecord(timestamp: past))
        #expect(store.recordCount() == 2)

        store.cleanup(olderThan: 0)
        #expect(store.recordCount() == 0)
    }

    @Test func cleanupWithLargeDaysRemovesNothing() {
        let store = makeStore()
        store.insert(makeRecord())
        store.insert(makeRecord())
        #expect(store.recordCount() == 2)

        store.cleanup(olderThan: 99999)
        #expect(store.recordCount() == 2)
    }
}
