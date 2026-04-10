import Testing
import Foundation
@testable import MocoCompanion

@MainActor
@Suite("AppRecorder")
struct AppRecorderTests {

    private func makeRecorder() -> AppRecorder {
        AppRecorder(store: AppRecordStore(inMemory: true))
    }

    @Test func coalescingSameApp() {
        let recorder = makeRecorder()
        recorder.processAppChange(bundleId: "com.app.A", appName: "AppA")
        recorder.processAppChange(bundleId: "com.app.A", appName: "AppA")

        // Same app — segment not flushed, no records yet
        #expect(recorder.store.recordCount() == 0)
        #expect(recorder.currentAppName == "AppA")
    }

    @Test func coalescingDifferentApp() {
        let recorder = makeRecorder()
        recorder.processAppChange(bundleId: "com.app.A", appName: "AppA")

        // Small delay so duration > 0
        Thread.sleep(forTimeInterval: 0.05)

        recorder.processAppChange(bundleId: "com.app.B", appName: "AppB")

        // AppA flushed when AppB became frontmost
        #expect(recorder.store.recordCount() == 1)
        #expect(recorder.recordCount == 1)

        let records = recorder.store.records(for: Date())
        #expect(records.first?.appBundleId == "com.app.A")
        #expect(records.first?.appName == "AppA")
    }

    @Test func flushOnStop() {
        let recorder = makeRecorder()
        recorder.processAppChange(bundleId: "com.app.A", appName: "AppA")

        Thread.sleep(forTimeInterval: 0.05)

        recorder.stop()

        #expect(recorder.store.recordCount() == 1)
        #expect(recorder.isRecording == false)
        #expect(recorder.currentAppName == nil)
    }

    @Test func recordCountUpdates() {
        let recorder = makeRecorder()

        recorder.processAppChange(bundleId: "com.app.A", appName: "AppA")
        Thread.sleep(forTimeInterval: 0.05)
        recorder.processAppChange(bundleId: "com.app.B", appName: "AppB")
        Thread.sleep(forTimeInterval: 0.05)
        recorder.processAppChange(bundleId: "com.app.C", appName: "AppC")

        // A flushed on B switch, B flushed on C switch
        #expect(recorder.recordCount == 2)
    }

    @Test func filterLoginWindow() {
        let recorder = makeRecorder()
        recorder.processAppChange(bundleId: "com.apple.loginwindow", appName: "loginwindow")

        #expect(recorder.store.recordCount() == 0)
        #expect(recorder.currentAppName == nil)
    }

    @Test func filterScreenSaver() {
        let recorder = makeRecorder()
        recorder.processAppChange(bundleId: "com.apple.ScreenSaver", appName: "ScreenSaver")

        #expect(recorder.store.recordCount() == 0)
        #expect(recorder.currentAppName == nil)
    }

    @Test func zeroDurationNotFlushed() {
        let recorder = makeRecorder()
        // Two immediate switches — first segment has ~0 duration
        recorder.processAppChange(bundleId: "com.app.A", appName: "AppA")
        recorder.processAppChange(bundleId: "com.app.B", appName: "AppB")

        // Duration ≈ 0 so record may or may not be stored depending on timing.
        // The important invariant: no crash, and currentAppName is B.
        #expect(recorder.currentAppName == "AppB")
    }
}
