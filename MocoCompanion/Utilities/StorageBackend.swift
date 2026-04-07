import Foundation
import os

// MARK: - Storage Backend Protocol

/// Abstraction over where bytes live. Production uses DefaultsBackend or FileBackend;
/// tests inject InMemoryBackend for instant, deterministic persistence.
protocol StorageBackend: Sendable {
    func data(forKey key: String) -> Data?
    func set(_ data: Data, forKey key: String)
    func remove(forKey key: String)
}

// MARK: - UserDefaults Backend

/// UserDefaults-backed storage (production default for most stores).
/// UserDefaults is thread-safe but not marked Sendable; @unchecked is safe here.
struct DefaultsBackend: StorageBackend, @unchecked Sendable {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func data(forKey key: String) -> Data? {
        defaults.data(forKey: key)
    }

    func set(_ data: Data, forKey key: String) {
        defaults.set(data, forKey: key)
    }

    func remove(forKey key: String) {
        defaults.removeObject(forKey: key)
    }
}

// MARK: - File Backend

/// File-backed storage for data that must survive UserDefaults resets.
/// Writes atomically to prevent corruption from mid-write crashes.
struct FileBackend: StorageBackend {
    private let directory: URL

    init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func url(for key: String) -> URL {
        directory.appendingPathComponent("\(key).json")
    }

    func data(forKey key: String) -> Data? {
        try? Data(contentsOf: url(for: key))
    }

    func set(_ data: Data, forKey key: String) {
        try? data.write(to: url(for: key), options: .atomic)
    }

    func remove(forKey key: String) {
        try? FileManager.default.removeItem(at: url(for: key))
    }
}

// MARK: - In-Memory Backend (Tests)

/// In-memory storage for tests. No disk, no UserDefaults, instant teardown.
final class InMemoryBackend: StorageBackend, @unchecked Sendable {
    private var store: [String: Data] = [:]

    func data(forKey key: String) -> Data? { store[key] }
    func set(_ data: Data, forKey key: String) { store[key] = data }
    func remove(forKey key: String) { store[key] = nil }
}

// MARK: - PersistedValue

/// A single persisted Codable value. Load on read, save on write.
///
///     private let store = PersistedValue<[FavoriteEntry]>(key: "favoriteEntries", default: [])
///     favorites = store.load()
///     store.save(favorites)
///
private enum PersistedValueConstants {
    static let encoder = JSONEncoder()
    static let decoder = JSONDecoder()
    static let logger = Logger(subsystem: "com.mococompanion.app", category: "PersistedValue")
}

struct PersistedValue<T: Codable> {
    let key: String
    private let fallback: T
    private let backend: StorageBackend

    init(key: String, default fallback: T, backend: StorageBackend = DefaultsBackend()) {
        self.key = key
        self.fallback = fallback
        self.backend = backend
    }

    /// Load the current persisted value, or fallback if absent/corrupt.
    func load() -> T {
        guard let data = backend.data(forKey: key) else { return fallback }
        guard let decoded = try? PersistedValueConstants.decoder.decode(T.self, from: data) else {
            PersistedValueConstants.logger.error("Decode failed for '\(key)' — using fallback")
            return fallback
        }
        return decoded
    }

    /// Persist a new value, replacing whatever was stored.
    func save(_ value: T) {
        guard let data = try? PersistedValueConstants.encoder.encode(value) else {
            PersistedValueConstants.logger.error("Encode failed for '\(key)'")
            return
        }
        backend.set(data, forKey: key)
    }

    /// Remove the persisted value entirely.
    func clear() {
        backend.remove(forKey: key)
    }
}
