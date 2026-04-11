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
                    self.handler?(.appActivated(bundleId: bundleId, appName: name, windowTitle: nil))
                }
                return
            }

            // Time-boxed off-main AX capture. The main actor is released
            // immediately — the handler fires when the title arrives or
            // after the 30 ms budget elapses, whichever is first.
            Task { [weak self] in
                let title = await AccessibilityPermission.capturefocusedWindowTitle(forProcess: pid)
                await MainActor.run {
                    self?.handler?(.appActivated(bundleId: bundleId, appName: name, windowTitle: title))
                }
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
    }
}

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
        self.recordCount = appRecordStore.recordCount()

        if let ns = resolvedWorkspace as? NSWorkspaceMonitor {
            ns.captureWindowTitles = { [weak settings] in
                settings?.windowTitleTrackingEnabled == true
            }
        }

        self.workspace.handler = { [weak self] event in
            self?.handleWorkspaceEvent(event)
        }
    }

    // MARK: - Lifecycle

    func start() {
        guard !isRecording else { return }
        isRecording = true
        workspace.start()
        if let frontmost = workspace.currentFrontmost {
            processAppChange(bundleId: frontmost.bundleId, appName: frontmost.appName, windowTitle: frontmost.windowTitle)
        }
        Self.atLogger.info("Recording started")
    }

    func stop() {
        pendingAppChangeTask?.cancel()
        pendingAppChangeTask = nil
        flushCurrentSegment()
        workspace.stop()
        isRecording = false
        currentAppName = nil
        Self.atLogger.info("Recording stopped")
    }

    private func handleWorkspaceEvent(_ event: WorkspaceEvent) {
        switch event {
        case .appActivated(let bundleId, let appName, let windowTitle):
            scheduleDebouncedAppChange(bundleId: bundleId, appName: appName, windowTitle: windowTitle)
        case .sleep:
            pendingAppChangeTask?.cancel()
            pendingAppChangeTask = nil
            flushCurrentSegment()
            Self.atLogger.debug("Paused for sleep/session resign")
        case .wake:
            guard isRecording else { return }
            if let frontmost = workspace.currentFrontmost {
                processAppChange(bundleId: frontmost.bundleId, appName: frontmost.appName, windowTitle: frontmost.windowTitle)
            }
            Self.atLogger.debug("Resumed after wake/session active")
        }
    }

    /// Collapse rapid app activations into one processAppChange call. Each
    /// new event cancels the previous pending task and schedules a fresh
    /// one; only the last event in a burst actually runs.
    private func scheduleDebouncedAppChange(bundleId: String, appName: String, windowTitle: String?) {
        pendingAppChangeTask?.cancel()
        pendingAppChangeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: self?.activationDebounce ?? .milliseconds(300))
            guard !Task.isCancelled, let self else { return }
            self.processAppChange(bundleId: bundleId, appName: appName, windowTitle: windowTitle)
        }
    }

    // MARK: - Coalescing (internal for testing)

    func processAppChange(bundleId: String, appName: String, windowTitle: String? = nil) {
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
            flushCurrentSegment()
            currentSegment = Segment(bundleId: bundleId, appName: appName, windowTitle: windowTitle, startedAt: now, lastSeenAt: now)
        }

        currentAppName = appName
    }

    private func flushCurrentSegment() {
        guard let segment = currentSegment else { return }
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
            appRecordStore.insert(record)
        }
        recordCount = appRecordStore.recordCount()
        currentSegment = nil
    }

    // MARK: - App record queries (for TimelineViewModel)

    func records(for date: Date) -> [AppRecord] {
        appRecordStore.records(for: date)
    }

    /// Earliest date for which the autotracker still retains app records.
    /// Older records are deleted by `cleanup(olderThanDays:)` on launch.
    /// Used by the timeline date picker to clamp its lower bound.
    var earliestRetainedDate: Date {
        let days = settings?.autotrackerRetentionDays ?? 14
        return Calendar.current.date(byAdding: .day, value: -days, to: Date())
            ?? Date()
    }

    /// Delete app records older than the given number of days from today.
    func cleanup(olderThanDays days: Int) {
        appRecordStore.cleanup(olderThan: days)
        recordCount = appRecordStore.recordCount()
    }

    // MARK: - Rule Evaluation

    func evaluate(
        for date: Date,
        existingEntries: [ShadowEntry],
        events: [CalendarEvent] = [],
        timerRunning: Bool
    ) async {
        guard settings?.rulesEnabled == true else {
            Self.atLogger.debug("evaluate skipped — rulesEnabled is false")
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

        let windowTitlesEnabled = settings?.windowTitleTrackingEnabled == true

        let records = appRecordStore.records(for: date)
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
                        description: rule.description,
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
        let nowString = ISO8601DateFormatter().string(from: nowDate)
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
            syncStatus: .pendingCreate,
            localUpdatedAt: nowString,
            serverUpdatedAt: nowString,
            conflictFlag: false,
            sourceAppBundleId: suggestion.appBundleId,
            sourceRuleId: suggestion.ruleId,
            sourceCalendarEventId: suggestion.sourceCalendarEventId
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

    // MARK: - Entry Factory

    private static func atMakeShadowEntry(
        from rule: TrackingRule,
        dateString: String,
        startTime: String,
        durationSeconds: Int,
        existingEntries: [ShadowEntry],
        sourceAppBundleId: String?,
        sourceCalendarEventId: String? = nil,
        now: Date
    ) -> ShadowEntry {
        let nowString = ISO8601DateFormatter().string(from: now)
        let userEntry = existingEntries.first

        return ShadowEntry(
            id: nil,
            localId: UUID().uuidString,
            date: dateString,
            hours: Double(durationSeconds) / 3600.0,
            seconds: durationSeconds,
            workedSeconds: durationSeconds,
            description: rule.description,
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
            syncStatus: .pendingCreate,
            localUpdatedAt: nowString,
            serverUpdatedAt: nowString,
            conflictFlag: false,
            sourceAppBundleId: sourceAppBundleId,
            sourceRuleId: rule.id,
            sourceCalendarEventId: sourceCalendarEventId
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
