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

    /// Entries waiting to be synced.
    private(set) var entries: [QueuedEntry] = []

    init() {
        entries = Self.loadFromDisk()
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
            createdAt: Date()
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

    private static var queueURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("MocoCompanion", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("entry-queue.json")
    }

    private func saveToDisk() {
        do {
            let data = try JSONEncoder().encode(entries)
            try data.write(to: Self.queueURL, options: .atomic)
        } catch {
            Self.logger.error("Failed to save entry queue: \(error.localizedDescription)")
        }
    }

    private static func loadFromDisk() -> [QueuedEntry] {
        guard FileManager.default.fileExists(atPath: queueURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: queueURL)
            return try JSONDecoder().decode([QueuedEntry].self, from: data)
        } catch {
            logger.error("Failed to load entry queue: \(error.localizedDescription)")
            return []
        }
    }
}
