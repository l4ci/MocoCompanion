import Foundation

/// Pure computation for description autocomplete and frequency tracking.
/// No persistence, no @Observable — just input→output.
/// Extracted from DescriptionStore for testability.
enum DescriptionMatcher {
    /// Find the best matching completion for a partial input from a list of entries.
    /// Returns the full suggested text if a prefix match is found (case-insensitive).
    static func suggest(for input: String, entries: [DescriptionStore.Entry]) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else { return nil }
        let lower = trimmed.lowercased()

        return entries
            .first { $0.text.lowercased().hasPrefix(lower) && $0.text.lowercased() != lower }
            .map(\.text)
    }

    /// Record a description into an entries list. Returns the updated, sorted, capped list.
    /// - Deduplicates by case-insensitive text match (increments count)
    /// - Sorts by usage count descending
    /// - Caps at maxEntries (drops least used)
    static func record(_ description: String, into entries: [DescriptionStore.Entry], maxEntries: Int = 100) -> [DescriptionStore.Entry]? {
        let cleaned = TagExtractor.stripTags(from: description).trimmingCharacters(in: .whitespaces)
        guard !cleaned.isEmpty, cleaned.count >= 3 else { return nil }

        var result = entries

        if let idx = result.firstIndex(where: { $0.text.lowercased() == cleaned.lowercased() }) {
            result[idx] = DescriptionStore.Entry(text: result[idx].text, count: result[idx].count + 1)
        } else {
            result.append(DescriptionStore.Entry(text: cleaned, count: 1))
        }

        result.sort { $0.count > $1.count }

        if result.count > maxEntries {
            result = Array(result.prefix(maxEntries))
        }

        return result
    }
}
