import Foundation

// MARK: - Time Slot

/// A fixed 30-minute window showing the dominant app and significant
/// contributing apps. Produced by aggregating raw `AppRecord` rows into
/// half-hour buckets for a cleaner, less noisy timeline display.
///
/// Only slots where the dominant app accumulated at least
/// `minDisplayDurationSeconds` are emitted — brief, scattered usage is
/// filtered as noise.
struct TimeSlot: Identifiable, Sendable {
    let id: String
    /// Minutes since midnight; always a multiple of `slotDurationMinutes`.
    let startMinutes: Int
    let dominantBundleId: String
    let dominantAppName: String
    let dominantDurationSeconds: TimeInterval
    /// The window title that accumulated the most seconds for the dominant
    /// app within this slot. Nil when window-title tracking was off or no
    /// title was captured.
    let dominantWindowTitle: String?
    /// Non-dominant apps with at least `minDisplayDurationSeconds` of use
    /// within this slot, sorted by duration descending.
    let contributingApps: [ContributingApp]
    /// Sum of all app durations within the slot (dominant + contributions + sub-threshold).
    let totalActiveSeconds: TimeInterval

    // MARK: - View-ready labels

    var endMinutes: Int { startMinutes + Self.slotDurationMinutes }
    var startTimeLabel: String { TimelineGeometry.timeString(fromMinutes: startMinutes) }
    var endTimeLabel: String { TimelineGeometry.timeString(fromMinutes: endMinutes) }
    var dominantDurationLabel: String { TimelineGeometry.durationLabel(seconds: dominantDurationSeconds) }

    // MARK: - Constants

    /// Width of each time slot in minutes.
    static let slotDurationMinutes: Int = 30

    /// An app must accumulate at least this many seconds within a slot to
    /// be considered significant. Applies to both the dominant app (slot is
    /// omitted if below) and contributing apps (hidden if below).
    static let minDisplayDurationSeconds: TimeInterval = 300 // 5 minutes

    // MARK: - Aggregation

    /// Aggregates raw `AppRecord`s into fixed 30-minute time slots.
    ///
    /// Records that span a slot boundary are split proportionally.
    /// Only slots where the dominant app reaches `minDisplayDurationSeconds`
    /// are included. Pure function — safe from any isolation domain.
    static func aggregate(_ records: [AppRecord]) -> [TimeSlot] {
        guard !records.isEmpty else { return [] }

        // Per-slot accumulator: bundleId → (appName, totalSeconds, titleSeconds)
        typealias TitleBucket = [String: TimeInterval]   // windowTitle → seconds
        typealias AppBucket = (appName: String, total: TimeInterval, titles: TitleBucket)
        var slots: [Int: [String: AppBucket]] = [:]      // slotIndex → bundleId → AppBucket

        let slotSeconds = TimeInterval(slotDurationMinutes * 60)

        for record in records {
            let cal = Calendar.current
            let comps = cal.dateComponents([.hour, .minute, .second], from: record.timestamp)
            let recordStartSeconds = TimeInterval((comps.hour ?? 0) * 3600 + (comps.minute ?? 0) * 60 + (comps.second ?? 0))
            let recordEndSeconds = recordStartSeconds + record.durationSeconds

            // Walk each slot this record overlaps.
            let firstSlot = Int(recordStartSeconds / slotSeconds)
            let lastSlot = Int(max(recordEndSeconds - 1, recordStartSeconds) / slotSeconds)

            for slotIdx in firstSlot...lastSlot {
                let slotStartSec = TimeInterval(slotIdx) * slotSeconds
                let slotEndSec = slotStartSec + slotSeconds
                let overlapStart = max(recordStartSeconds, slotStartSec)
                let overlapEnd = min(recordEndSeconds, slotEndSec)
                let contribution = max(overlapEnd - overlapStart, 0)
                guard contribution > 0 else { continue }

                var slotApps = slots[slotIdx, default: [:]]
                var bucket = slotApps[record.appBundleId] ?? (appName: record.appName, total: 0, titles: [:])
                bucket.total += contribution

                if let title = record.windowTitle, !title.isEmpty {
                    bucket.titles[title, default: 0] += contribution
                }

                slotApps[record.appBundleId] = bucket
                slots[slotIdx] = slotApps
            }
        }

        // Build TimeSlots from accumulated data.
        var result: [TimeSlot] = []

        for (slotIdx, apps) in slots {
            // Find the dominant app (most cumulative seconds).
            guard let (dominantId, dominantBucket) = apps.max(by: { $0.value.total < $1.value.total }) else { continue }

            // Skip slot if dominant app is below threshold.
            guard dominantBucket.total >= minDisplayDurationSeconds else { continue }

            // Dominant window title: the title with the most seconds.
            let dominantTitle: String? = dominantBucket.titles
                .max(by: { $0.value < $1.value })?
                .key

            // Contributing apps: non-dominant, >= threshold, sorted desc.
            let contributing = apps
                .filter { $0.key != dominantId && $0.value.total >= minDisplayDurationSeconds }
                .map { ContributingApp(bundleId: $0.key, appName: $0.value.appName, durationSeconds: $0.value.total) }
                .sorted { $0.durationSeconds > $1.durationSeconds }

            let totalActive = apps.values.reduce(0) { $0 + $1.total }
            let startMinutes = slotIdx * slotDurationMinutes

            result.append(TimeSlot(
                id: "slot-\(startMinutes)",
                startMinutes: startMinutes,
                dominantBundleId: dominantId,
                dominantAppName: dominantBucket.appName,
                dominantDurationSeconds: dominantBucket.total,
                dominantWindowTitle: dominantTitle,
                contributingApps: contributing,
                totalActiveSeconds: totalActive
            ))
        }

        return result.sorted { $0.startMinutes < $1.startMinutes }
    }
}
