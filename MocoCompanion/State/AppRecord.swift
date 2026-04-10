import Foundation

// MARK: - Timeline Geometry

/// Pure time-and-grid math for the autotracker timeline. Lives outside
/// `TimelineViewModel` so views (and value types like `AppUsageBlock`)
/// don't depend on a `@MainActor` type just to format a time string or
/// snap a pixel coordinate. All methods are `nonisolated` and safe to
/// call from any isolation domain.
enum TimelineGeometry {

    /// Snap a fractional minute value to the nearest grid boundary, clamped to 0...1439.
    static func snapToGrid(minutes: Double, gridMinutes: Int = 5) -> Int {
        let snapped = Int(round(minutes / Double(gridMinutes))) * gridMinutes
        return min(max(snapped, 0), 1439)
    }

    /// Convert an "HH:mm" time string to minutes since midnight.
    static func minutesSinceMidnight(from timeString: String) -> Int? {
        guard timeString.count >= 5 else { return nil }
        let parts = timeString.prefix(5).split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
        return h * 60 + m
    }

    /// Convert minutes since midnight to "HH:mm" format.
    static func timeString(fromMinutes minutes: Int) -> String {
        let clamped = min(max(minutes, 0), 1439)
        return String(format: "%02d:%02d", clamped / 60, clamped % 60)
    }

    /// "HH:mm" for the hour/minute components of a `Date` in the current calendar.
    static func timeString(from date: Date) -> String {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", components.hour ?? 0, components.minute ?? 0)
    }

    /// Format a duration in seconds as a short label ("45m" or "1h 15m").
    static func durationLabel(seconds: TimeInterval) -> String {
        let totalMinutes = Int(seconds) / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    /// "yyyy-MM-dd" in POSIX locale. Used as the canonical date key across the
    /// shadow entry store and the rule engine.
    static func dateString(from date: Date) -> String {
        dateFormatter.string(from: date)
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}

/// A single record of which application was frontmost during a time window.
struct AppRecord: Sendable, Identifiable, Equatable {
    let id: Int64?
    let timestamp: Date
    let appBundleId: String
    let appName: String
    let windowTitle: String?
    let durationSeconds: TimeInterval
}

// MARK: - App Usage Block

/// A merged block of consecutive app usage within a 5-minute gap threshold.
///
/// Produced by folding adjacent `AppRecord` rows for the same bundle into one
/// visible block. Used by the autotracker rule engine for matching and by the
/// timeline view for the app-usage column.
struct AppUsageBlock: Identifiable, Sendable {
    let id: String
    let appBundleId: String
    let appName: String
    let startTime: Date
    let endTime: Date
    let durationSeconds: TimeInterval
    let recordCount: Int

    /// "HH:mm" start-of-block label, pre-formatted so views don't need to reach
    /// for a `DateFormatter`.
    var startTimeLabel: String { TimelineGeometry.timeString(from: startTime) }

    /// "HH:mm" end-of-block label.
    var endTimeLabel: String { TimelineGeometry.timeString(from: endTime) }

    /// Short duration label ("45m" / "1h 15m").
    var durationLabel: String { TimelineGeometry.durationLabel(seconds: durationSeconds) }

    /// Gap threshold (seconds) for merging adjacent same-app records into a single block.
    static let mergeGapSeconds: TimeInterval = 300 // 5 minutes

    /// Merges adjacent `AppRecord`s with the same bundleId within `mergeGapSeconds`
    /// into consolidated `AppUsageBlock` instances. Pure function — safe to call
    /// from any isolation domain.
    static func merge(_ records: [AppRecord]) -> [AppUsageBlock] {
        guard !records.isEmpty else { return [] }

        let sorted = records.sorted { $0.timestamp < $1.timestamp }
        var blocks: [AppUsageBlock] = []

        var currentBundleId = sorted[0].appBundleId
        var currentAppName = sorted[0].appName
        var blockStart = sorted[0].timestamp
        var blockEnd = sorted[0].timestamp.addingTimeInterval(sorted[0].durationSeconds)
        var blockDuration = sorted[0].durationSeconds
        var recordCount = 1

        for i in 1..<sorted.count {
            let record = sorted[i]
            let gap = record.timestamp.timeIntervalSince(blockEnd)

            if record.appBundleId == currentBundleId && gap <= mergeGapSeconds {
                // Merge into current block
                let recordEnd = record.timestamp.addingTimeInterval(record.durationSeconds)
                blockEnd = max(blockEnd, recordEnd)
                blockDuration += record.durationSeconds
                recordCount += 1
            } else {
                // Flush current block
                blocks.append(AppUsageBlock(
                    id: "\(currentBundleId)-\(blockStart.timeIntervalSince1970)",
                    appBundleId: currentBundleId,
                    appName: currentAppName,
                    startTime: blockStart,
                    endTime: blockEnd,
                    durationSeconds: blockDuration,
                    recordCount: recordCount
                ))

                // Start new block
                currentBundleId = record.appBundleId
                currentAppName = record.appName
                blockStart = record.timestamp
                blockEnd = record.timestamp.addingTimeInterval(record.durationSeconds)
                blockDuration = record.durationSeconds
                recordCount = 1
            }
        }

        // Flush last block
        blocks.append(AppUsageBlock(
            id: "\(currentBundleId)-\(blockStart.timeIntervalSince1970)",
            appBundleId: currentBundleId,
            appName: currentAppName,
            startTime: blockStart,
            endTime: blockEnd,
            durationSeconds: blockDuration,
            recordCount: recordCount
        ))

        return blocks
    }
}
