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
        #expect(entries.first?.syncStatus == .pendingCreate)
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
        #expect(created?.syncStatus == .pendingCreate)
    }

    // MARK: - Helpers

    private func makeEngine() throws -> (Autotracker, RuleStore, AppRecordStore, ShadowEntryStore) {
        let ruleDb = try SQLiteDatabase(path: ":memory:")
        let ruleStore = try RuleStore(database: ruleDb)

        let appRecordStore = AppRecordStore(inMemory: true)

        let shadowDb = try SQLiteDatabase(path: ":memory:")
        let shadowEntryStore = try ShadowEntryStore(database: shadowDb)

        // Ephemeral UserDefaults per test so declined-suggestion state does not
        // leak across runs (or across parallel tests in the same suite).
        let defaults = UserDefaults(suiteName: "autotracker-test-\(UUID().uuidString)")!

        let engine = Autotracker(
            shadowEntryStore: shadowEntryStore,
            appRecordStore: appRecordStore,
            ruleStore: ruleStore,
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
            mode: mode,
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
            syncStatus: .synced,
            localUpdatedAt: now,
            serverUpdatedAt: now,
            conflictFlag: false,
            sourceAppBundleId: nil,
            sourceRuleId: nil
        )
    }

    private func dateString(from date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: date)
    }
}
