import Foundation

/// Pure sync/parse logic behind `TimeRangeEditor`. Start and end are minutes
/// since midnight; the range never crosses midnight (end <= 1440).
struct TimeRangeModel: Equatable {
    static let minutesPerDay = 1440
    static let minDuration = 1

    private(set) var start: Int
    private(set) var duration: Int

    init(start: Int, duration: Int) {
        let s = min(max(start, 0), Self.minutesPerDay - 1)
        self.start = s
        self.duration = min(max(duration, Self.minDuration), Self.minutesPerDay - s)
    }

    var end: Int { start + duration }

    /// Moving the start keeps the duration, so the end follows. If that would
    /// pass midnight, the duration shrinks to fit.
    mutating func setStart(_ minutes: Int) {
        self = TimeRangeModel(start: minutes, duration: duration)
    }

    /// Setting the end recomputes the duration. An end at or before the start
    /// collapses to the minimum duration.
    mutating func setEnd(_ minutes: Int) {
        let e = min(minutes, Self.minutesPerDay)
        duration = min(max(e - start, Self.minDuration), Self.minutesPerDay - start)
    }

    /// Setting the duration moves the end, clamped to the end of the day.
    mutating func setDuration(_ minutes: Int) {
        duration = min(max(minutes, Self.minDuration), Self.minutesPerDay - start)
    }

    // MARK: - Parsing / formatting

    /// Parses "H:mm" or "HH:mm" into minutes since midnight. Allows "24:00"
    /// (end of day). Returns nil for anything else.
    static func parseTime(_ text: String) -> Int? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2,
              (1...2).contains(parts[0].count), parts[1].count == 2,
              parts.allSatisfy({ $0.allSatisfy { $0.isASCII && $0.isNumber } }),
              let h = Int(parts[0]), let m = Int(parts[1]),
              m < 60 else { return nil }
        let total = h * 60 + m
        return total <= minutesPerDay ? total : nil
    }

    /// Parses a positive whole number of minutes. Returns nil otherwise.
    static func parseDuration(_ text: String) -> Int? {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, t.allSatisfy({ $0.isASCII && $0.isNumber }),
              let v = Int(t), v > 0 else { return nil }
        return v
    }

    /// "HH:mm"; 1440 renders as "24:00".
    static func format(_ minutes: Int) -> String {
        let m = min(max(minutes, 0), minutesPerDay)
        return String(format: "%02d:%02d", m / 60, m % 60)
    }
}
