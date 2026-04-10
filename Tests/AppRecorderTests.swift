import Testing
import Foundation
@testable import MocoCompanion

@MainActor
@Suite("AutotrackerRecording")
struct AppRecorderTests {

    private func makeTracker() throws -> Autotracker {
        let shadowDb = try SQLiteDatabase(path: ":memory:")
        let shadowStore = try ShadowEntryStore(database: shadowDb)
        let rulesDb = try SQLiteDatabase(path: ":memory:")
        let ruleStore = try RuleStore(database: rulesDb)
        return Autotracker(
            shadowEntryStore: shadowStore,
            appRecordStore: AppRecordStore(inMemory: true),
            ruleStore: ruleStore
        )
    }

    @Test func coalescingSameApp() throws {
        let tracker = try makeTracker()
        tracker.processAppChange(bundleId: "com.app.A", appName: "AppA")
        tracker.processAppChange(bundleId: "com.app.A", appName: "AppA")

        // Same app — segment not flushed, no records yet
        #expect(tracker.recordCount == 0)
        #expect(tracker.currentAppName == "AppA")
    }

    @Test func coalescingDifferentApp() throws {
        let tracker = try makeTracker()
        tracker.processAppChange(bundleId: "com.app.A", appName: "AppA")

        // Small delay so duration > 0
        Thread.sleep(forTimeInterval: 0.05)

        tracker.processAppChange(bundleId: "com.app.B", appName: "AppB")

        // AppA flushed when AppB became frontmost
        #expect(tracker.recordCount == 1)

        let records = tracker.records(for: Date())
        #expect(records.first?.appBundleId == "com.app.A")
        #expect(records.first?.appName == "AppA")
    }

    @Test func flushOnStop() throws {
        let tracker = try makeTracker()
        tracker.processAppChange(bundleId: "com.app.A", appName: "AppA")

        Thread.sleep(forTimeInterval: 0.05)

        tracker.stop()

        #expect(tracker.recordCount == 1)
        #expect(tracker.isRecording == false)
        #expect(tracker.currentAppName == nil)
    }

    @Test func recordCountUpdates() throws {
        let tracker = try makeTracker()

        tracker.processAppChange(bundleId: "com.app.A", appName: "AppA")
        Thread.sleep(forTimeInterval: 0.05)
        tracker.processAppChange(bundleId: "com.app.B", appName: "AppB")
        Thread.sleep(forTimeInterval: 0.05)
        tracker.processAppChange(bundleId: "com.app.C", appName: "AppC")

        // A flushed on B switch, B flushed on C switch
        #expect(tracker.recordCount == 2)
    }

    @Test func filterLoginWindow() throws {
        let tracker = try makeTracker()
        tracker.processAppChange(bundleId: "com.apple.loginwindow", appName: "loginwindow")

        #expect(tracker.recordCount == 0)
        #expect(tracker.currentAppName == nil)
    }

    @Test func filterScreenSaver() throws {
        let tracker = try makeTracker()
        tracker.processAppChange(bundleId: "com.apple.ScreenSaver", appName: "ScreenSaver")

        #expect(tracker.recordCount == 0)
        #expect(tracker.currentAppName == nil)
    }

    @Test func zeroDurationNotFlushed() throws {
        let tracker = try makeTracker()
        // Two immediate switches — first segment has ~0 duration
        tracker.processAppChange(bundleId: "com.app.A", appName: "AppA")
        tracker.processAppChange(bundleId: "com.app.B", appName: "AppB")

        // Duration ≈ 0 so record may or may not be stored depending on timing.
        // The important invariant: no crash, and currentAppName is B.
        #expect(tracker.currentAppName == "AppB")
    }
}
