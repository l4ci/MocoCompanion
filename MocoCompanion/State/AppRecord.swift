import Foundation

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
