import AppKit
import Foundation
import os

// MARK: - Workspace Monitor Port

/// Events emitted by a `WorkspaceMonitor` as the user's foreground app changes
/// or the machine enters/leaves a sleeping state. Production adapter converts
/// NSWorkspace notifications into these events; tests drive them directly.
enum WorkspaceEvent: Sendable {
    case appActivated(bundleId: String, appName: String)
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
    var currentFrontmost: (bundleId: String, appName: String)? { get }
}

/// Production `WorkspaceMonitor` that observes NSWorkspace notifications.
@MainActor
final class NSWorkspaceMonitor: WorkspaceMonitor {
    var handler: ((WorkspaceEvent) -> Void)?
    private var observers: [NSObjectProtocol] = []

    var currentFrontmost: (bundleId: String, appName: String)? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let bundleId = app.bundleIdentifier,
              let name = app.localizedName else { return nil }
        return (bundleId, name)
    }

    func start() {
        guard observers.isEmpty else { return }
        let ws = NSWorkspace.shared.notificationCenter

        observers.append(ws.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let bundleId = app?.bundleIdentifier
            let name = app?.localizedName
            MainActor.assumeIsolated {
                guard let self, let bundleId, let name else { return }
                self.handler?(.appActivated(bundleId: bundleId, appName: name))
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
        var startedAt: Date
        var lastSeenAt: Date
    }

    private var currentSegment: Segment?
    private let coalescingThreshold: TimeInterval = 10.0
    private var pollingTask: Task<Void, Never>?

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
        self.workspace = workspace ?? NSWorkspaceMonitor()
        self.clock = clock
        self.declinedDefaults = declinedDefaults
        self.recordCount = appRecordStore.recordCount()

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
            processAppChange(bundleId: frontmost.bundleId, appName: frontmost.appName)
        }
        startPolling()
        Self.atLogger.info("Recording started")
    }

    func stop() {
        flushCurrentSegment()
        stopPolling()
        workspace.stop()
        isRecording = false
        currentAppName = nil
        Self.atLogger.info("Recording stopped")
    }

    private func handleWorkspaceEvent(_ event: WorkspaceEvent) {
        switch event {
        case .appActivated(let bundleId, let appName):
            processAppChange(bundleId: bundleId, appName: appName)
        case .sleep:
            flushCurrentSegment()
            stopPolling()
            Self.atLogger.debug("Paused for sleep/session resign")
        case .wake:
            guard isRecording else { return }
            startPolling()
            if let frontmost = workspace.currentFrontmost {
                processAppChange(bundleId: frontmost.bundleId, appName: frontmost.appName)
            }
            Self.atLogger.debug("Resumed after wake/session active")
        }
    }

    // MARK: - Coalescing (internal for testing)

    func processAppChange(bundleId: String, appName: String) {
        guard !filteredBundleIds.contains(bundleId) else { return }
        let now = clock()

        if currentSegment == nil {
            currentSegment = Segment(bundleId: bundleId, appName: appName, startedAt: now, lastSeenAt: now)
        } else if currentSegment!.bundleId == bundleId {
            currentSegment!.lastSeenAt = now
        } else {
            flushCurrentSegment()
            currentSegment = Segment(bundleId: bundleId, appName: appName, startedAt: now, lastSeenAt: now)
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
                windowTitle: nil,
                durationSeconds: duration
            )
            appRecordStore.insert(record)
        }
        recordCount = appRecordStore.recordCount()
        currentSegment = nil
    }

    private func startPolling() {
        stopPolling()
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { break }
                self?.currentSegment?.lastSeenAt = self?.clock() ?? Date()
            }
        }
    }

    private func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
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

        // MARK: App rule pass

        for block in blocks {
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
                            now: clock()
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

        // MARK: Calendar rule pass
        //
        // Gated on calendarEnabled + non-empty events. Calendar events
        // only fire rules when the meeting has already started (no
        // entries for future events), is accepted (declined/tentative
        // don't auto-create), and is not all-day (all-day events are
        // shown in the aboveline region, not tracked as entries).

        if settings?.calendarEnabled == true, !events.isEmpty {
            let calendarRules = rules.filter { $0.ruleType == .calendar }
            if !calendarRules.isEmpty {
                let nowDate = clock()
                for event in events {
                    guard !event.isAllDay else { continue }
                    guard event.isAcceptedByUser else { continue }
                    guard event.startDate <= nowDate else { continue }

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
                                    now: nowDate
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
        }

        suggestions = newSuggestions
        Self.atLogger.info("Evaluation complete: \(rules.count) rules, \(newSuggestions.count) suggestions, \(entriesCreated) entries created")

        if entriesCreated > 0 {
            await onEntryCreated?()
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
