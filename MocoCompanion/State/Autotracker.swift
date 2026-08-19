import AppKit
import Foundation
import os

// MARK: - Workspace Monitor Port

/// Events emitted by a `WorkspaceMonitor` as the user's foreground app changes
/// or the machine enters/leaves a sleeping state. Production adapter converts
/// NSWorkspace notifications into these events; tests drive them directly.
enum WorkspaceEvent: Sendable {
    case appActivated(bundleId: String, appName: String, windowTitle: String?)
    case sleep
    case wake
}

/// Narrow port for foreground-app change detection and sleep/wake transitions.
/// Production wraps NSWorkspace; tests provide a fake with an `emit(_:)` entry
/// point so workspace scenarios can be driven deterministically.
@MainActor
protocol WorkspaceMonitor: AnyObject {
    /// Handler invoked on every workspace event once `start()` is called.
    var handler: ((WorkspaceEvent) -> Void)? { get set }
    func start()
    func stop()
    /// The currently-frontmost app, or nil if none / not supported.
    /// `windowTitle` is populated when Accessibility is trusted and the
    /// frontmost process exposes a focused window; nil otherwise.
    var currentFrontmost: (bundleId: String, appName: String, windowTitle: String?)? { get }
}

/// Production `WorkspaceMonitor` that observes NSWorkspace notifications.
@MainActor
final class NSWorkspaceMonitor: WorkspaceMonitor {
    var handler: ((WorkspaceEvent) -> Void)?
    private var observers: [NSObjectProtocol] = []

    /// Closure reporting whether window-title capture is currently enabled
    /// via `SettingsStore.windowTitleTrackingEnabled`. Default returns false
    /// so titles are NOT captured unless explicitly wired up. Set from
    /// `Autotracker.init`.
    var captureWindowTitles: () -> Bool = { false }

    /// Per-PID observer for intra-app focus changes (tab switch in browsers,
    /// email opened in mail clients, document switch in editors). Replaced on
    /// every app activation; nil'd in `stop()`.
    private var focusedWindowObserver: FocusedWindowObserver?
    private var observedPid: pid_t?
    private var observedBundleId: String?
    private var observedAppName: String?

    /// Injectable AX title resolver. Production wraps
    /// `AccessibilityPermission.capturefocusedWindowTitle`; tests substitute
    /// a controllable async closure to simulate out-of-order AX resolution
    /// across rapid activations.
    var titleResolver: @Sendable (pid_t) async -> String? = { pid in
        await AccessibilityPermission.capturefocusedWindowTitle(forProcess: pid)
    }

    /// Monotonically increasing counter bumped on every activation (full app
    /// switch or intra-app focus change) that kicks off an AX title
    /// resolution. Each resolution captures the counter's value at spawn
    /// time; when it completes, the result is only reported to `handler` if
    /// the counter still matches — otherwise a newer activation has since
    /// superseded it. Without this guard, a slow AX read for an earlier
    /// activation can resolve after a faster later one and overwrite it with
    /// stale app/title data.
    private var activationGeneration: Int = 0

    /// Sync frontmost info. Returns nil window title — full title capture
    /// would block the caller on AX reads. The first didActivate event
    /// after this will fill in the title asynchronously.
    var currentFrontmost: (bundleId: String, appName: String, windowTitle: String?)? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let bundleId = app.bundleIdentifier,
              let name = app.localizedName else { return nil }
        return (bundleId, name, nil)
    }

    func start() {
        guard observers.isEmpty else { return }
        let ws = NSWorkspace.shared.notificationCenter

        observers.append(ws.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let bundleId = app?.bundleIdentifier
            let name = app?.localizedName
            let pid = app?.processIdentifier ?? 0
            guard let self, let bundleId, let name else { return }
            let wantsTitle = MainActor.assumeIsolated { self.captureWindowTitles() }

            if !wantsTitle {
                MainActor.assumeIsolated {
                    // Bump the generation even though this path reports no
                    // title itself — a stale AX read still in flight from
                    // the previous activation must not land after this one.
                    self.activationGeneration += 1
                    self.detachFocusedWindowObserver()
                    self.handler?(.appActivated(bundleId: bundleId, appName: name, windowTitle: nil))
                }
                return
            }

            // Rebind the per-PID observer synchronously so intra-app focus
            // changes start firing immediately for the new frontmost app.
            MainActor.assumeIsolated {
                self.attachFocusedWindowObserver(pid: pid, bundleId: bundleId, appName: name)
                self.beginTitleResolution(pid: pid, bundleId: bundleId, appName: name)
            }
        })
        observers.append(ws.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.handler?(.sleep) }
        })
        observers.append(ws.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.handler?(.wake) }
        })
        observers.append(ws.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.handler?(.sleep) }
        })
        observers.append(ws.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.handler?(.wake) }
        })
    }

    func stop() {
        let ws = NSWorkspace.shared.notificationCenter
        for token in observers { ws.removeObserver(token) }
        observers.removeAll()
        detachFocusedWindowObserver()
    }

    /// Bind a new AX observer to the given PID. Tears down any previous
    /// observer first so we only hold one at a time. Called from the
    /// `didActivateApplication` handler.
    private func attachFocusedWindowObserver(pid: pid_t, bundleId: String, appName: String) {
        detachFocusedWindowObserver()
        observedPid = pid
        observedBundleId = bundleId
        observedAppName = appName
        focusedWindowObserver = FocusedWindowObserver(pid: pid) { [weak self] in
            self?.handleFocusedWindowChange()
        }
    }

    private func detachFocusedWindowObserver() {
        focusedWindowObserver = nil
        observedPid = nil
        observedBundleId = nil
        observedAppName = nil
    }

    /// Fires when the AX server posts `kAXFocusedWindowChangedNotification`
    /// for the currently-observed app. Re-reads the focused window title and
    /// emits a fresh `appActivated` event so `Autotracker` debounces and, if
    /// the title genuinely changed, flushes the current segment and starts a
    /// new one tagged with the new title.
    private func handleFocusedWindowChange() {
        guard let pid = observedPid,
              let bundleId = observedBundleId,
              let appName = observedAppName else { return }
        beginTitleResolution(pid: pid, bundleId: bundleId, appName: appName)
    }

    /// Spawns a time-boxed off-main AX title read for `pid`, tagged with a
    /// fresh generation number. The main actor is released immediately —
    /// `handler` fires when the title arrives, but only if no newer
    /// activation or focus change has superseded this one in the meantime
    /// (see `activationGeneration`). Shared by the full-app-activation path
    /// and `handleFocusedWindowChange`'s intra-app path.
    private func beginTitleResolution(pid: pid_t, bundleId: String, appName: String) {
        activationGeneration += 1
        let generation = activationGeneration
        let resolver = titleResolver
        Task { [weak self] in
            let title = await resolver(pid)
            await MainActor.run {
                guard let self, self.activationGeneration == generation else { return }
                self.handler?(.appActivated(bundleId: bundleId, appName: appName, windowTitle: title))
            }
        }
    }
}

#if DEBUG
extension NSWorkspaceMonitor {
    /// Test-only entry point that exercises the same generation-guarded AX
    /// title resolution path as the real `didActivateApplicationNotification`
    /// and `handleFocusedWindowChange` handlers, without requiring a live
    /// NSWorkspace notification or an AX-trusted process. Inject
    /// `titleResolver` with a controlled delay to simulate an earlier
    /// activation's AX read completing after a later one's. DO NOT use in
    /// production code.
    func _testBeginTitleResolution(pid: pid_t, bundleId: String, appName: String) {
        beginTitleResolution(pid: pid, bundleId: bundleId, appName: appName)
    }
}
#endif

// MARK: - Autotracker

/// Deep module that owns the full "watch apps and suggest time entries"
/// pipeline. Callers depend on this single facade instead of the four
/// separate types it replaces at the public boundary (AppRecorder,
/// AppRecordStore, RuleStore, RuleEngine) plus the ad-hoc
/// UserDefaults-backed declined-suggestion state.
///
/// Internally the NSWorkspace-facing piece, the SQLite stores, and the rule
/// evaluator remain as private implementation details — the point is that the
/// rest of the app no longer has to know about them.
///
/// ## Ports
///
/// - `WorkspaceMonitor` — foreground-app change source. Production adapter
///   wraps NSWorkspace notifications; tests inject a `FakeWorkspaceMonitor`
///   and drive events through its `emit(_:)` method.
/// - `clock` — a `() -> Date` closure used for every timestamp the module
///   produces (segment start, record duration, approval createdAt, etc.), so
///   tests can drive time deterministically without sleeping.
///
/// ## Dependencies
///
/// Approve-path writes go to an injected `ShadowEntryStore`. The shadow
/// subsystem is a lower layer this module *depends on* — it does not own it.
@Observable @MainActor
final class Autotracker {
    private static let atLogger = Logger(category: "Autotracker")
    private static let isoFormatter = ISO8601DateFormatter()

    // MARK: - Internal composed state

    private let appRecordStore: AppRecordStore
    private let ruleStore: RuleStore
    private let shadowEntryStore: ShadowEntryStore
    private let workspace: WorkspaceMonitor
    private let clock: () -> Date
    private let settings: SettingsStore?
    private let declinedDefaults: UserDefaults

    // MARK: - Observable public state

    private(set) var suggestions: [Suggestion] = []
    private(set) var isRecording: Bool = false
    private(set) var recordCount: Int = 0
    private(set) var currentAppName: String?

    // MARK: - Recording / coalescing state

    private struct Segment {
        var bundleId: String
        var appName: String
        var windowTitle: String?
        var startedAt: Date
        var lastSeenAt: Date
    }

    private var currentSegment: Segment?
    private let coalescingThreshold: TimeInterval = 10.0

    /// Debounce interval for rapid app activations. Alt-tabbing through 5
    /// apps in 200 ms should not create 5 segments — the user isn't doing
    /// real work in any of them. Only the final app (held for >300 ms)
    /// gets recorded.
    private let activationDebounce: Duration = .milliseconds(300)
    private var pendingAppChangeTask: Task<Void, Never>?
    /// Tail of the serialized workspace-event chain (see init).
    private var eventChain: Task<Void, Never>?

    private static let systemFilteredBundleIds: Set<String> = [
        "com.apple.loginwindow",
        "com.apple.ScreenSaver",
    ]

    private var filteredBundleIds: Set<String> {
        Self.systemFilteredBundleIds.union(settings?.autotrackerExcludedApps ?? [])
    }

    // MARK: - Declined suggestion state

    private var declinedSuggestionIds: Set<String> = []
    private var loadedDeclinedDate: String?

    /// Called after entries are inserted into the shadow store (create-mode rules
    /// or approved suggestions). Allows AppState to refresh the Today panel.
    var onEntryCreated: (() async -> Void)?

    // MARK: - Init

    init(
        shadowEntryStore: ShadowEntryStore,
        appRecordStore: AppRecordStore,
        ruleStore: RuleStore,
        settings: SettingsStore? = nil,
        workspace: WorkspaceMonitor? = nil,
        clock: @escaping () -> Date = Date.init,
        declinedDefaults: UserDefaults = .standard
    ) {
        self.shadowEntryStore = shadowEntryStore
        self.appRecordStore = appRecordStore
        self.ruleStore = ruleStore
        self.settings = settings
        let resolvedWorkspace = workspace ?? NSWorkspaceMonitor()
        self.workspace = resolvedWorkspace
        self.clock = clock
        self.declinedDefaults = declinedDefaults

        // AppRecordStore is an actor — its recordCount() can't be awaited
        // synchronously from this (non-async) init. `recordCount` starts at
        // 0 and is corrected moments later by this Task, which is enqueued
        // on the main actor before init returns and so runs before any
        // later flush-triggered update (start()/processAppChange happen
        // only after the caller receives this instance).
        Task { [weak self, appRecordStore] in
            let count = await appRecordStore.recordCount()
            self?.recordCount = count
        }

        if let ns = resolvedWorkspace as? NSWorkspaceMonitor {
            ns.captureWindowTitles = { [weak settings] in
                settings?.windowTitleTrackingEnabled == true
            }
        }

        // Events are processed strictly in order: each one waits for the
        // previous to finish. handleWorkspaceEvent suspends on store IO, and
        // macOS can deliver several notifications for one transition (e.g.
        // screensDidSleep + sessionDidResignActive), so unordered per-event
        // Tasks could interleave and flush or clobber the same segment twice.
        self.workspace.handler = { [weak self] event in
            self?.enqueue { [weak self] in
                await self?.handleWorkspaceEvent(event)
            }
        }
    }

    /// Chains `work` onto the tail of the serialized workspace-event queue
    /// (`eventChain`) so it can never interleave with a workspace-event
    /// handler, or with another unit of work enqueued this way. Used by the
    /// workspace-event handler above and by `scheduleDebouncedAppChange`'s
    /// debounce task — the latter previously called `processAppChange`
    /// directly, off the chain, so it could land concurrently with a
    /// chained flush/wake and clobber a segment either had just started.
    private func enqueue(_ work: @escaping @MainActor () async -> Void) {
        let previous = eventChain
        eventChain = Task { @MainActor in
            await previous?.value
            await work()
        }
    }

    // MARK: - Lifecycle

    func start() async {
        guard !isRecording else { return }
        isRecording = true
        workspace.start()
        if let frontmost = workspace.currentFrontmost {
            await processAppChange(bundleId: frontmost.bundleId, appName: frontmost.appName, windowTitle: frontmost.windowTitle)
        }
        Self.atLogger.info("Recording started")
    }

    func stop() async {
        // Let queued workspace events settle so none starts a segment after
        // the final flush below.
        await eventChain?.value
        pendingAppChangeTask?.cancel()
        pendingAppChangeTask = nil
        await flushCurrentSegment()
        workspace.stop()
        isRecording = false
        currentAppName = nil
        Self.atLogger.info("Recording stopped")
    }

    private func handleWorkspaceEvent(_ event: WorkspaceEvent) async {
        switch event {
        case .appActivated(let bundleId, let appName, let windowTitle):
            scheduleDebouncedAppChange(bundleId: bundleId, appName: appName, windowTitle: windowTitle)
        case .sleep:
            pendingAppChangeTask?.cancel()
            pendingAppChangeTask = nil
            await flushCurrentSegment()
            Self.atLogger.debug("Paused for sleep/session resign")
        case .wake:
            guard isRecording else { return }
            // A debounced app-change scheduled before sleep (or a stray
            // activation delivered while "asleep") must not fire after wake
            // with stale app info — this path already reads currentFrontmost
            // itself, so any pending debounce is redundant at best and a
            // clobber at worst.
            pendingAppChangeTask?.cancel()
            pendingAppChangeTask = nil
            if let frontmost = workspace.currentFrontmost {
                await processAppChange(bundleId: frontmost.bundleId, appName: frontmost.appName, windowTitle: frontmost.windowTitle)
            }
            Self.atLogger.debug("Resumed after wake/session active")
        }
    }

    /// Collapse rapid app activations into one processAppChange call. Each
    /// new event cancels the previous pending task and schedules a fresh
    /// one; only the last event in a burst actually runs. The delayed work
    /// is routed through `enqueue` (rather than calling `processAppChange`
    /// directly) so it's serialized with the eventChain — this task runs
    /// independently of that chain while it's sleeping, and without this it
    /// could land in the middle of a chained flush/wake and clobber a
    /// segment either had just started.
    private func scheduleDebouncedAppChange(bundleId: String, appName: String, windowTitle: String?) {
        pendingAppChangeTask?.cancel()
        pendingAppChangeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: self?.activationDebounce ?? .milliseconds(300))
            guard !Task.isCancelled, let self else { return }
            self.enqueue { [weak self] in
                await self?.processAppChange(bundleId: bundleId, appName: appName, windowTitle: windowTitle)
            }
        }
    }

    // MARK: - Coalescing (internal for testing)

    func processAppChange(bundleId: String, appName: String, windowTitle: String? = nil) async {
        guard !filteredBundleIds.contains(bundleId) else { return }
        let now = clock()

        if currentSegment == nil {
            currentSegment = Segment(bundleId: bundleId, appName: appName, windowTitle: windowTitle, startedAt: now, lastSeenAt: now)
        } else if currentSegment!.bundleId == bundleId && currentSegment!.windowTitle == windowTitle {
            // Same app AND same window title — extend existing segment.
            // nil == nil counts as equal, so when title capture is
            // disabled coalescing falls back to bundleId-only.
            currentSegment!.lastSeenAt = now
        } else {
            await flushCurrentSegment()
            currentSegment = Segment(bundleId: bundleId, appName: appName, windowTitle: windowTitle, startedAt: now, lastSeenAt: now)
        }

        currentAppName = appName
    }

    private func flushCurrentSegment() async {
        // Take ownership before the first suspension so a concurrent caller
        // (debounced app change vs. sleep flush) can't flush the same segment.
        guard let segment = currentSegment else { return }
        currentSegment = nil
        let now = clock()
        let duration = max(segment.lastSeenAt, now).timeIntervalSince(segment.startedAt)
        if duration > 0 {
            let record = AppRecord(
                id: nil,
                timestamp: segment.startedAt,
                appBundleId: segment.bundleId,
                appName: segment.appName,
                windowTitle: segment.windowTitle,
                durationSeconds: duration
            )
            // Maintained incrementally rather than re-querying
            // `SELECT COUNT(*)` on every app/window switch — this runs on
            // every flush, so an O(rows) count would scale with history size
            // at the app's highest-frequency event.
            if await appRecordStore.insert(record) {
                recordCount += 1
            }
        }
    }

    // MARK: - App record queries (for TimelineViewModel)

    func records(for date: Date) async -> [AppRecord] {
        await appRecordStore.records(for: date)
    }

    /// Earliest date for which the autotracker still retains app records.
    /// Older records are deleted by `cleanup(olderThanDays:)` on launch.
    /// Used by the timeline date picker to clamp its lower bound.
    var earliestRetainedDate: Date {
        let days = settings?.autotrackerRetentionDays ?? 14
        return Calendar.current.date(byAdding: .day, value: -days, to: .now)
            ?? .now
    }

    /// Delete app records older than the given number of days from today.
    func cleanup(olderThanDays days: Int) async {
        let deleted = await appRecordStore.cleanup(olderThan: days)
        recordCount = max(0, recordCount - deleted)
        BreadcrumbTrail.shared.record("Autotracker", "Cleanup: records older than \(days) days removed")
    }

    /// Delete all recorded app-activity history. Used by the Autotracker
    /// settings "Clear tracked app history" action and by the full-app
    /// "Reset Everything" flow.
    func deleteAllRecords() async {
        let deleted = await appRecordStore.deleteAll()
        recordCount = max(0, recordCount - deleted)
        BreadcrumbTrail.shared.record("Autotracker", "All app activity records deleted")
    }

    /// Delete all automation rules. Used by the full-app "Reset Everything" flow.
    func deleteAllRules() async {
        do {
            try await ruleStore.deleteAll()
        } catch {
            Self.atLogger.error("Failed to delete all rules: \(error)")
        }
        BreadcrumbTrail.shared.record("Autotracker", "All automation rules deleted")
    }

    // MARK: - Rule Evaluation

    func evaluate(
        for date: Date,
        existingEntries: [ShadowEntry],
        events: [CalendarEvent] = [],
        timerRunning: Bool
    ) async {
        BreadcrumbTrail.shared.record("Autotracker", "Rule evaluation started")
        guard settings?.rulesEnabled == true else {
            Self.atLogger.debug("evaluate skipped — rulesEnabled is false")
            suggestions = []
            return
        }

        // Rules only apply to today and future dates — never create
        // suggestions or auto-entries for past days.
        let startOfToday = Calendar.current.startOfDay(for: clock())
        guard date >= startOfToday else {
            Self.atLogger.debug("evaluate skipped — date is in the past")
            suggestions = []
            return
        }

        let dateString = Self.atDateString(from: date)
        loadDeclinedIds(for: dateString)

        let rules: [TrackingRule]
        do {
            rules = try await ruleStore.enabledRules()
        } catch {
            Self.atLogger.error("Failed to load enabled rules: \(error)")
            suggestions = []
            return
        }

        guard !rules.isEmpty else {
            Self.atLogger.info("No enabled rules — skipping evaluation")
            suggestions = []
            return
        }

        BreadcrumbTrail.shared.record("Autotracker", "Evaluating \(rules.count) rules")
        let windowTitlesEnabled = settings?.windowTitleTrackingEnabled == true

        let records = await appRecordStore.records(for: date)
        let blocks = AppUsageBlock.merge(records)

        var newSuggestions: [Suggestion] = []
        var entriesCreated = 0
        let nowDate = clock()

        await atEvaluateAppRules(
            rules: rules,
            appUsageBlocks: blocks,
            existingEntries: existingEntries,
            windowTitlesEnabled: windowTitlesEnabled,
            now: nowDate,
            date: date,
            dateString: dateString,
            timerRunning: timerRunning,
            entriesCreated: &entriesCreated,
            newSuggestions: &newSuggestions
        )

        if settings?.calendarEnabled == true, !events.isEmpty {
            await atEvaluateCalendarRules(
                rules: rules,
                events: events,
                existingEntries: existingEntries,
                now: nowDate,
                timerRunning: timerRunning,
                entriesCreated: &entriesCreated,
                newSuggestions: &newSuggestions
            )
        }

        suggestions = newSuggestions
        BreadcrumbTrail.shared.record("Autotracker", "Evaluation done: \(newSuggestions.count) suggestions, \(entriesCreated) entries created")
        Self.atLogger.info("Evaluation complete: \(rules.count) rules, \(newSuggestions.count) suggestions, \(entriesCreated) entries created")

        if entriesCreated > 0 {
            await onEntryCreated?()
        }
    }

    // MARK: - Rule Evaluation Helpers

    /// Runs the app-block pass of the rule engine. Iterates over
    /// `appUsageBlocks`, filters `.app`-type rules, dedupes via
    /// `atIsDuplicate`, and mutates the accumulators for entries
    /// created or suggestions added. Called from `evaluate()`.
    private func atEvaluateAppRules(
        rules: [TrackingRule],
        appUsageBlocks: [AppUsageBlock],
        existingEntries: [ShadowEntry],
        windowTitlesEnabled: Bool,
        now: Date,
        date: Date,
        dateString: String,
        timerRunning: Bool,
        entriesCreated: inout Int,
        newSuggestions: inout [Suggestion]
    ) async {
        for block in appUsageBlocks {
            let matchingRules = rules.filter { Self.atRuleMatches($0, block: block, windowTitlesEnabled: windowTitlesEnabled) }

            for rule in matchingRules {
                guard let ruleId = rule.id else { continue }

                let blockStartTime = Self.atTimeString(from: block.startTime)
                let blockDuration = Int(block.durationSeconds)

                if Self.atIsDuplicate(rule: rule, startTime: blockStartTime, existingEntries: existingEntries) {
                    continue
                }

                switch rule.mode {
                case .create:
                    if timerRunning {
                        Self.atLogger.debug("Skipping create-mode rule '\(rule.name)' — timer is running")
                        continue
                    }
                    do {
                        let entry = Self.atMakeShadowEntry(
                            from: rule,
                            dateString: dateString,
                            startTime: blockStartTime,
                            durationSeconds: blockDuration,
                            existingEntries: existingEntries,
                            sourceAppBundleId: block.appBundleId,
                            appName: block.appName,
                            windowTitle: block.windowTitle,
                            now: now
                        )
                        try await shadowEntryStore.insert(entry)
                        entriesCreated += 1
                        Self.atLogger.info("Created entry for rule '\(rule.name)' at \(blockStartTime)")
                    } catch {
                        Self.atLogger.error("Failed to create entry for rule \(ruleId) at \(blockStartTime): \(error)")
                    }

                case .suggest:
                    let suggestionId = "\(ruleId)-\(blockStartTime)"
                    if declinedSuggestionIds.contains(suggestionId) { continue }
                    let resolvedDescription = Self.atResolveDescription(rule.description, appName: block.appName, windowTitle: block.windowTitle)
                    newSuggestions.append(Suggestion(
                        id: suggestionId,
                        ruleId: ruleId,
                        ruleName: rule.name,
                        startTime: blockStartTime,
                        durationSeconds: blockDuration,
                        projectId: rule.projectId,
                        projectName: rule.projectName,
                        taskId: rule.taskId,
                        taskName: rule.taskName,
                        description: resolvedDescription,
                        appName: block.appName,
                        appBundleId: block.appBundleId
                    ))
                }
            }
        }
    }

    /// Runs the calendar-event pass of the rule engine. Filters
    /// `.calendar`-type rules, gates each event on isAllDay / acceptance
    /// / startDate-in-past, dedupes via `atIsDuplicate`, and mutates the
    /// accumulators. Called from `evaluate()` only when calendarEnabled
    /// and events is non-empty.
    private func atEvaluateCalendarRules(
        rules: [TrackingRule],
        events: [CalendarEvent],
        existingEntries: [ShadowEntry],
        now: Date,
        timerRunning: Bool,
        entriesCreated: inout Int,
        newSuggestions: inout [Suggestion]
    ) async {
        let calendarRules = rules.filter { $0.ruleType == .calendar }
        guard !calendarRules.isEmpty else { return }

        for event in events {
            guard !event.isAllDay else { continue }
            guard event.isAcceptedByUser else { continue }
            guard event.startDate <= now else { continue }

            let matchingRules = calendarRules.filter { Self.atRuleMatches($0, event: event) }
            for rule in matchingRules {
                guard let ruleId = rule.id else { continue }

                let startTime = Self.atTimeString(from: event.startDate)
                let durationSeconds = max(event.durationMinutes * 60, 60)
                let eventDateString = Self.atDateString(from: event.startDate)

                if Self.atIsDuplicate(rule: rule, startTime: startTime, existingEntries: existingEntries) {
                    continue
                }

                let resolvedDescription = rule.description.isEmpty ? event.title : rule.description

                switch rule.mode {
                case .create:
                    if timerRunning {
                        Self.atLogger.debug("Skipping create-mode calendar rule '\(rule.name)' — timer is running")
                        continue
                    }
                    do {
                        var entry = Self.atMakeShadowEntry(
                            from: rule,
                            dateString: eventDateString,
                            startTime: startTime,
                            durationSeconds: durationSeconds,
                            existingEntries: existingEntries,
                            sourceAppBundleId: nil,
                            sourceCalendarEventId: event.calendarItemIdentifier,
                            now: now
                        )
                        // If the rule has no description set, fall
                        // back to the event title so the created
                        // entry is meaningful at a glance.
                        if rule.description.isEmpty {
                            entry.description = event.title
                        }
                        try await shadowEntryStore.insert(entry)
                        entriesCreated += 1
                        Self.atLogger.info("Created entry for calendar rule '\(rule.name)' at \(startTime)")
                    } catch {
                        Self.atLogger.error("Failed to create entry for calendar rule \(ruleId) at \(startTime): \(error)")
                    }

                case .suggest:
                    let suggestionId = "\(ruleId)-\(startTime)"
                    if declinedSuggestionIds.contains(suggestionId) { continue }
                    newSuggestions.append(Suggestion(
                        id: suggestionId,
                        ruleId: ruleId,
                        ruleName: rule.name,
                        startTime: startTime,
                        durationSeconds: durationSeconds,
                        projectId: rule.projectId,
                        projectName: rule.projectName,
                        taskId: rule.taskId,
                        taskName: rule.taskName,
                        description: resolvedDescription,
                        appName: event.title,
                        appBundleId: nil,
                        sourceCalendarEventId: event.calendarItemIdentifier
                    ))
                }
            }
        }
    }

    // MARK: - Suggestion Actions

    func approveSuggestion(_ suggestion: Suggestion) async {
        let nowDate = clock()
        let nowString = Autotracker.isoFormatter.string(from: nowDate)
        let dateString = loadedDeclinedDate ?? Self.atDateString(from: nowDate)

        let entry = ShadowEntry(
            id: nil,
            localId: UUID().uuidString,
            date: dateString,
            hours: Double(suggestion.durationSeconds) / 3600.0,
            seconds: suggestion.durationSeconds,
            workedSeconds: suggestion.durationSeconds,
            description: suggestion.description,
            billed: false,
            billable: true,
            tag: "",
            projectId: suggestion.projectId,
            projectName: suggestion.projectName,
            projectBillable: true,
            taskId: suggestion.taskId,
            taskName: suggestion.taskName,
            taskBillable: true,
            customerId: 0,
            customerName: "",
            userId: 0,
            userFirstname: "",
            userLastname: "",
            hourlyRate: 0,
            timerStartedAt: nil,
            startTime: suggestion.startTime,
            locked: false,
            createdAt: nowString,
            updatedAt: nowString,
            sync: ShadowEntry.SyncMeta(
                status: .pendingCreate,
                localUpdatedAt: nowString,
                serverUpdatedAt: nowString,
                conflictFlag: false
            ),
            origin: ShadowEntry.Origin(
                appBundleId: suggestion.appBundleId,
                ruleId: suggestion.ruleId,
                calendarEventId: suggestion.sourceCalendarEventId
            )
        )

        do {
            try await shadowEntryStore.insert(entry)
            suggestions.removeAll { $0.id == suggestion.id }
            Self.atLogger.info("Approved suggestion \(suggestion.id)")
            await onEntryCreated?()
        } catch {
            Self.atLogger.error("Failed to approve suggestion \(suggestion.id): \(error)")
        }
    }

    func declineSuggestion(_ suggestion: Suggestion) {
        declinedSuggestionIds.insert(suggestion.id)
        persistDeclinedIds()
        suggestions.removeAll { $0.id == suggestion.id }
        Self.atLogger.info("Declined suggestion \(suggestion.id)")
    }

    func approveAllSuggestions() async {
        let current = suggestions
        for suggestion in current {
            await approveSuggestion(suggestion)
        }
    }

    // MARK: - Rule CRUD (forwards to internal RuleStore)

    func allRules() async throws -> [TrackingRule] {
        try await ruleStore.allRules()
    }

    func insertRule(_ rule: TrackingRule) async throws -> Int64 {
        try await ruleStore.insert(rule)
    }

    func updateRule(_ rule: TrackingRule) async throws {
        try await ruleStore.update(rule)
    }

    func deleteRule(id: Int64) async throws {
        try await ruleStore.delete(id: id)
    }

    // MARK: - Rule Matching

    private static func atRuleMatches(_ rule: TrackingRule, block: AppUsageBlock, windowTitlesEnabled: Bool) -> Bool {
        guard rule.ruleType == .app else { return false }
        var hasAnyCriterion = false

        if let bundleId = rule.appBundleId, !bundleId.isEmpty {
            hasAnyCriterion = true
            if bundleId.caseInsensitiveCompare(block.appBundleId) != .orderedSame {
                return false
            }
        }

        if let pattern = rule.appNamePattern, !pattern.isEmpty {
            hasAnyCriterion = true
            if !block.appName.localizedCaseInsensitiveContains(pattern) {
                return false
            }
        }

        if let pattern = rule.windowTitlePattern, !pattern.isEmpty, windowTitlesEnabled {
            hasAnyCriterion = true
            // A rule that demands a window title requires the block to
            // actually have one captured. Feature disabled → rule skipped.
            guard let title = block.windowTitle, !title.isEmpty else { return false }
            if !title.localizedCaseInsensitiveContains(pattern) {
                return false
            }
        }

        return hasAnyCriterion
    }

    /// Returns true if `rule` is a calendar-type rule with a non-empty
    /// `eventTitlePattern` that substring-matches `event.title`
    /// (case-insensitive). Does NOT check eligibility — `evaluate`
    /// filters all-day, accepted, and startDate-in-past separately.
    private static func atRuleMatches(_ rule: TrackingRule, event: CalendarEvent) -> Bool {
        guard rule.ruleType == .calendar else { return false }
        guard let pattern = rule.eventTitlePattern, !pattern.isEmpty else { return false }
        return event.title.localizedCaseInsensitiveContains(pattern)
    }

    private static func atIsDuplicate(rule: TrackingRule, startTime: String, existingEntries: [ShadowEntry]) -> Bool {
        existingEntries.contains { entry in
            entry.projectId == rule.projectId
                && entry.taskId == rule.taskId
                && entry.startTime == startTime
        }
    }

    // MARK: - Description Template

    /// Replaces `{app}` and `{title}` placeholders in a rule's description
    /// template with the actual app name and window title from the matched
    /// usage block. Returns the original string unchanged when no placeholders
    /// are present.
    private static func atResolveDescription(
        _ template: String,
        appName: String? = nil,
        windowTitle: String? = nil
    ) -> String {
        var result = template
        if let appName { result = result.replacingOccurrences(of: "{app}", with: appName) }
        if let windowTitle { result = result.replacingOccurrences(of: "{title}", with: windowTitle) }
        return result
    }

    // MARK: - Entry Factory

    private static func atMakeShadowEntry(
        from rule: TrackingRule,
        dateString: String,
        startTime: String,
        durationSeconds: Int,
        existingEntries: [ShadowEntry],
        sourceAppBundleId: String?,
        sourceCalendarEventId: String? = nil,
        appName: String? = nil,
        windowTitle: String? = nil,
        now: Date
    ) -> ShadowEntry {
        let nowString = Autotracker.isoFormatter.string(from: now)
        let userEntry = existingEntries.first
        let resolvedDescription = atResolveDescription(rule.description, appName: appName, windowTitle: windowTitle)

        return ShadowEntry(
            id: nil,
            localId: UUID().uuidString,
            date: dateString,
            hours: Double(durationSeconds) / 3600.0,
            seconds: durationSeconds,
            workedSeconds: durationSeconds,
            description: resolvedDescription,
            billed: false,
            billable: true,
            tag: "",
            projectId: rule.projectId,
            projectName: rule.projectName,
            projectBillable: true,
            taskId: rule.taskId,
            taskName: rule.taskName,
            taskBillable: true,
            customerId: 0,
            customerName: "",
            userId: userEntry?.userId ?? 0,
            userFirstname: userEntry?.userFirstname ?? "",
            userLastname: userEntry?.userLastname ?? "",
            hourlyRate: userEntry?.hourlyRate ?? 0,
            timerStartedAt: nil,
            startTime: startTime,
            locked: false,
            createdAt: nowString,
            updatedAt: nowString,
            sync: ShadowEntry.SyncMeta(
                status: .pendingCreate,
                localUpdatedAt: nowString,
                serverUpdatedAt: nowString,
                conflictFlag: false
            ),
            origin: ShadowEntry.Origin(
                appBundleId: sourceAppBundleId,
                ruleId: rule.id,
                calendarEventId: sourceCalendarEventId
            )
        )
    }

    // MARK: - Declined Persistence

    private func loadDeclinedIds(for dateString: String) {
        guard loadedDeclinedDate != dateString else { return }
        let key = "declinedSuggestions_\(dateString)"
        let stored = declinedDefaults.stringArray(forKey: key) ?? []
        declinedSuggestionIds = Set(stored)
        loadedDeclinedDate = dateString
    }

    private func persistDeclinedIds() {
        guard let dateString = loadedDeclinedDate else { return }
        let key = "declinedSuggestions_\(dateString)"
        declinedDefaults.set(Array(declinedSuggestionIds), forKey: key)
    }

    // MARK: - Helpers

    private static func atTimeString(from date: Date) -> String {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", components.hour ?? 0, components.minute ?? 0)
    }

    private static let atDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static func atDateString(from date: Date) -> String {
        atDateFormatter.string(from: date)
    }
}

#if DEBUG
extension Autotracker {
    /// Test-only wrapper around the private `atRuleMatches` overload for
    /// calendar events. Exposes the matcher so unit tests can exercise it
    /// without going through the full `evaluate` pipeline. DO NOT use in
    /// production code.
    static func _testRuleMatches(_ rule: TrackingRule, event: CalendarEvent) -> Bool {
        atRuleMatches(rule, event: event)
    }

    /// Test-only wrapper around the private `atRuleMatches` overload for
    /// app usage blocks. DO NOT use in production code.
    static func _testRuleMatches(
        _ rule: TrackingRule,
        block: AppUsageBlock,
        windowTitlesEnabled: Bool
    ) -> Bool {
        atRuleMatches(rule, block: block, windowTitlesEnabled: windowTitlesEnabled)
    }
}
#endif
