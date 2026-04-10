import Foundation

extension Array where Element == ShadowEntry {
    /// Total tracked hours across all entries.
    var totalHours: Double { reduce(0) { $0 + $1.hours } }

    /// Billable percentage (0–100) across all entries.
    var billablePercentage: Double {
        let total = totalHours
        guard total > 0 else { return 0 }
        let billable = filter(\.billable).reduce(0.0) { $0 + $1.hours }
        return (billable / total) * 100.0
    }
}
