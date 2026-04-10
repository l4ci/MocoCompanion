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
            conflictFlag: false
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

    // MARK: - Conversion to MocoActivity

    func toMocoActivity() -> MocoActivity {
        let json: [String: Any] = [
            "id": id ?? 0,
            "date": date,
            "hours": hours,
            "seconds": seconds,
            "worked_seconds": workedSeconds,
            "description": description,
            "billed": billed,
            "billable": billable,
            "tag": tag,
            "project": [
                "id": projectId,
                "name": projectName,
                "billable": projectBillable,
            ] as [String: Any],
            "task": [
                "id": taskId,
                "name": taskName,
                "billable": taskBillable,
            ] as [String: Any],
            "customer": [
                "id": customerId,
                "name": customerName,
            ] as [String: Any],
            "user": [
                "id": userId,
                "firstname": userFirstname,
                "lastname": userLastname,
            ] as [String: Any],
            "hourly_rate": hourlyRate,
            "timer_started_at": timerStartedAt as Any,
            "locked": locked,
            "created_at": createdAt,
            "updated_at": updatedAt,
        ]
        let data = try! JSONSerialization.data(withJSONObject: json)
        return try! JSONDecoder().decode(MocoActivity.self, from: data)
    }
}
