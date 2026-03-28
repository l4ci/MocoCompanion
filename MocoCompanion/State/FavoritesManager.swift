import Foundation
import os

/// Manages a persistent list of favorite project+task combos.
/// Stored as JSON in UserDefaults. Max 5 favorites.
@Observable
@MainActor
final class FavoritesManager {
    private static let logger = Logger(category: "Favorites")
    private static let storageKey = "favoriteEntries"
    static let maxFavorites = 5

    /// Persisted favorite entries.
    private(set) var favorites: [FavoriteEntry] = []

    init() {
        favorites = Self.load()
    }

    // MARK: - Model

    /// A favorite project+task combo, persisted as JSON.
    struct FavoriteEntry: ProjectTaskRef, Codable, Equatable {
        let projectId: Int
        let taskId: Int
        let customerName: String
        let projectName: String
        let taskName: String
    }

    // MARK: - Public API

    /// Whether a given project+task combo is a favorite.
    func isFavorite(projectId: Int, taskId: Int) -> Bool {
        favorites.contains { $0.projectId == projectId && $0.taskId == taskId }
    }

    /// Toggle favorite status for a search entry.
    /// If already a favorite, removes it. Otherwise adds it (respecting max cap).
    func toggle(_ entry: SearchEntry) {
        if let index = favorites.firstIndex(where: { $0.projectId == entry.projectId && $0.taskId == entry.taskId }) {
            let removed = favorites.remove(at: index)
            Self.logger.info("Removed favorite: \(removed.displayText)")
        } else {
            guard favorites.count < Self.maxFavorites else {
                Self.logger.info("Cannot add favorite — max \(Self.maxFavorites) reached")
                return
            }
            let fav = FavoriteEntry(
                projectId: entry.projectId,
                taskId: entry.taskId,
                customerName: entry.customerName,
                projectName: entry.projectName,
                taskName: entry.taskName
            )
            favorites.append(fav)
            Self.logger.info("Added favorite: \(fav.displayText)")
        }
        save()
    }

    /// Remove a favorite by its ID.
    func remove(id: String) {
        if let index = favorites.firstIndex(where: { $0.id == id }) {
            let removed = favorites.remove(at: index)
            Self.logger.info("Removed favorite: \(removed.displayText)")
            save()
        }
    }

    /// Move favorites for drag-to-reorder. Persists new order.
    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        favorites.move(fromOffsets: source, toOffset: destination)
        save()
        Self.logger.info("Reordered favorites")
    }

    /// Return only favorites that still exist in the current search entries.
    /// Filters out deactivated/removed projects without deleting them from persistence
    /// (they may reappear if re-activated).
    func activeFavorites(validEntries: [SearchEntry]) -> [FavoriteEntry] {
        let validIds = Set(validEntries.map(\.id))
        let active = favorites.filter { validIds.contains($0.id) }
        let staleCount = favorites.count - active.count
        if staleCount > 0 {
            Self.logger.info("Filtered \(staleCount) stale favorite(s)")
        }
        return active
    }

    // MARK: - Persistence

    private func save() {
        JSONStore.save(favorites, key: Self.storageKey)
    }

    private static func load() -> [FavoriteEntry] {
        JSONStore.load([FavoriteEntry].self, key: storageKey, fallback: [])
    }
}
