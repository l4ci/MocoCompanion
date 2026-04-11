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

/// A brief co-occurring app use within a larger block's timeframe.
/// Surfaced in `AppUsageBlock.contributingApps` for tooltip display.
struct ContributingApp: Sendable, Hashable {
    let bundleId: String
    let appName: String
    let durationSeconds: TimeInterval

    var durationLabel: String { TimelineGeometry.durationLabel(seconds: durationSeconds) }
}

/// A merged block of app usage dominated by one bundle, with short same-window
/// usage of other bundles absorbed as contributions.
///
/// Produced by folding raw `AppRecord` rows via `merge(_:)`. The algorithm is a
/// "sticky-dominant" merge: a run of records with the same dominant bundle is
/// extended when brief interruptions from other bundles appear (≤ the
/// interruption grace window), and those interruptions are tracked as
/// contributions. Blocks whose total duration falls below
/// `minDisplayDurationSeconds` are filtered out entirely — the timeline only
/// shows windows of meaningful focus.
struct AppUsageBlock: Identifiable, Sendable {
    let id: String
    let appBundleId: String
    let appName: String
    let startTime: Date
    let endTime: Date
    /// Total duration of the block window (dominant + contributions combined).
    let durationSeconds: TimeInterval
    let recordCount: Int
    /// Other apps briefly used within this block's time window, each with total
    /// duration ≥ `contributionMinDisplaySeconds`, sorted by duration descending.
    let contributingApps: [ContributingApp]
    /// The title of the focused window from the most recent contributing record
    /// that had a non-nil title. Nil when window-title tracking was off for the
    /// entire duration of the block.
    let windowTitle: String?

    init(
        id: String,
        appBundleId: String,
        appName: String,
        startTime: Date,
        endTime: Date,
        durationSeconds: TimeInterval,
        recordCount: Int,
        contributingApps: [ContributingApp],
        windowTitle: String? = nil
    ) {
        self.id = id
        self.appBundleId = appBundleId
        self.appName = appName
        self.startTime = startTime
        self.endTime = endTime
        self.durationSeconds = durationSeconds
        self.recordCount = recordCount
        self.contributingApps = contributingApps
        self.windowTitle = windowTitle
    }

    // MARK: - View-ready labels

    /// "HH:mm" start-of-block label, pre-formatted so views don't need to reach
    /// for a `DateFormatter`.
    var startTimeLabel: String { TimelineGeometry.timeString(from: startTime) }

    /// "HH:mm" end-of-block label.
    var endTimeLabel: String { TimelineGeometry.timeString(from: endTime) }

    /// Short duration label ("45m" / "1h 15m").
    var durationLabel: String { TimelineGeometry.durationLabel(seconds: durationSeconds) }

    // MARK: - Merge constants

    /// Minimum total block duration required for display. Blocks shorter than
    /// this are filtered out — a 30-second visit to an app is noise, not
    /// signal.
    static let minDisplayDurationSeconds: TimeInterval = 300 // 5 minutes

    /// A single non-dominant record at or below this duration is absorbed into
    /// the surrounding dominant block as a contribution rather than breaking
    /// the block in two.
    static let interruptionGraceSeconds: TimeInterval = 60 // 1 minute

    /// A contribution is surfaced in the block's tooltip only if its total
    /// duration (summed across all the block's time window) is at least this
    /// long.
    static let contributionMinDisplaySeconds: TimeInterval = 60 // 1 minute

    /// Any gap between two records longer than this forces a block boundary.
    /// Handles sleep/wake and long idle windows.
    static let sleepGapSeconds: TimeInterval = 300 // 5 minutes

    // MARK: - Merge algorithm

    /// Merges raw `AppRecord`s into displayable `AppUsageBlock`s using the
    /// sticky-dominant algorithm. Returns only blocks whose total duration
    /// meets `minDisplayDurationSeconds`. Pure function — safe to call from
    /// any isolation domain.
    static func merge(_ records: [AppRecord]) -> [AppUsageBlock] {
        guard !records.isEmpty else { return [] }

        let sorted = records.sorted { $0.timestamp < $1.timestamp }

        var result: [AppUsageBlock] = []

        // Working block state
        var workBundleId: String? = nil
        var workAppName: String = ""
        var workStart: Date = sorted[0].timestamp
        var workEnd: Date = sorted[0].timestamp
        var workDominantDuration: TimeInterval = 0
        var workContributions: [String: (appName: String, total: TimeInterval)] = [:]
        var workRecordCount: Int = 0
        // Most recent non-nil window title seen across all records in this block.
        var workWindowTitle: String? = nil

        func flush() {
            guard let bundleId = workBundleId else { return }
            let contributionTotal = workContributions.values.reduce(0) { $0 + $1.total }
            let totalDuration = workDominantDuration + contributionTotal
            if totalDuration >= minDisplayDurationSeconds {
                let contributing = workContributions
                    .filter { $0.value.total >= contributionMinDisplaySeconds }
                    .map { ContributingApp(bundleId: $0.key, appName: $0.value.appName, durationSeconds: $0.value.total) }
                    .sorted { $0.durationSeconds > $1.durationSeconds }
                result.append(AppUsageBlock(
                    id: "\(bundleId)-\(workStart.timeIntervalSince1970)",
                    appBundleId: bundleId,
                    appName: workAppName,
                    startTime: workStart,
                    endTime: workEnd,
                    durationSeconds: totalDuration,
                    recordCount: workRecordCount,
                    contributingApps: contributing,
                    windowTitle: workWindowTitle
                ))
            }
            workBundleId = nil
            workDominantDuration = 0
            workContributions = [:]
            workRecordCount = 0
            workWindowTitle = nil
        }

        func startWith(_ record: AppRecord) {
            workBundleId = record.appBundleId
            workAppName = record.appName
            workStart = record.timestamp
            workEnd = record.timestamp.addingTimeInterval(record.durationSeconds)
            workDominantDuration = record.durationSeconds
            workContributions = [:]
            workRecordCount = 1
            workWindowTitle = record.windowTitle
        }

        for record in sorted {
            let recordEnd = record.timestamp.addingTimeInterval(record.durationSeconds)

            // Sleep/wake gap: any gap beyond the threshold forces a flush so
            // we don't visually bridge hours of inactivity into one block.
            if workBundleId != nil {
                let gap = record.timestamp.timeIntervalSince(workEnd)
                if gap > sleepGapSeconds {
                    flush()
                }
            }

            if workBundleId == nil {
                startWith(record)
                continue
            }

            if record.appBundleId == workBundleId {
                // Same dominant — extend in place.
                workEnd = max(workEnd, recordEnd)
                workDominantDuration += record.durationSeconds
                workRecordCount += 1
                if let title = record.windowTitle { workWindowTitle = title }
            } else if record.durationSeconds <= interruptionGraceSeconds {
                // Brief use of another app — absorb as a contribution.
                workEnd = max(workEnd, recordEnd)
                let existing = workContributions[record.appBundleId]
                workContributions[record.appBundleId] = (
                    appName: record.appName,
                    total: (existing?.total ?? 0) + record.durationSeconds
                )
                workRecordCount += 1
                if let title = record.windowTitle { workWindowTitle = title }
            } else {
                // Long interruption — flush and start fresh with this record
                // as the new dominant.
                flush()
                startWith(record)
            }
        }
        flush()
        return result
    }
}
