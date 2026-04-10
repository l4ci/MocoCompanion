import Foundation

// MARK: - Sync Status

enum SyncStatus: String, Sendable, Equatable {
    case synced = "synced"
    case dirty = "dirty"
    case pendingCreate = "pending_create"
    case pendingDelete = "pending_delete"
}

// MARK: - Shadow Entry

struct ShadowEntry: Sendable, Equatable {
    var id: Int?
    var localId: String?
    var date: String
    var hours: Double
    var seconds: Int
    var workedSeconds: Int
    var description: String
    var billed: Bool
    var billable: Bool
    var tag: String
    var projectId: Int
    var projectName: String
    var projectBillable: Bool
    var taskId: Int
    var taskName: String
    var taskBillable: Bool
    var customerId: Int
    var customerName: String
    var userId: Int
    var userFirstname: String
    var userLastname: String
    var hourlyRate: Double
    var timerStartedAt: String?
    var startTime: String?
    var locked: Bool
    var createdAt: String
    var updatedAt: String
    var syncStatus: SyncStatus
    var localUpdatedAt: String
    var serverUpdatedAt: String
    var conflictFlag: Bool

    // MARK: - Origin Tracking
    //
    // Local-only metadata that records where the entry came from when it
    // was created inside MocoCompanion. Moco has no API field for this,
    // so these columns are purged on pull from server and re-applied on
    // local insert. Used by the timeline view to decide whether an entry
    // is "linked" to a recorded activity block.

    /// Bundle identifier of the app whose recorded activity this entry
    /// was created from (right-click "Create entry from this block",
    /// drag-create from a block, or a matching TrackingRule). Nil for
    /// manually-typed entries.
    var sourceAppBundleId: String?

    /// Id of the TrackingRule that created this entry, if any.
    var sourceRuleId: Int64?

    /// Whether the timer is currently running on this entry.
    var isTimerRunning: Bool { timerStartedAt != nil }

    /// Whether the entry is read-only (locked by Moco or already billed/invoiced).
    var isReadOnly: Bool { locked || billed }

    // MARK: - Conversion from MocoActivity

    static func from(_ activity: MocoActivity) -> ShadowEntry {
        ShadowEntry(
            id: activity.id,
            localId: nil,
            date: activity.date,
            hours: activity.hours,
            seconds: activity.seconds,
            workedSeconds: activity.workedSeconds,
            description: activity.description,
            billed: activity.billed,
            billable: activity.billable,
            tag: activity.tag,
            projectId: activity.project.id,
            projectName: activity.project.name,
            projectBillable: activity.project.billable,
            taskId: activity.task.id,
            taskName: activity.task.name,
            taskBillable: activity.task.billable,
            customerId: activity.customer.id,
            customerName: activity.customer.name,
            userId: activity.user.id,
            userFirstname: activity.user.firstname,
            userLastname: activity.user.lastname,
            hourlyRate: activity.hourlyRate,
            timerStartedAt: activity.timerStartedAt,
            startTime: Self.extractTime(from: activity.timerStartedAt),
            locked: activity.locked,
            createdAt: activity.createdAt,
            updatedAt: activity.updatedAt,
            syncStatus: .synced,
            localUpdatedAt: activity.updatedAt,
            serverUpdatedAt: activity.updatedAt,
            conflictFlag: false,
            sourceAppBundleId: nil,
            sourceRuleId: nil
        )
    }

    /// Extract "HH:mm" time portion from an ISO8601 datetime string.
    private static func extractTime(from iso8601: String?) -> String? {
        guard let iso = iso8601 else { return nil }
        // ISO8601 format: "2025-06-01T14:30:00Z" or "2025-06-01T14:30:00+02:00"
        // We need the "HH:mm" portion after 'T'
        guard let tIndex = iso.firstIndex(of: "T") else { return nil }
        let timeStart = iso.index(after: tIndex)
        guard iso.distance(from: timeStart, to: iso.endIndex) >= 5 else { return nil }
        let timeEnd = iso.index(timeStart, offsetBy: 5)
        return String(iso[timeStart..<timeEnd])
    }

}
