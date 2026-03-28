import Foundation
import os

/// Tracks the last N submitted time entries for quick re-selection.
/// Stored as JSON in UserDefaults. Deduplicates by projectId+taskId (keeps latest).
@Observable
@MainActor
final class RecentEntriesTracker {
    private static let logger = Logger(category: "Recents")
    private static let storageKey = "recentEntries"
    static let maxEntries = 5

    /// Most-recent-first list of recent entries.
    private(set) var entries: [RecentEntry] = []

    init() {
        entries = Self.load()
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
        // Remove existing entry for same project+task
        entries.removeAll { $0.projectId == projectId && $0.taskId == taskId }

        let entry = RecentEntry(
            projectId: projectId,
            taskId: taskId,
            customerName: customerName,
            projectName: projectName,
            taskName: taskName,
            description: description,
            date: Date()
        )

        // Insert at front (most recent first)
        entries.insert(entry, at: 0)

        // Cap at max
        if entries.count > Self.maxEntries {
            entries = Array(entries.prefix(Self.maxEntries))
        }

        save()
        Self.logger.info("Recorded recent entry: \(entry.projectName) > \(entry.taskName)")
    }

    /// Return recent entries that still exist in current search entries.
    func activeEntries(validEntries: [SearchEntry]) -> [RecentEntry] {
        let validIds = Set(validEntries.map(\.id))
        return entries.filter { validIds.contains($0.id) }
    }

    // MARK: - Persistence

    private func save() {
        JSONStore.save(entries, key: Self.storageKey)
    }

    private static func load() -> [RecentEntry] {
        JSONStore.load([RecentEntry].self, key: storageKey, fallback: [])
    }
}
