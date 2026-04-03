import Foundation
import os

/// Caches the last-known projects list to disk so search works offline.
/// Stored as JSON in Application Support. Loaded on launch, updated after each successful fetch.
enum ProjectCache {
    private static let logger = Logger(category: "ProjectCache")

    private static var cacheURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("MocoCompanion", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("projects-cache.json")
    }

    /// Save projects to disk. Called after each successful fetchProjects.
    static func save(_ projects: [MocoProject]) {
        do {
            let data = try JSONEncoder().encode(projects)
            try data.write(to: cacheURL, options: .atomic)
            logger.info("Cached \(projects.count) projects to disk")
        } catch {
            logger.error("Failed to cache projects: \(error.localizedDescription)")
        }
    }

    /// Load cached projects from disk. Returns empty array if no cache exists.
    static func load() -> [MocoProject] {
        guard FileManager.default.fileExists(atPath: cacheURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: cacheURL)
            let projects = try JSONDecoder().decode([MocoProject].self, from: data)
            logger.info("Loaded \(projects.count) cached projects from disk")
            return projects
        } catch {
            logger.error("Failed to load cached projects: \(error.localizedDescription)")
            return []
        }
    }
}
