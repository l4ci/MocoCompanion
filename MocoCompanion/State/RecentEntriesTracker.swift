import Foundation
import os

/// Tracks the last N submitted time entries for quick re-selection.
/// Stored as JSON in UserDefaults. Deduplicates by projectId+taskId (keeps latest).
@Observable
@MainActor
final class RecentEntriesTracker {
    private static let logger = Logger(category: "Recents")
    static let maxEntries = 5

    private let state: PersistedState<[RecentEntry]>

    /// Most-recent-first list of recent entries.
    var entries: [RecentEntry] { state.value }

    init(backend: StorageBackend = DefaultsBackend()) {
        self.state = PersistedState(key: "recentEntries", default: [], backend: backend)
    }

    // MARK: - Model

    struct RecentEntry: ProjectTaskRef, Codable {
        let projectId: Int
        let taskId: Int
        let customerName: String
        let projectName: String
        let taskName: String
        let description: String
        let date: Date
    }

    // MARK: - Public API

    /// Record a submitted entry. Deduplicates by projectId+taskId, keeps most recent.
    func record(projectId: Int, taskId: Int, customerName: String, projectName: String, taskName: String, description: String) {
        state.update { entries in
            // Remove existing entry for same project+task
            entries.removeAll { $0.projectId == projectId && $0.taskId == taskId }

            let entry = RecentEntry(
                projectId: projectId,
                taskId: taskId,
                customerName: customerName,
                projectName: projectName,
                taskName: taskName,
                description: description,
                date: Date.now
            )

            // Insert at front (most recent first)
            entries.insert(entry, at: 0)

            // Cap at max
            if entries.count > RecentEntriesTracker.maxEntries {
                entries = Array(entries.prefix(RecentEntriesTracker.maxEntries))
            }
        }
        Self.logger.info("Recorded recent entry: \(projectName) > \(taskName)")
    }

    /// Return recent entries that still exist in current search entries.
    func activeEntries(validEntries: [SearchEntry]) -> [RecentEntry] {
        let validIds = Set(validEntries.map(\.id))
        return entries.filter { validIds.contains($0.id) }
    }
}
