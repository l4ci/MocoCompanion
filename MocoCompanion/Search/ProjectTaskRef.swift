import Foundation

/// Shared protocol for types that represent a project+task reference.
/// Eliminates field duplication across SearchEntry, FavoriteEntry, and RecentEntry.
protocol ProjectTaskRef: Identifiable {
    var projectId: Int { get }
    var taskId: Int { get }
    var customerName: String { get }
    var projectName: String { get }
    var taskName: String { get }
}

extension ProjectTaskRef {
    /// Unique identifier combining project and task IDs.
    var id: String { "\(projectId)-\(taskId)" }

    /// Display string: "Customer > Project > Task"
    var displayText: String {
        "\(customerName) > \(projectName) > \(taskName)"
    }
}
