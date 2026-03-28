import Foundation

/// Pure dedup logic extracted from MonitorEngine.
/// Tracks which alert keys have fired and enforces dedup strategies.
/// Testable without timers, notifications, or polling.
struct DedupLedger {
    private var entries: [String: Date] = [:]

    /// Check whether an alert should fire based on its dedup strategy.
    func shouldFire(_ alert: MonitorAlert, now: Date = Date()) -> Bool {
        switch alert.dedupStrategy {
        case .once:
            return entries[alert.dedupKey] == nil
        case .rateLimited(let interval):
            guard let last = entries[alert.dedupKey] else { return true }
            return now.timeIntervalSince(last) >= interval
        case .perDay:
            guard let last = entries[alert.dedupKey] else { return true }
            return !Calendar.current.isDate(last, inSameDayAs: now)
        }
    }

    /// Record that an alert fired.
    mutating func markFired(_ alert: MonitorAlert, at date: Date = Date()) {
        entries[alert.dedupKey] = date
    }

    /// Clear all entries with the given prefix.
    mutating func clearPrefix(_ prefix: String) {
        entries = entries.filter { !$0.key.hasPrefix(prefix) }
    }

    /// Clear all entries.
    mutating func clearAll() {
        entries.removeAll()
    }
}
