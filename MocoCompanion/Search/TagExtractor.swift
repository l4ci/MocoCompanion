import Foundation

/// Extracts a ticket tag from a description string.
///
/// Looks for the first `#WORD` pattern and returns the word without the `#`.
/// Example: "Fix login #PRJ-456 edge case" → "PRJ-456"
enum TagExtractor {
    /// Extract the first hashtag from a description string.
    /// Returns nil if no hashtag is found.
    static func extract(from text: String) -> String? {
        // Match # followed by one or more word chars (letters, digits, hyphens, underscores)
        guard let range = text.range(of: #"#([A-Za-z0-9][\w-]*)"#, options: .regularExpression) else {
            return nil
        }
        let match = text[range]
        // Drop the leading #
        return String(match.dropFirst())
    }

    /// Strip all #TAG patterns from a description, leaving only the free text.
    /// Used to avoid duplicate tag info in the API payload (tag is sent separately).
    static func stripTags(from text: String) -> String {
        text.replacingOccurrences(of: #"#[A-Za-z0-9][\w-]*"#, with: "", options: .regularExpression)
            .replacing("  ", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }
}
