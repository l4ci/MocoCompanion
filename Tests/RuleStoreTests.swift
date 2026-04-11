import Testing
@testable import MocoCompanion

@Suite("RuleStore")
struct RuleStoreTests {

    private func makeStore() throws -> RuleStore {
        let db = try SQLiteDatabase(path: ":memory:")
        return try RuleStore(database: db)
    }

    private func sampleRule(
        name: String = "Test Rule",
        mode: RuleMode = .suggest,
        enabled: Bool = true
    ) -> TrackingRule {
        TrackingRule(
            id: nil,
            name: name,
            appBundleId: "com.apple.Safari",
            appNamePattern: "Safari",
            windowTitlePattern: "Jira.*",
            eventTitlePattern: nil,
            mode: mode,
            ruleType: .app,
            projectId: 100,
            projectName: "Test Project",
            taskId: 200,
            taskName: "Test Task",
            description: "Auto-tracked from Safari",
            enabled: enabled,
            createdAt: "",
            updatedAt: ""
        )
    }

    // MARK: - Insert

    @Test("insert returns valid id")
    func insertReturnsValidId() async throws {
        let store = try makeStore()
        let id = try await store.insert(sampleRule())
        #expect(id > 0)
    }

    @Test("insert with empty name succeeds")
    func insertEmptyName() async throws {
        let store = try makeStore()
        let id = try await store.insert(sampleRule(name: ""))
        #expect(id > 0)
    }

    // MARK: - All Rules

    @Test("allRules returns inserted rules")
    func allRulesReturnsInserted() async throws {
        let store = try makeStore()
        let id1 = try await store.insert(sampleRule(name: "Alpha"))
        let id2 = try await store.insert(sampleRule(name: "Beta"))

        let rules = try await store.allRules()
        #expect(rules.count == 2)
        #expect(rules[0].id == id1)
        #expect(rules[0].name == "Alpha")
        #expect(rules[1].id == id2)
        #expect(rules[1].name == "Beta")
    }

    @Test("allRules on empty store returns empty array")
    func allRulesEmpty() async throws {
        let store = try makeStore()
        let rules = try await store.allRules()
        #expect(rules.isEmpty)
    }

    // MARK: - Enabled Rules

    @Test("enabledRules filters disabled rules")
    func enabledRulesFilters() async throws {
        let store = try makeStore()
        _ = try await store.insert(sampleRule(name: "Active", enabled: true))
        _ = try await store.insert(sampleRule(name: "Disabled", enabled: false))

        let enabled = try await store.enabledRules()
        #expect(enabled.count == 1)
        #expect(enabled[0].name == "Active")
    }

    @Test("enabledRules excludes after update disables rule")
    func enabledRulesAfterDisable() async throws {
        let store = try makeStore()
        let id = try await store.insert(sampleRule(name: "Will Disable", enabled: true))

        var rule = (try await store.allRules()).first!
        #expect(rule.id == id)

        rule.enabled = false
        try await store.update(rule)

        let enabled = try await store.enabledRules()
        #expect(enabled.isEmpty)
    }

    // MARK: - Update

    @Test("update modifies fields")
    func updateModifiesFields() async throws {
        let store = try makeStore()
        let id = try await store.insert(sampleRule())

        var rule = (try await store.allRules()).first!
        #expect(rule.id == id)

        rule.name = "Updated Name"
        rule.mode = .create
        rule.description = "New description"
        try await store.update(rule)

        let updated = (try await store.allRules()).first!
        #expect(updated.name == "Updated Name")
        #expect(updated.mode == .create)
        #expect(updated.description == "New description")
    }

    // MARK: - Delete

    @Test("delete removes rule")
    func deleteRemovesRule() async throws {
        let store = try makeStore()
        let id = try await store.insert(sampleRule())

        try await store.delete(id: id)
        let rules = try await store.allRules()
        #expect(rules.isEmpty)
    }

    @Test("delete non-existent id does not throw")
    func deleteNonExistent() async throws {
        let store = try makeStore()
        try await store.delete(id: 999)
    }

    // MARK: - Round-Trip Field Integrity

    @Test("all fields round-trip correctly")
    func fieldRoundTrip() async throws {
        let store = try makeStore()
        _ = try await store.insert(sampleRule())

        let rule = (try await store.allRules()).first!
        #expect(rule.appBundleId == "com.apple.Safari")
        #expect(rule.appNamePattern == "Safari")
        #expect(rule.windowTitlePattern == "Jira.*")
        #expect(rule.mode == .suggest)
        #expect(rule.projectId == 100)
        #expect(rule.projectName == "Test Project")
        #expect(rule.taskId == 200)
        #expect(rule.taskName == "Test Task")
        #expect(rule.description == "Auto-tracked from Safari")
        #expect(rule.enabled == true)
        #expect(!rule.createdAt.isEmpty)
        #expect(!rule.updatedAt.isEmpty)
    }
}
