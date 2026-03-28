import Foundation

/// Fuzzy matcher that scores SearchEntry items against a query string.
///
/// Supports two matching strategies:
/// 1. **Substring match**: query characters appear in order within the search text
/// 2. **Acronym match**: query matches first letters of words (e.g., "CPM" → "Carrot > Project Management")
///
/// Results are sorted by score (higher = better match).
enum FuzzyMatcher {

    /// Match result with scoring information.
    struct Match: Sendable {
        let entry: SearchEntry
        let score: Double
        /// Character indices in displayText that matched (for highlighting).
        let matchedIndices: [Int]
    }

    /// Search entries with a fuzzy query. Returns matches sorted by score (best first).
    ///
    /// - Parameters:
    ///   - query: The user's search text. Empty/whitespace-only returns empty results.
    ///   - entries: All available search entries.
    ///   - recencyScores: Optional projectId → recency score (0–1) to boost recently-used projects.
    ///   - limit: Maximum number of results to return. Defaults to 10.
    /// - Returns: Sorted matches with scores and match indices.
    static func search(query: String, in entries: [SearchEntry], recencyScores: [Int: Double] = [:], limit: Int = 10) -> [Match] {
        let trimmed = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else { return [] }

        var matches: [Match] = []

        for entry in entries {
            if let match = score(query: trimmed, entry: entry, recencyScores: recencyScores) {
                matches.append(match)
            }
        }

        // Sort by score descending, then alphabetically for ties
        matches.sort { lhs, rhs in
            if lhs.score != rhs.score {
                return lhs.score > rhs.score
            }
            return lhs.entry.displayText < rhs.entry.displayText
        }

        return Array(matches.prefix(limit))
    }

    // MARK: - Private

    /// Score a single entry against the query. Returns nil if no match.
    private static func score(query: String, entry: SearchEntry, recencyScores: [Int: Double]) -> Match? {
        let text = entry.displayText
        let lowerText = entry.searchText

        // Recency boost for the project (0–1.0 scaled to 0–0.5)
        let recencyBoost = (recencyScores[entry.projectId] ?? 0) * 0.5

        // Check for exact contiguous substring match — highest priority
        let isExactSubstring = lowerText.contains(query)

        // Try substring match first (characters in order)
        if let substringResult = substringMatch(query: query, text: text, lowerText: lowerText) {
            let exactBonus = isExactSubstring ? 3.0 : 0.0
            let totalScore = substringResult.score + exactBonus + recencyBoost
            return Match(entry: entry, score: totalScore, matchedIndices: substringResult.indices)
        }

        // Try acronym match (first letters of words)
        if let acronymResult = acronymMatch(query: query, text: text) {
            let totalScore = acronymResult.score + recencyBoost
            return Match(entry: entry, score: totalScore, matchedIndices: acronymResult.indices)
        }

        return nil
    }

    private struct MatchResult {
        let score: Double
        let indices: [Int]
    }

    /// Substring match: all query characters appear in order in the text.
    private static func substringMatch(query: String, text: String, lowerText: String) -> MatchResult? {
        let textChars = Array(lowerText)
        let queryChars = Array(query)

        var matchedIndices: [Int] = []
        var textIndex = 0

        for queryChar in queryChars {
            var found = false
            while textIndex < textChars.count {
                if textChars[textIndex] == queryChar {
                    matchedIndices.append(textIndex)
                    textIndex += 1
                    found = true
                    break
                }
                textIndex += 1
            }
            if !found { return nil }
        }

        // Score based on:
        // 1. Ratio of matched chars to total (longer matches in short text = better)
        // 2. Consecutiveness bonus (adjacent matches score higher)
        // 3. Position bonus (earlier matches score higher)
        let coverage = Double(queryChars.count) / Double(textChars.count)

        var consecutiveBonus = 0.0
        for i in 1..<matchedIndices.count {
            if matchedIndices[i] == matchedIndices[i - 1] + 1 {
                consecutiveBonus += 0.1
            }
        }

        // Bonus for matching at start of words (after ' ', '>', '-', '_')
        var wordStartBonus = 0.0
        for idx in matchedIndices {
            if idx == 0 || " >-_".contains(textChars[max(0, idx - 1)]) {
                wordStartBonus += 0.05
            }
        }

        // Penalty for late start
        let startPenalty = Double(matchedIndices.first ?? 0) * 0.01

        let score = coverage * 2.0 + consecutiveBonus + wordStartBonus - startPenalty
        return MatchResult(score: score, indices: matchedIndices)
    }

    /// Acronym match: query matches first letters of words.
    /// E.g., "cpm" matches "Carrot > Project Management"
    private static func acronymMatch(query: String, text: String) -> MatchResult? {
        let queryChars = Array(query.lowercased())

        // Extract word-start positions and their characters
        var wordStarts: [(index: Int, char: Character)] = []
        let textChars = Array(text.lowercased())

        // First character is always a word start
        if let first = textChars.first {
            wordStarts.append((0, first))
        }

        for i in 1..<textChars.count {
            let prev = textChars[i - 1]
            if " >-_".contains(prev) && !(" >-_".contains(textChars[i])) {
                wordStarts.append((i, textChars[i]))
            }
        }

        // Try to match query chars to word starts in order
        var matchedIndices: [Int] = []
        var wsIndex = 0

        for queryChar in queryChars {
            var found = false
            while wsIndex < wordStarts.count {
                if wordStarts[wsIndex].char == queryChar {
                    matchedIndices.append(wordStarts[wsIndex].index)
                    wsIndex += 1
                    found = true
                    break
                }
                wsIndex += 1
            }
            if !found { return nil }
        }

        // Acronym matches score slightly lower than good substring matches
        // but higher than poor substring matches
        let coverage = Double(queryChars.count) / Double(wordStarts.count)
        let score = coverage * 1.5 + 0.3  // Base acronym bonus
        return MatchResult(score: score, indices: matchedIndices)
    }
}
