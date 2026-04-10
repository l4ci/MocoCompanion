import Foundation
import os

/// Evaluates tracking rules against recorded app usage and produces suggestions
/// or creates shadow entries automatically.
@Observable @MainActor final class RuleEngine {

    private static let logger = Logger(category: "RuleEngine")

    // MARK: - Dependencies

    private let ruleStore: RuleStore
    private let appRecordStore: AppRecordStore
    private let shadowEntryStore: ShadowEntryStore

    // MARK: - Observable State

    private(set) var suggestions: [Suggestion] = []

    // MARK: - Declined Tracking

    private var declinedSuggestionIds: Set<String> = []
    private var loadedDeclinedDate: String?

    // MARK: - Init

    init(ruleStore: RuleStore, appRecordStore: AppRecordStore, shadowEntryStore: ShadowEntryStore) {
        self.ruleStore = ruleStore
        self.appRecordStore = appRecordStore
        self.shadowEntryStore = shadowEntryStore
    }

    // MARK: - Evaluation

    func evaluate(for date: Date, existingEntries: [ShadowEntry], timerRunning: Bool) async {
        let dateString = Self.dateString(from: date)

        // Load declined IDs for this date
        loadDeclinedIds(for: dateString)

        // Load enabled rules (async actor call)
        let rules: [TrackingRule]
        do {
            rules = try await ruleStore.enabledRules()
        } catch {
            Self.logger.error("Failed to load enabled rules: \(error)")
            suggestions = []
            return
        }

        guard !rules.isEmpty else {
            Self.logger.info("No enabled rules — skipping evaluation")
            suggestions = []
            return
        }

        // Load app records for date and merge into blocks
        let records = appRecordStore.records(for: date)
        let blocks = TimelineViewModel.mergeIntoBlocks(records)

        var newSuggestions: [Suggestion] = []
        var entriesCreated = 0

        for block in blocks {
            let matchingRules = rules.filter { Self.ruleMatches($0, block: block) }

            for rule in matchingRules {
                guard let ruleId = rule.id else { continue }

                let blockStartTime = Self.timeString(from: block.startTime)
                let blockDuration = Int(block.durationSeconds)

                // Dedup: skip if existing entry covers same project+task+time
                if Self.isDuplicate(rule: rule, startTime: blockStartTime, existingEntries: existingEntries) {
                    continue
                }

                switch rule.mode {
                case .create:
                    if timerRunning {
                        Self.logger.debug("Skipping create-mode rule '\(rule.name)' — timer is running")
                        continue
                    }
                    do {
                        let entry = Self.makeShadowEntry(
                            from: rule,
                            dateString: dateString,
                            startTime: blockStartTime,
                            durationSeconds: blockDuration,
                            existingEntries: existingEntries
                        )
                        try await shadowEntryStore.insert(entry)
                        entriesCreated += 1
                        Self.logger.info("Created entry for rule '\(rule.name)' at \(blockStartTime)")
                    } catch {
                        Self.logger.error("Failed to create entry for rule \(ruleId) at \(blockStartTime): \(error)")
                    }

                case .suggest:
                    let suggestionId = "\(ruleId)-\(blockStartTime)"
                    if declinedSuggestionIds.contains(suggestionId) {
                        continue
                    }
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
                        appName: block.appName
                    ))
                }
            }
        }

        suggestions = newSuggestions
        Self.logger.info("Evaluation complete: \(rules.count) rules, \(newSuggestions.count) suggestions, \(entriesCreated) entries created")
    }

    // MARK: - Suggestion Actions

    func approveSuggestion(_ suggestion: Suggestion) async {
        let now = ISO8601DateFormatter().string(from: Date())
        let dateString = loadedDeclinedDate ?? Self.dateString(from: Date())

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
            createdAt: now,
            updatedAt: now,
            syncStatus: .pendingCreate,
            localUpdatedAt: now,
            serverUpdatedAt: now,
            conflictFlag: false
        )

        do {
            try await shadowEntryStore.insert(entry)
            suggestions.removeAll { $0.id == suggestion.id }
            Self.logger.info("Approved suggestion \(suggestion.id)")
        } catch {
            Self.logger.error("Failed to approve suggestion \(suggestion.id): \(error)")
        }
    }

    func declineSuggestion(_ suggestion: Suggestion) {
        declinedSuggestionIds.insert(suggestion.id)
        persistDeclinedIds()
        suggestions.removeAll { $0.id == suggestion.id }
        Self.logger.info("Declined suggestion \(suggestion.id)")
    }

    func approveAllSuggestions() async {
        let current = suggestions
        for suggestion in current {
            await approveSuggestion(suggestion)
        }
    }

    // MARK: - Rule Matching

    private static func ruleMatches(_ rule: TrackingRule, block: AppUsageBlock) -> Bool {
        var hasAnyCriterion = false

        // Check appBundleId (exact, case-insensitive)
        if let bundleId = rule.appBundleId, !bundleId.isEmpty {
            hasAnyCriterion = true
            if bundleId.caseInsensitiveCompare(block.appBundleId) != .orderedSame {
                return false
            }
        }

        // Check appNamePattern (contains, case-insensitive)
        if let pattern = rule.appNamePattern, !pattern.isEmpty {
            hasAnyCriterion = true
            if !block.appName.localizedCaseInsensitiveContains(pattern) {
                return false
            }
        }

        // Rule must have at least one non-nil/non-empty match criterion
        return hasAnyCriterion
    }

    // MARK: - Dedup

    private static func isDuplicate(rule: TrackingRule, startTime: String, existingEntries: [ShadowEntry]) -> Bool {
        existingEntries.contains { entry in
            entry.projectId == rule.projectId
                && entry.taskId == rule.taskId
                && entry.startTime == startTime
        }
    }

    // MARK: - Entry Factory

    private static func makeShadowEntry(
        from rule: TrackingRule,
        dateString: String,
        startTime: String,
        durationSeconds: Int,
        existingEntries: [ShadowEntry]
    ) -> ShadowEntry {
        let now = ISO8601DateFormatter().string(from: Date())
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
            createdAt: now,
            updatedAt: now,
            syncStatus: .pendingCreate,
            localUpdatedAt: now,
            serverUpdatedAt: now,
            conflictFlag: false
        )
    }

    // MARK: - Declined Persistence

    private func loadDeclinedIds(for dateString: String) {
        guard loadedDeclinedDate != dateString else { return }
        let key = "declinedSuggestions_\(dateString)"
        let stored = UserDefaults.standard.stringArray(forKey: key) ?? []
        declinedSuggestionIds = Set(stored)
        loadedDeclinedDate = dateString
    }

    private func persistDeclinedIds() {
        guard let dateString = loadedDeclinedDate else { return }
        let key = "declinedSuggestions_\(dateString)"
        UserDefaults.standard.set(Array(declinedSuggestionIds), forKey: key)
    }

    // MARK: - Helpers

    private static func timeString(from date: Date) -> String {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", components.hour ?? 0, components.minute ?? 0)
    }

    nonisolated(unsafe) private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static func dateString(from date: Date) -> String {
        dateFormatter.string(from: date)
    }
}
