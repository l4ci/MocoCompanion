import Foundation
import os

/// Tracks frequently used descriptions for inline autocomplete.
/// Stores description → usage count. Filters out ticket references (#TAG).
/// Persisted as JSON in UserDefaults.
@Observable
@MainActor
final class DescriptionStore {
    private static let logger = Logger(category: "DescriptionStore")
    static let maxEntries = 100

    private let state: PersistedState<[Entry]>

    /// Description text → usage count, sorted by count descending.
    var entries: [Entry] { state.value }

    struct Entry: Codable {
        let text: String
        var count: Int
    }

    init(backend: StorageBackend = DefaultsBackend()) {
        self.state = PersistedState(key: "descriptionHistory", default: [], backend: backend)
    }

    // MARK: - Public API

    /// Record a used description. Strips ticket tags before storing.
    /// Only records non-empty descriptions after tag removal.
    func record(_ description: String) {
        guard let updated = DescriptionMatcher.record(description, into: state.value, maxEntries: Self.maxEntries) else { return }
        state.set(updated)
    }

    /// Find the best matching completion for a partial input.
    /// Returns the full suggested text if a match is found.
    func suggest(for input: String) -> String? {
        DescriptionMatcher.suggest(for: input, entries: state.value)
    }

    /// Clear all stored descriptions.
    func clearAll() {
        state.set([])
        Self.logger.info("Description history cleared")
    }
}
