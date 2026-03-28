import Foundation
import os

/// Generic JSON-in-UserDefaults persistence.
/// Provides encode/decode with error logging, eliminating the repeated
/// save/load boilerplate across FavoritesManager, RecentEntriesTracker, etc.
enum JSONStore {
    private static let logger = Logger(category: "JSONStore")
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    /// Save a Codable value to UserDefaults as JSON data.
    static func save<T: Encodable>(_ value: T, key: String) {
        guard let data = try? encoder.encode(value) else {
            logger.error("Failed to encode \(String(describing: T.self)) for key '\(key)'")
            return
        }
        UserDefaults.standard.set(data, forKey: key)
    }

    /// Load a Codable value from UserDefaults. Returns `fallback` if the key is absent or decoding fails.
    static func load<T: Decodable>(_ type: T.Type, key: String, fallback: T) -> T {
        guard let data = UserDefaults.standard.data(forKey: key) else { return fallback }
        guard let decoded = try? decoder.decode(T.self, from: data) else {
            logger.error("Failed to decode \(String(describing: T.self)) for key '\(key)' — using fallback")
            return fallback
        }
        return decoded
    }
}
