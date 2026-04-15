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
        appRecordStore.insert(record)

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
        appRecordStore.insert(record)

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
        appRecordStore.insert(record)

        await engine.evaluate(for: today, existingEntries: [], timerRunning: false)

        #expect(engine.suggestions.isEmpty)
    }

    @Test func ruleWithNoMatchCriteriaMatchesNothing() async throws {
        let (engine, ruleStore, appRecordStore, _) = try makeEngine()

        let rule = sampleRule(mode: .suggest, appBundleId: nil, appNamePattern: nil)
        _ = try await ruleStore.insert(rule)

        let today = Calendar.current.startOfDay(for: Date())
        let record = makeAppRecord(bundleId: "com.apple.Safari", name: "Safari", timestamp: makeDate(hour: 9, minute: 0), duration: 600)
        appRecordStore.insert(record)

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
        appRecordStore.insert(record)

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
        appRecordStore.insert(record)

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
        appRecordStore.insert(record)

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
        appRecordStore.insert(record)

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
        appRecordStore.insert(record)

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
        appRecordStore.insert(record)

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
        calendarEnabled: Bool = false
    ) throws -> (Autotracker, RuleStore, AppRecordStore, ShadowEntryStore) {
        let ruleDb = try SQLiteDatabase(path: ":memory:")
        let ruleStore = try RuleStore(database: ruleDb)

        let appRecordStore = AppRecordStore(inMemory: true)

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

        let engine = Autotracker(
            shadowEntryStore: shadowEntryStore,
            appRecordStore: appRecordStore,
            ruleStore: ruleStore,
            settings: settings,
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
