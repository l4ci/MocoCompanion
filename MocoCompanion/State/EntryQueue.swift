import Foundation
import os

/// Queues time entries created while offline for later sync.
/// Persisted to disk so entries survive app restarts.
@Observable
@MainActor
final class EntryQueue {
    private static let logger = Logger(category: "EntryQueue")

    /// A queued entry waiting to be synced.
    struct QueuedEntry: Codable, Identifiable {
        let id: UUID
        let date: String
        let projectId: Int
        let taskId: Int
        let projectName: String
        let taskName: String
        let description: String
        let seconds: Int
        let tag: String?
        let createdAt: Date
    }

    private let store: PersistedValue<[QueuedEntry]>

    /// Entries waiting to be synced.
    private(set) var entries: [QueuedEntry] = []

    init(backend: StorageBackend? = nil) {
        let resolvedBackend = backend ?? FileBackend(directory: Self.appSupportDir)
        self.store = PersistedValue(key: "entry-queue", default: [], backend: resolvedBackend)
        entries = store.load()
    }

    private static var appSupportDir: URL {
        URL.applicationSupportDirectory
            .appendingPathComponent("MocoCompanion", isDirectory: true)
    }

    /// Queue an entry for later sync.
    func enqueue(date: String, projectId: Int, taskId: Int, projectName: String, taskName: String, description: String, seconds: Int, tag: String?) {
        let entry = QueuedEntry(
            id: UUID(),
            date: date,
            projectId: projectId,
            taskId: taskId,
            projectName: projectName,
            taskName: taskName,
            description: description,
            seconds: seconds,
            tag: tag,
            createdAt: Date.now
        )
        entries.append(entry)
        saveToDisk()
        Self.logger.info("Queued entry for \(projectName) > \(taskName)")
    }

    /// Remove a synced entry from the queue.
    func remove(id: UUID) {
        entries.removeAll { $0.id == id }
        saveToDisk()
    }

    /// Remove all entries (after successful full sync).
    func clear() {
        entries.removeAll()
        saveToDisk()
    }

    var isEmpty: Bool { entries.isEmpty }
    var count: Int { entries.count }

    // MARK: - Persistence

    private func saveToDisk() {
        store.save(entries)
    }
}
