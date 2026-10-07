import Testing
import Foundation
@testable import MocoCompanion

@MainActor
struct AutotrackerTests {

    // MARK: - Suggest Mode Tests

    @Test func suggestModeRuleWithMatchingBundleIdProducesSuggestion() async throws {
        let (engine, ruleStore, appRecordStore, _) = try makeEngine()

        let rule = sampleRule(mode: .suggest, appBundleId: "com.apple.Safari")
        _ = try await ruleStore.insert(rule)

        let today = Calendar.current.startOfDay(for: Date())
        let record = makeAppRecord(bundleId: "com.apple.Safari", name: "Safari", timestamp: makeDate(hour: 9, minute: 0), duration: 1800)
        await appRecordStore.insert(record)

        await engine.evaluate(for: today, existingEntries: [], timerRunning: false)

        #expect(engine.suggestions.count == 1)
        #expect(engine.suggestions.first?.appName == "Safari")
        #expect(engine.suggestions.first?.projectId == 100)
        #expect(engine.suggestions.first?.startTime == "09:00")
    }

    @Test func suggestModeRuleWithMatchingAppNamePatternProducesSuggestion() async throws {
        let (engine, ruleStore, appRecordStore, _) = try makeEngine()

        let rule = sampleRule(mode: .suggest, appBundleId: nil, appNamePattern: "Safari")
        _ = try await ruleStore.insert(rule)

        let today = Calendar.current.startOfDay(for: Date())
        let record = makeAppRecord(bundleId: "com.apple.Safari", name: "Safari", timestamp: makeDate(hour: 10, minute: 0), duration: 600)
        await appRecordStore.insert(record)

        await engine.evaluate(for: today, existingEntries: [], timerRunning: false)

        #expect(engine.suggestions.count == 1)
        #expect(engine.suggestions.first?.appName == "Safari")
    }

    @Test func disabledRuleProducesNoSuggestion() async throws {
        let (engine, ruleStore, appRecordStore, _) = try makeEngine()

        var rule = sampleRule(mode: .suggest, appBundleId: "com.apple.Safari")
        rule.enabled = false
        _ = try await ruleStore.insert(rule)

        let today = Calendar.current.startOfDay(for: Date())
        let record = makeAppRecord(bundleId: "com.apple.Safari", name: "Safari", timestamp: makeDate(hour: 9, minute: 0), duration: 1800)
        await appRecordStore.insert(record)

        await engine.evaluate(for: today, existingEntries: [], timerRunning: false)

        #expect(engine.suggestions.isEmpty)
    }

    @Test func ruleWithNoMatchCriteriaMatchesNothing() async throws {
        let (engine, ruleStore, appRecordStore, _) = try makeEngine()

        let rule = sampleRule(mode: .suggest, appBundleId: nil, appNamePattern: nil)
        _ = try await ruleStore.insert(rule)

        let today = Calendar.current.startOfDay(for: Date())
        let record = makeAppRecord(bundleId: "com.apple.Safari", name: "Safari", timestamp: makeDate(hour: 9, minute: 0), duration: 600)
        await appRecordStore.insert(record)

        await engine.evaluate(for: today, existingEntries: [], timerRunning: false)

        #expect(engine.suggestions.isEmpty)
    }

    // MARK: - Create Mode Tests

    @Test func createModeRuleCreatesShadowEntry() async throws {
        let (engine, ruleStore, appRecordStore, shadowEntryStore) = try makeEngine()

        let rule = sampleRule(mode: .create, appBundleId: "com.apple.Safari")
        _ = try await ruleStore.insert(rule)

        let today = Calendar.current.startOfDay(for: Date())
        let dateString = dateString(from: today)
        let record = makeAppRecord(bundleId: "com.apple.Safari", name: "Safari", timestamp: makeDate(hour: 9, minute: 0), duration: 1800)
        await appRecordStore.insert(record)

        await engine.evaluate(for: today, existingEntries: [], timerRunning: false)

        let entries = try await shadowEntryStore.entries(forDate: dateString)
        #expect(entries.count == 1)
        #expect(entries.first?.projectId == 100)
        #expect(entries.first?.taskId == 200)
        #expect(entries.first?.sync.status == .pendingCreate)
        #expect(entries.first?.startTime == "09:00")
    }

    @Test func createModeRuleSkipsWhenTimerRunning() async throws {
        let (engine, ruleStore, appRecordStore, shadowEntryStore) = try makeEngine()

        let rule = sampleRule(mode: .create, appBundleId: "com.apple.Safari")
        _ = try await ruleStore.insert(rule)

        let today = Calendar.current.startOfDay(for: Date())
        let dateString = dateString(from: today)
        let record = makeAppRecord(bundleId: "com.apple.Safari", name: "Safari", timestamp: makeDate(hour: 9, minute: 0), duration: 1800)
        await appRecordStore.insert(record)

        await engine.evaluate(for: today, existingEntries: [], timerRunning: true)

        let entries = try await shadowEntryStore.entries(forDate: dateString)
        #expect(entries.isEmpty)
        #expect(engine.suggestions.isEmpty)
    }

    // MARK: - Dedup Tests

    @Test func duplicateEntryForSameProjectTaskTimeIsNotCreated() async throws {
        let (engine, ruleStore, appRecordStore, shadowEntryStore) = try makeEngine()

        let rule = sampleRule(mode: .create, appBundleId: "com.apple.Safari")
        _ = try await ruleStore.insert(rule)

        let today = Calendar.current.startOfDay(for: Date())
        let dateString = dateString(from: today)
        let record = makeAppRecord(bundleId: "com.apple.Safari", name: "Safari", timestamp: makeDate(hour: 9, minute: 0), duration: 1800)
        await appRecordStore.insert(record)

        // Create an existing entry that covers this time
        let existingEntry = makeExistingEntry(
            date: dateString,
            startTime: "09:00",
            projectId: 100,
            taskId: 200
        )

        await engine.evaluate(for: today, existingEntries: [existingEntry], timerRunning: false)

        let entries = try await shadowEntryStore.entries(forDate: dateString)
        #expect(entries.isEmpty)
    }

    @Test func suggestModeDedupExcludesDuplicateSuggestion() async throws {
        let (engine, ruleStore, appRecordStore, _) = try makeEngine()

        let rule = sampleRule(mode: .suggest, appBundleId: "com.apple.Safari")
        _ = try await ruleStore.insert(rule)

        let today = Calendar.current.startOfDay(for: Date())
        let dateString = dateString(from: today)
        let record = makeAppRecord(bundleId: "com.apple.Safari", name: "Safari", timestamp: makeDate(hour: 9, minute: 0), duration: 1800)
        await appRecordStore.insert(record)

        let existingEntry = makeExistingEntry(
            date: dateString,
            startTime: "09:00",
            projectId: 100,
            taskId: 200
        )

        await engine.evaluate(for: today, existingEntries: [existingEntry], timerRunning: false)

        #expect(engine.suggestions.isEmpty)
    }

    // MARK: - Declined Tests

    @Test func declinedSuggestionIsExcludedFromResults() async throws {
        let (engine, ruleStore, appRecordStore, _) = try makeEngine()

        let rule = sampleRule(mode: .suggest, appBundleId: "com.apple.Safari")
        let ruleId = try await ruleStore.insert(rule)

        let today = Calendar.current.startOfDay(for: Date())
        let record = makeAppRecord(bundleId: "com.apple.Safari", name: "Safari", timestamp: makeDate(hour: 9, minute: 0), duration: 1800)
        await appRecordStore.insert(record)

        // First evaluation produces a suggestion
        await engine.evaluate(for: today, existingEntries: [], timerRunning: false)
        #expect(engine.suggestions.count == 1)

        // Decline it
        let suggestion = engine.suggestions[0]
        engine.declineSuggestion(suggestion)
        #expect(engine.suggestions.isEmpty)

        // Re-evaluate — declined suggestion should not reappear
        await engine.evaluate(for: today, existingEntries: [], timerRunning: false)
        #expect(engine.suggestions.isEmpty)
    }

    // MARK: - Approve Tests

    @Test func approveAllSuggestionsClearsAndCreatesEntries() async throws {
        let (engine, ruleStore, appRecordStore, shadowEntryStore) = try makeEngine()

        let rule = sampleRule(mode: .suggest, appBundleId: "com.apple.Safari")
        _ = try await ruleStore.insert(rule)

        let today = Calendar.current.startOfDay(for: Date())
        let dateString = dateString(from: today)
        let record = makeAppRecord(bundleId: "com.apple.Safari", name: "Safari", timestamp: makeDate(hour: 9, minute: 0), duration: 1800)
        await appRecordStore.insert(record)

        await engine.evaluate(for: today, existingEntries: [], timerRunning: false)
        #expect(engine.suggestions.count == 1)

        await engine.approveAllSuggestions()
        #expect(engine.suggestions.isEmpty)

        // Verify entry was created — note: approveSuggestion uses currentDateString() for date,
        // so we check across all entries in the store
        let entries = try await shadowEntryStore.entries(forDate: dateString)
        #expect(entries.count >= 1)
        let created = entries.first
        #expect(created?.projectId == 100)
        #expect(created?.taskId == 200)
        #expect(created?.sync.status == .pendingCreate)
    }

    // MARK: - Calendar Rule Tests

    @Test func calendarRuleCreatesShadowEntryStampedWithCalendarEventId() async throws {
        let (engine, ruleStore, _, shadowEntryStore) = try makeEngine(calendarEnabled: true)

        let rule = sampleCalendarRule(
            mode: .create,
            eventTitlePattern: "standup"
        )
        _ = try await ruleStore.insert(rule)

        // Event must be already-started (startDate <= now), accepted,
        // and not all-day. We anchor the event to `Date() - 1h` so the
        // `event.startDate <= clock()` gate is satisfied, and we derive
        // the target `today` from the event itself so the day boundary
        // is consistent even if the suite runs across midnight.
        let startDate = Date().addingTimeInterval(-3600)
        let endDate = startDate.addingTimeInterval(1800)
        let today = Calendar.current.startOfDay(for: startDate)
        let dateString = dateString(from: today)
        let expectedEventId = "calitem-\(UUID().uuidString)"
        let event = CalendarEvent(
            id: UUID().uuidString,
            calendarItemIdentifier: expectedEventId,
            title: "Engineering Standup",
            location: nil,
            startDate: startDate,
            endDate: endDate,
            isAllDay: false,
            isAcceptedByUser: true,
            calendarColorHex: "#808080"
        )

        await engine.evaluate(
            for: today,
            existingEntries: [],
            events: [event],
            timerRunning: false
        )

        let entries = try await shadowEntryStore.entries(forDate: dateString)
        #expect(entries.count == 1)
        #expect(entries.first?.projectId == 100)
        #expect(entries.first?.taskId == 200)
        #expect(entries.first?.sync.status == .pendingCreate)
        #expect(entries.first?.origin.calendarEventId == expectedEventId)
        #expect(entries.first?.description == "Engineering Standup")
    }

    @Test("Overlapping evaluations return their own results and only the latest publishes",
          arguments: ["different-day", "skipped", "declined-next-day"])
    func evaluationResultsAreScopedToInvocation(scenario: String) async throws {
        let now = regressionDate
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now)!
        let (engine, rules, records, _) = try makeEngine(now: now)
        _ = try await rules.insert(sampleRule(mode: .suggest))
        await records.insert(makeAppRecord(bundleId: "com.apple.Safari", name: "Today App",
                                            timestamp: now, duration: 600))
        await records.insert(makeAppRecord(bundleId: "com.apple.Safari", name: "Tomorrow App",
                                            timestamp: tomorrow, duration: 600))
        if scenario == "declined-next-day" {
            let initial = await engine.evaluate(for: tomorrow, existingEntries: [], timerRunning: false)
            engine.declineSuggestion(try #require(initial.first))
        }

        let gate = EvaluationGate()
        engine._testBeforeRuleEvaluation = { date in
            if date == now { await gate.pause() }
        }
        let older = Task { await engine.evaluate(for: now, existingEntries: [], timerRunning: false) }
        await gate.waitUntilPaused()
        let newerDate = scenario == "skipped"
            ? Calendar.current.date(byAdding: .day, value: -1, to: now)!
            : tomorrow
        let newer = await engine.evaluate(for: newerDate, existingEntries: [], timerRunning: false)
        gate.resume()
        let earlierResult = await older.value

        // Both dates use the same rule and HH:mm, so a leaked declined-ID set
        // would incorrectly suppress today's per-call result.
        #expect(earlierResult.map(\.appName) == ["Today App"])
        let expected = scenario == "different-day" ? ["Tomorrow App"] : []
        #expect(newer.map(\.appName) == expected)
        #expect(engine.suggestions.map(\.appName) == expected)
    }

    @MainActor
    private final class EvaluationGate {
        private var paused = false
        private var waiter: CheckedContinuation<Void, Never>?
        private var release: CheckedContinuation<Void, Never>?

        func pause() async {
            await withCheckedContinuation { continuation in
                release = continuation
                paused = true
                waiter?.resume()
                waiter = nil
            }
        }

        func waitUntilPaused() async {
            if paused { return }
            await withCheckedContinuation { waiter = $0 }
        }

        func resume() {
            release?.resume()
            release = nil
        }
    }

    // MARK: - Rule safety regressions

    @Test("Title-dependent create rules produce no booking when capture is off")
    func titleCreateRuleDoesNotBroaden() async throws {
        let now = regressionDate
        let (engine, rules, records, entries) = try makeEngine(now: now, windowTitlesEnabled: false)
        var rule = sampleRule(mode: .create)
        rule.windowTitlePattern = "Client"
        _ = try await rules.insert(rule)
        await records.insert(AppRecord(id: nil, timestamp: now.addingTimeInterval(-1800),
                                       appBundleId: "com.apple.Safari", appName: "Safari",
                                       windowTitle: "Client dashboard", durationSeconds: 600))
        await engine.evaluate(for: now, existingEntries: [], timerRunning: false)
        #expect(try await entries.entries(forDate: dateString(from: now)).isEmpty)
        #expect(engine.suggestions.isEmpty)
    }

    @Test("Two matching app rules create one booking, including on stale reevaluation")
    func duplicateAppRulesCreateOneBooking() async throws {
        let now = regressionDate
        let (engine, rules, records, entries) = try makeEngine(now: now)
        _ = try await rules.insert(sampleRule(mode: .create))
        var second = sampleRule(mode: .create)
        second.name = "Second rule"
        _ = try await rules.insert(second)
        await records.insert(makeAppRecord(bundleId: "com.apple.Safari", name: "Safari",
                                            timestamp: now.addingTimeInterval(-1800), duration: 600))
        await engine.evaluate(for: now, existingEntries: [], timerRunning: false)
        #expect(try await entries.entries(forDate: dateString(from: now)).count == 1)
        await engine.evaluate(for: now, existingEntries: [], timerRunning: false)
        #expect(try await entries.entries(forDate: dateString(from: now)).count == 1)
    }

    @Test("Past-date guard uses the injected calendar, not Calendar.current")
    func pastDateGuardUsesInjectedCalendar() async throws {
        // 09:00Z is already March 10 in UTC+14, so March 10 local started 10:00Z on the 9th.
        var kiritimati = Calendar(identifier: .gregorian)
        kiritimati.timeZone = TimeZone(identifier: "Pacific/Kiritimati")!
        let now = Date(timeIntervalSince1970: 1_773_133_200) // 2026-03-10T09:00:00Z
        let (engine, rules, records, _) = try makeEngine(now: now, calendar: kiritimati)
        _ = try await rules.insert(sampleRule(mode: .suggest))
        let today = kiritimati.startOfDay(for: now)
        await records.insert(makeAppRecord(bundleId: "com.apple.Safari", name: "Safari",
                                            timestamp: today.addingTimeInterval(7200), duration: 1800))

        await engine.evaluate(for: today, existingEntries: [], timerRunning: false)

        #expect(engine.suggestions.count == 1)
    }

    @Test("App and calendar passes share occupied booking keys")
    func appAndCalendarRulesCreateOneBooking() async throws {
        let now = regressionDate
        let (engine, rules, records, entries) = try makeEngine(calendarEnabled: true, now: now)
        _ = try await rules.insert(sampleRule(mode: .create))
        _ = try await rules.insert(sampleCalendarRule(mode: .create, eventTitlePattern: "Standup"))
        let start = now.addingTimeInterval(-1800)
        await records.insert(makeAppRecord(bundleId: "com.apple.Safari", name: "Safari",
                                            timestamp: start, duration: 600))
        await engine.evaluate(for: now, existingEntries: [], events: [regressionEvent(start: start)], timerRunning: false)
        #expect(try await entries.entries(forDate: dateString(from: now)).count == 1)
    }

    @Test("Calendar rules and overlapping evaluations cannot duplicate bookings")
    func concurrentCalendarEvaluationsCreateOneBooking() async throws {
        let now = regressionDate
        let (engine, rules, _, entries) = try makeEngine(calendarEnabled: true, now: now)
        _ = try await rules.insert(sampleCalendarRule(mode: .create, eventTitlePattern: "Standup"))
        _ = try await rules.insert(sampleCalendarRule(mode: .create, eventTitlePattern: "Team"))
        let event = regressionEvent(start: now.addingTimeInterval(-1800))
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<4 {
                group.addTask {
                    await engine.evaluate(for: now, existingEntries: [], events: [event], timerRunning: false)
                }
            }
        }
        #expect(try await entries.entries(forDate: dateString(from: now)).count == 1)
    }

    @Test("Booking identity includes the date and ignores pending deletion")
    func unrelatedOrDeletedEntryDoesNotBlockBooking() async throws {
        let now = regressionDate
        let (engine, rules, records, entries) = try makeEngine(now: now)
        _ = try await rules.insert(sampleRule(mode: .create))
        let start = now.addingTimeInterval(-1800)
        await records.insert(makeAppRecord(bundleId: "com.apple.Safari", name: "Safari", timestamp: start, duration: 600))
        let time = TimelineGeometry.timeString(from: start)
        var deleted = makeExistingEntry(date: dateString(from: now), startTime: time, projectId: 100, taskId: 200)
        deleted.sync.status = .pendingDelete
        let otherDay = makeExistingEntry(date: "2000-01-01", startTime: time, projectId: 100, taskId: 200)
        await engine.evaluate(for: now, existingEntries: [deleted, otherDay], timerRunning: false)
        #expect(try await entries.entries(forDate: dateString(from: now)).count == 1)
    }

    @Test("Evaluation during undo grace does not replace a hidden booking")
    func undoableDeletionStillOccupiesBooking() async throws {
        let now = regressionDate
        let (engine, rules, records, entries) = try makeEngine(now: now)
        _ = try await rules.insert(sampleRule(mode: .create))
        let start = now.addingTimeInterval(-1800)
        await records.insert(makeAppRecord(bundleId: "com.apple.Safari", name: "Safari", timestamp: start, duration: 600))
        let original = makeExistingEntry(date: dateString(from: now), startTime: TimelineGeometry.timeString(from: start),
                                         projectId: 100, taskId: 200)
        try await entries.insert(original)
        let saved = try #require(try await entries.beginUndoableDelete(id: 999))
        await engine.evaluate(for: now, existingEntries: [], timerRunning: false)
        let duringGrace = try await entries.entries(forDate: dateString(from: now))
        #expect(duringGrace.count == 1)
        #expect(duringGrace.first?.sync.status == .pendingDelete)
        try await entries.restoreUndoableDelete(saved)
        let restored = try await entries.entries(forDate: dateString(from: now))
        #expect(restored.count == 1)
        #expect(restored.first?.id == 999)
        #expect(restored.first?.sync.status == .synced)
    }

    @Test("Approving the same suggestion twice creates one booking")
    func duplicateApprovalCreatesOneBooking() async throws {
        let now = regressionDate
        let (engine, rules, records, entries) = try makeEngine(now: now)
        _ = try await rules.insert(sampleRule(mode: .suggest))
        await records.insert(makeAppRecord(bundleId: "com.apple.Safari", name: "Safari",
                                            timestamp: now.addingTimeInterval(-1800), duration: 600))
        await engine.evaluate(for: now, existingEntries: [], timerRunning: false)
        let suggestion = try #require(engine.suggestions.first)
        await engine.approveSuggestion(suggestion)
        await engine.approveSuggestion(suggestion)
        #expect(try await entries.entries(forDate: dateString(from: now)).count == 1)
    }

    private var regressionDate: Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: 15, hour: 12))!
    }

    private func regressionEvent(start: Date) -> CalendarEvent {
        CalendarEvent(id: "event", calendarItemIdentifier: "calendar-item", title: "Team Standup",
                      location: nil, startDate: start, endDate: start.addingTimeInterval(600),
                      isAllDay: false, isAcceptedByUser: true, calendarColorHex: "#808080")
    }

    // MARK: - Helpers

    private func sampleCalendarRule(
        mode: RuleMode,
        eventTitlePattern: String
    ) -> TrackingRule {
        TrackingRule(
            id: nil,
            name: "Calendar Test Rule",
            appBundleId: nil,
            appNamePattern: nil,
            windowTitlePattern: nil,
            eventTitlePattern: eventTitlePattern,
            mode: mode,
            ruleType: .calendar,
            projectId: 100,
            projectName: "Test Project",
            taskId: 200,
            taskName: "Meetings",
            description: "",
            enabled: true,
            createdAt: "",
            updatedAt: ""
        )
    }

    private func makeEngine(
        calendarEnabled: Bool = false,
        now: Date? = nil,
        windowTitlesEnabled: Bool = false,
        calendar: Calendar = .current
    ) throws -> (Autotracker, RuleStore, AppRecordStore, ShadowEntryStore) {
        let ruleDb = try SQLiteDatabase(path: ":memory:")
        let ruleStore = try RuleStore(database: ruleDb)

        let appRecordStore = try AppRecordStore(inMemory: true)

        let shadowDb = try SQLiteDatabase(path: ":memory:")
        let shadowEntryStore = try ShadowEntryStore(database: shadowDb)

        // Ephemeral UserDefaults per test so declined-suggestion state does not
        // leak across runs (or across parallel tests in the same suite).
        let defaults = UserDefaults(suiteName: "autotracker-test-\(UUID().uuidString)")!

        // Task 7 added a top-level `settings?.rulesEnabled == true` gate to
        // `evaluate`. Tests must supply a SettingsStore with that flag set
        // or the gate short-circuits and no rules fire. We construct a
        // real SettingsStore (the only constructor it offers) and flip
        // the relevant flags post-init — it's a @MainActor observable
        // object with plain `var` properties, so this is safe.
        let settings = SettingsStore()
        settings.rulesEnabled = true
        settings.appRecordingEnabled = true
        settings.calendarEnabled = calendarEnabled
        settings.windowTitleTrackingEnabled = windowTitlesEnabled

        let engine = Autotracker(
            shadowEntryStore: shadowEntryStore,
            appRecordStore: appRecordStore,
            ruleStore: ruleStore,
            settings: settings,
            clock: { now ?? Date() },
            calendar: calendar,
            declinedDefaults: defaults
        )

        return (engine, ruleStore, appRecordStore, shadowEntryStore)
    }

    private func sampleRule(
        mode: RuleMode,
        appBundleId: String? = "com.apple.Safari",
        appNamePattern: String? = nil
    ) -> TrackingRule {
        TrackingRule(
            id: nil,
            name: "Test Rule",
            appBundleId: appBundleId,
            appNamePattern: appNamePattern,
            windowTitlePattern: nil,
            eventTitlePattern: nil,
            mode: mode,
            ruleType: .app,
            projectId: 100,
            projectName: "Test Project",
            taskId: 200,
            taskName: "Development",
            description: "Auto-tracked",
            enabled: true,
            createdAt: "",
            updatedAt: ""
        )
    }

    private func makeDate(hour: Int, minute: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date())!
    }

    private func makeAppRecord(
        bundleId: String,
        name: String,
        timestamp: Date,
        duration: TimeInterval
    ) -> AppRecord {
        AppRecord(
            id: nil,
            timestamp: timestamp,
            appBundleId: bundleId,
            appName: name,
            windowTitle: nil,
            durationSeconds: duration
        )
    }

    private func makeExistingEntry(
        date: String,
        startTime: String,
        projectId: Int,
        taskId: Int
    ) -> ShadowEntry {
        let now = ISO8601DateFormatter().string(from: Date())
        return ShadowEntry(
            id: 999,
            localId: UUID().uuidString,
            date: date,
            hours: 0.5,
            seconds: 1800,
            workedSeconds: 1800,
            description: "Existing",
            billed: false,
            billable: true,
            tag: "",
            projectId: projectId,
            projectName: "Existing Project",
            projectBillable: true,
            taskId: taskId,
            taskName: "Existing Task",
            taskBillable: true,
            customerId: 0,
            customerName: "",
            userId: 0,
            userFirstname: "",
            userLastname: "",
            hourlyRate: 0,
            timerStartedAt: nil,
            startTime: startTime,
            locked: false,
            createdAt: now,
            updatedAt: now,
            sync: ShadowEntry.SyncMeta(
                status: .synced,
                localUpdatedAt: now,
                serverUpdatedAt: now,
                conflictFlag: false
            ),
            origin: ShadowEntry.Origin()
        )
    }

    private func dateString(from date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: date)
    }
}
