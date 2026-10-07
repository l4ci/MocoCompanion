import Testing
import Foundation
@testable import MocoCompanion

@MainActor
@Suite("AutotrackerRecording")
struct AppRecorderTests {

    @Test("Excluded app time is never attributed to the previous app", arguments: [
        "com.example.excluded", "com.apple.loginwindow", "com.apple.ScreenSaver"
    ])
    func excludedTransitionEndsTrackedSegment(excluded: String) async throws {
        let settings = SettingsStore()
        settings.autotrackerExcludedApps = ["com.example.excluded"]
        let store = try AppRecordStore(inMemory: true)
        var now = Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: 15, hour: 12))!
        let beginning = now
        let tracker = Autotracker(
            shadowEntryStore: try ShadowEntryStore(database: SQLiteDatabase(path: ":memory:")),
            appRecordStore: store,
            ruleStore: try RuleStore(database: SQLiteDatabase(path: ":memory:")),
            settings: settings, workspace: FakeWorkspace(), clock: { now }
        )
        await tracker.processAppChange(bundleId: "com.app.A", appName: "AppA")
        now = beginning.addingTimeInterval(600)
        await tracker.processAppChange(bundleId: excluded, appName: "Excluded")
        #expect(tracker.currentAppName == nil)
        now = beginning.addingTimeInterval(1800)
        await tracker.processAppChange(bundleId: "com.app.B", appName: "AppB")
        now = beginning.addingTimeInterval(2400)
        await tracker.stop()
        let records = await tracker.records(for: now)
        #expect(records.map(\.appBundleId) == ["com.app.A", "com.app.B"])
        #expect(records.map(\.durationSeconds) == [600, 600])
        #expect(records.map(\.timestamp) == [beginning, beginning.addingTimeInterval(1800)])
    }

    @Test("Exclusion invalidates a tracked debounce already queued behind it")
    func excludedTransitionInvalidatesQueuedDebounce() async throws {
        let store = try AppRecordStore(inMemory: true)
        let workspace = FakeWorkspace()
        var now = Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: 15, hour: 12))!
        let beginning = now
        let tracker = Autotracker(
            shadowEntryStore: try ShadowEntryStore(database: SQLiteDatabase(path: ":memory:")),
            appRecordStore: store,
            ruleStore: try RuleStore(database: SQLiteDatabase(path: ":memory:")),
            workspace: workspace, clock: { now }
        )
        await tracker.processAppChange(bundleId: "com.app.A", appName: "AppA")
        now = beginning.addingTimeInterval(600)
        // Both enqueue synchronously on the main actor, before either runs:
        // the stale timer has already passed its cancellation check.
        workspace.handler?(.appActivated(bundleId: "com.apple.loginwindow", appName: "Excluded", windowTitle: nil))
        tracker._testEnqueueDebouncedAppChange(bundleId: "com.app.A", appName: "AppA")
        await tracker._testDrainWorkspaceEvents()
        #expect(tracker.currentAppName == nil)
        now = beginning.addingTimeInterval(1800)
        await tracker.stop()
        let records = await tracker.records(for: now)
        #expect(records.map(\.durationSeconds) == [600])
        #expect(records.map(\.appBundleId) == ["com.app.A"])
    }

    @Test("New segments split 23:50–00:20 into ten and twenty minutes")
    func midnightSplitsNewSegment() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let start = calendar.date(from: DateComponents(year: 2026, month: 6, day: 15, hour: 23, minute: 50))!
        let end = calendar.date(from: DateComponents(year: 2026, month: 6, day: 16, hour: 0, minute: 20))!
        let store = try AppRecordStore(inMemory: true)
        var now = start
        let tracker = Autotracker(
            shadowEntryStore: try ShadowEntryStore(database: SQLiteDatabase(path: ":memory:")),
            appRecordStore: store,
            ruleStore: try RuleStore(database: SQLiteDatabase(path: ":memory:")),
            workspace: FakeWorkspace(), clock: { now }, calendar: calendar
        )
        await tracker.processAppChange(bundleId: "com.app.A", appName: "AppA", windowTitle: "Document")
        now = end
        await tracker.stop()
        #expect(await store.recordCount() == 2)
        #expect(tracker.recordCount == 2)
        let before = await tracker.records(for: start)
        let after = await tracker.records(for: end)
        #expect(before.map(\.durationSeconds) == [600])
        #expect(after.map(\.durationSeconds) == [1200])
        #expect(after.first?.timestamp == calendar.startOfDay(for: end))
        #expect(before.first?.id != after.first?.id)
        #expect(after.first?.windowTitle == "Document")
    }

    @Test("Segments split at actual midnight across short and long DST days", arguments: [3, 10])
    func midnightSplitsAcrossDST(month: Int) async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let day = month == 3 ? 29 : 25
        let start = calendar.date(from: DateComponents(year: 2026, month: month, day: day - 1, hour: 23, minute: 50))!
        let middle = calendar.date(from: DateComponents(year: 2026, month: month, day: day))!
        let end = calendar.date(from: DateComponents(year: 2026, month: month, day: day + 1, hour: 0, minute: 20))!
        let store = try AppRecordStore(inMemory: true)
        var now = start
        let tracker = Autotracker(
            shadowEntryStore: try ShadowEntryStore(database: SQLiteDatabase(path: ":memory:")),
            appRecordStore: store,
            ruleStore: try RuleStore(database: SQLiteDatabase(path: ":memory:")),
            workspace: FakeWorkspace(), clock: { now }, calendar: calendar
        )
        await tracker.processAppChange(bundleId: "com.app.A", appName: "AppA")
        now = end
        await tracker.stop()
        #expect(await store.recordCount() == 3)
        let before = await tracker.records(for: start)
        let during = await tracker.records(for: middle)
        let after = await tracker.records(for: end)
        #expect(before.map(\.durationSeconds) == [600])
        #expect(during.map(\.durationSeconds) == [Double(month == 3 ? 23 : 25) * 3600])
        #expect(after.map(\.durationSeconds) == [1200])
        #expect((before + during + after).reduce(0) { $0 + $1.durationSeconds } == end.timeIntervalSince(start))
    }

    private func makeTracker() throws -> Autotracker {
        let shadowDb = try SQLiteDatabase(path: ":memory:")
        let shadowStore = try ShadowEntryStore(database: shadowDb)
        let rulesDb = try SQLiteDatabase(path: ":memory:")
        let ruleStore = try RuleStore(database: rulesDb)
        return Autotracker(
            shadowEntryStore: shadowStore,
            appRecordStore: try AppRecordStore(inMemory: true),
            ruleStore: ruleStore
        )
    }

    /// Scriptable workspace: tests push events through `handler` directly.
    @MainActor
    private final class FakeWorkspace: WorkspaceMonitor {
        var handler: ((WorkspaceEvent) -> Void)?
        var currentFrontmost: (bundleId: String, appName: String, windowTitle: String?)?
        func start() {}
        func stop() {}
    }

    @Test("Back-to-back sleep events flush the segment exactly once")
    func duplicateSleepEventsFlushOnce() async throws {
        let shadowDb = try SQLiteDatabase(path: ":memory:")
        let shadowStore = try ShadowEntryStore(database: shadowDb)
        let rulesDb = try SQLiteDatabase(path: ":memory:")
        let ruleStore = try RuleStore(database: rulesDb)
        let store = try AppRecordStore(inMemory: true)
        let workspace = FakeWorkspace()
        var now = Date(timeIntervalSince1970: 1_700_000_000)
        let tracker = Autotracker(
            shadowEntryStore: shadowStore,
            appRecordStore: store,
            ruleStore: ruleStore,
            workspace: workspace,
            clock: { now }
        )
        await tracker.processAppChange(bundleId: "com.app.A", appName: "AppA")
        now = now.addingTimeInterval(30)

        // macOS fires screensDidSleep + sessionDidResignActive together on
        // lock; both map to .sleep. Without serialized handling these two
        // interleave and insert the same segment twice.
        workspace.handler?(.sleep)
        workspace.handler?(.sleep)
        await tracker.stop()

        #expect(await store.recordCount() == 1)
    }

    /// Regression test for a lost-segment race: `scheduleDebouncedAppChange`
    /// schedules a real-time debounce timer for an app activation; if the
    /// system sleeps and wakes again before that timer elapses, wake reads
    /// `currentFrontmost` and starts its own segment directly — the stale
    /// debounced activation must not survive to fire afterwards with
    /// outdated app info.
    ///
    /// Sequence, with the injected clock advanced between steps so records
    /// land on distinguishable timestamps:
    ///   1. `start()` — segment A begins.
    ///   2. `.sleep` — flushes segment A (record #1, app A). No debounce is
    ///      pending yet, so nothing to cancel.
    ///   3. `.appActivated(C)` — schedules a debounced switch to C (a real
    ///      300 ms timer; `currentSegment` is nil, so nothing to flush yet).
    ///   4. `.wake` (with `currentFrontmost` set to B) — reads B directly
    ///      and starts segment B. THE FIX also cancels the still-pending C
    ///      debounce here.
    ///   5. Wait past the 300 ms debounce window.
    ///   6. `stop()` — flushes whatever segment is current.
    ///
    /// Hand-derived expected result under the fix (strict serialization, C
    /// debounce cancelled at wake and never fires):
    ///   record #1 = A (sleep flush), record #2 = B (stop flush)
    ///   → 2 records, apps {A, B}.
    ///
    /// Under the pre-fix code, `.wake` never cancels `pendingAppChangeTask`.
    /// The stale C debounce survives and, ~300ms later (deterministic, not
    /// a coincidental race — nothing else is running at that moment), calls
    /// `processAppChange` directly with the injected clock still frozen at
    /// the same instant wake set it to (only real wall-clock time passed
    /// during the wait, not simulated time). That flushes segment B with a
    /// computed duration of exactly 0 — silently DROPPED, never inserted —
    /// and starts segment C in its place, which `stop()` later flushes as a
    /// real record once the clock is advanced again.
    ///   → still 2 records, but apps {A, C}: B is lost entirely and a
    ///   phantom C record — time the user never actually spent in C —
    ///   takes its place. The record *count* alone doesn't catch this; the
    ///   assertion on which apps actually got recorded does.
    @Test("Wake cancels a stale debounced app-change so it can't clobber a later segment")
    func wakeCancelsStaleDebouncedAppChange() async throws {
        let shadowDb = try SQLiteDatabase(path: ":memory:")
        let shadowStore = try ShadowEntryStore(database: shadowDb)
        let rulesDb = try SQLiteDatabase(path: ":memory:")
        let ruleStore = try RuleStore(database: rulesDb)
        let store = try AppRecordStore(inMemory: true)
        let workspace = FakeWorkspace()
        var now = Date(timeIntervalSince1970: 1_700_000_000)
        workspace.currentFrontmost = (bundleId: "com.app.A", appName: "AppA", windowTitle: nil)

        let tracker = Autotracker(
            shadowEntryStore: shadowStore,
            appRecordStore: store,
            ruleStore: ruleStore,
            workspace: workspace,
            clock: { now }
        )

        await tracker.start() // segment A begins
        now = now.addingTimeInterval(5)

        workspace.handler?(.sleep) // flushes A -> record #1
        try await Task.sleep(for: .milliseconds(20)) // let the eventChain drain the .sleep event
        now = now.addingTimeInterval(1)

        // Schedule a debounced switch to C — a real 300ms timer, not yet fired.
        workspace.handler?(.appActivated(bundleId: "com.app.C", appName: "AppC", windowTitle: nil))
        try await Task.sleep(for: .milliseconds(20)) // let the eventChain schedule the debounce
        now = now.addingTimeInterval(1)

        // Wake, well inside the 300ms debounce window, with a different app
        // (B) frontmost. Wake starts B directly; the fix also cancels the
        // still-pending C debounce so it can never fire afterwards.
        workspace.currentFrontmost = (bundleId: "com.app.B", appName: "AppB", windowTitle: nil)
        workspace.handler?(.wake)

        // Wait past the 300ms debounce window so a NOT-cancelled C debounce
        // (pre-fix behavior) has time to actually fire.
        try await Task.sleep(for: .milliseconds(450))
        now = now.addingTimeInterval(5)

        await tracker.stop() // flushes whatever segment is current

        #expect(await store.recordCount() == 2)
        let records = await tracker.records(for: now)
        #expect(Set(records.map(\.appBundleId)) == ["com.app.A", "com.app.B"])
    }

    @Test func coalescingSameApp() async throws {
        let tracker = try makeTracker()
        await tracker.processAppChange(bundleId: "com.app.A", appName: "AppA")
        await tracker.processAppChange(bundleId: "com.app.A", appName: "AppA")

        // Same app — segment not flushed, no records yet
        #expect(tracker.recordCount == 0)
        #expect(tracker.currentAppName == "AppA")
    }

    @Test func coalescingDifferentApp() async throws {
        let tracker = try makeTracker()
        await tracker.processAppChange(bundleId: "com.app.A", appName: "AppA")

        // Small delay so duration > 0
        try await Task.sleep(for: .milliseconds(50))

        await tracker.processAppChange(bundleId: "com.app.B", appName: "AppB")

        // AppA flushed when AppB became frontmost
        #expect(tracker.recordCount == 1)

        let records = await tracker.records(for: Date())
        #expect(records.first?.appBundleId == "com.app.A")
        #expect(records.first?.appName == "AppA")
    }

    @Test func flushOnStop() async throws {
        let tracker = try makeTracker()
        await tracker.processAppChange(bundleId: "com.app.A", appName: "AppA")

        try await Task.sleep(for: .milliseconds(50))

        await tracker.stop()

        #expect(tracker.recordCount == 1)
        #expect(tracker.isRecording == false)
        #expect(tracker.currentAppName == nil)
    }

    @Test func recordCountUpdates() async throws {
        let tracker = try makeTracker()

        await tracker.processAppChange(bundleId: "com.app.A", appName: "AppA")
        try await Task.sleep(for: .milliseconds(50))
        await tracker.processAppChange(bundleId: "com.app.B", appName: "AppB")
        try await Task.sleep(for: .milliseconds(50))
        await tracker.processAppChange(bundleId: "com.app.C", appName: "AppC")

        // A flushed on B switch, B flushed on C switch
        #expect(tracker.recordCount == 2)
    }

    @Test func filterLoginWindow() async throws {
        let tracker = try makeTracker()
        await tracker.processAppChange(bundleId: "com.apple.loginwindow", appName: "loginwindow")

        #expect(tracker.recordCount == 0)
        #expect(tracker.currentAppName == nil)
    }

    @Test func filterScreenSaver() async throws {
        let tracker = try makeTracker()
        await tracker.processAppChange(bundleId: "com.apple.ScreenSaver", appName: "ScreenSaver")

        #expect(tracker.recordCount == 0)
        #expect(tracker.currentAppName == nil)
    }

    @Test func zeroDurationNotFlushed() async throws {
        let tracker = try makeTracker()
        // Two immediate switches — first segment has ~0 duration
        await tracker.processAppChange(bundleId: "com.app.A", appName: "AppA")
        await tracker.processAppChange(bundleId: "com.app.B", appName: "AppB")

        // Duration ≈ 0 so record may or may not be stored depending on timing.
        // The important invariant: no crash, and currentAppName is B.
        #expect(tracker.currentAppName == "AppB")
    }

    /// Same bundle, different window title — the FocusedWindowObserver path
    /// re-emits `appActivated` for the same app with a fresh title. The
    /// existing coalescing logic must flush the prior segment and start a
    /// new one tagged with the new title.
    @Test func intraAppTitleChangeFlushesSegment() async throws {
        let tracker = try makeTracker()
        await tracker.processAppChange(bundleId: "com.google.Chrome", appName: "Chrome", windowTitle: "Inbox — Gmail")

        try await Task.sleep(for: .milliseconds(50))

        await tracker.processAppChange(bundleId: "com.google.Chrome", appName: "Chrome", windowTitle: "GitHub — Pull Request #42")

        // First Chrome segment flushed when title changed
        #expect(tracker.recordCount == 1)

        let records = await tracker.records(for: Date())
        #expect(records.first?.appBundleId == "com.google.Chrome")
        #expect(records.first?.windowTitle == "Inbox — Gmail")
    }

    /// Same bundle, identical window title — repeated events extend the
    /// segment rather than create a new one. Critical so AX-observer
    /// re-fires (which can happen for purely cosmetic focus events) don't
    /// produce duplicate records.
    @Test func intraAppIdenticalTitleCoalesces() async throws {
        let tracker = try makeTracker()
        await tracker.processAppChange(bundleId: "com.google.Chrome", appName: "Chrome", windowTitle: "Inbox — Gmail")
        await tracker.processAppChange(bundleId: "com.google.Chrome", appName: "Chrome", windowTitle: "Inbox — Gmail")

        #expect(tracker.recordCount == 0)
        #expect(tracker.currentAppName == "Chrome")
    }
}
