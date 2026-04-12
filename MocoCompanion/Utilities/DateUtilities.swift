import Foundation

/// Shared date and time utilities used across the app.
enum DateUtilities {

    // MARK: - Cached Formatters

    /// ISO8601 formatter with fractional seconds.
    /// Note: DateFormatters are not Sendable but this is only accessed from @MainActor contexts
    /// via SwiftUI views and @MainActor-isolated state. nonisolated(unsafe) suppresses the
    /// concurrency warning; the formatters are immutable after initialization.
    nonisolated(unsafe) private static let iso8601Fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// ISO8601 formatter without fractional seconds (fallback).
    nonisolated(unsafe) private static let iso8601Standard: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// Date-only formatter: "yyyy-MM-dd" with POSIX locale.
    private static let dateOnly: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    // MARK: - Parsing

    /// Parse an ISO8601 timestamp, trying with and without fractional seconds.
    static func parseISO8601(_ string: String) -> Date? {
        iso8601Fractional.date(from: string) ?? iso8601Standard.date(from: string)
    }

    // MARK: - Date Formatting

    /// Today's date as "YYYY-MM-DD".
    static func todayString() -> String {
        dateString(.now)
    }

    /// Yesterday's date as "YYYY-MM-DD". Returns nil if calendar math fails.
    static func yesterdayString() -> String? {
        guard let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: .now) else { return nil }
        return dateString(yesterday)
    }

    /// Tomorrow's date as "YYYY-MM-DD". Returns nil if calendar math fails.
    static func tomorrowString() -> String? {
        guard let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: .now) else { return nil }
        return dateString(tomorrow)
    }

    /// Format a date as "YYYY-MM-DD".
    static func dateString(_ date: Date) -> String {
        dateOnly.string(from: date)
    }

    // MARK: - Duration Formatting

    /// Format elapsed seconds as H:MM:SS.
    static func formatElapsed(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    }

    /// Format elapsed seconds compactly for menubar display.
    /// Under 1 minute: "45s". Under 1 hour: "3m". 1 hour+: "1h3m".
    static func formatElapsedCompact(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return "\(hours)h\(minutes)m"
        } else if minutes > 0 {
            return "\(minutes)m"
        } else {
            return "\(seconds)s"
        }
    }

    /// Format elapsed seconds as HH:MM:SS (zero-padded hours).
    static func formatElapsedPadded(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    /// Format decimal hours as compact display: "2h05m", "45m", "0m".
    static func formatHoursCompact(_ hours: Double) -> String {
        let totalMinutes = Int(hours * 60)
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        if h > 0 { return "\(h)h\(String(format: "%02d", m))m" }
        if m == 0 { return "0m" }
        return "\(m)m"
    }

    // MARK: - Hours Parsing

    /// Parse a flexible hours string into total hours.
    /// Supports: "1.5", "1,5", "1h", "30m", "1h 30m", "1h30m", "90m", "1h 4m".
    /// Returns nil if the string can't be parsed.
    static func parseHours(_ input: String) -> Double? {
        let trimmed = input.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else { return nil }

        // Try "Xh Ym" or "XhYm" pattern first
        let hmPattern = #"^(\d+(?:[.,]\d+)?)\s*h\s*(?:(\d+)\s*m)?$"#
        if let match = trimmed.range(of: hmPattern, options: .regularExpression) {
            let matched = String(trimmed[match])
            // Extract hours part
            if let hRange = matched.range(of: #"\d+(?:[.,]\d+)?"#, options: .regularExpression) {
                let hStr = String(matched[hRange]).replacing(",", with: ".")
                guard let h = Double(hStr) else { return nil }

                // Extract optional minutes part
                if let mRange = matched.range(of: #"(\d+)\s*m"#, options: .regularExpression) {
                    let mStr = String(matched[mRange]).replacing("m", with: "").trimmingCharacters(in: .whitespaces)
                    let m = Double(mStr) ?? 0
                    return h + m / 60.0
                }
                return h
            }
        }

        // Try "Xm" pattern (minutes only)
        let mPattern = #"^(\d+)\s*m$"#
        if let match = trimmed.range(of: mPattern, options: .regularExpression) {
            let mStr = String(trimmed[match]).replacing("m", with: "").trimmingCharacters(in: .whitespaces)
            if let m = Double(mStr) { return m / 60.0 }
        }

        // Try plain number (with comma or dot decimal)
        let plain = trimmed
            .replacing("h", with: "")
            .replacing(",", with: ".")
            .trimmingCharacters(in: .whitespaces)
        if let value = Double(plain), value >= 0 { return value }

        return nil
    }
}
