import Foundation
import os

/// Manages a persistent list of favorite project+task combos.
/// Stored as JSON in UserDefaults. Max 5 favorites.
@Observable
@MainActor
final class FavoritesManager {
    private static let logger = Logger(category: "Favorites")
    static let maxFavorites = 5

    private let state: PersistedState<[FavoriteEntry]>
    private let notifications: NotificationDispatcher?

    /// Persisted favorite entries.
    var favorites: [FavoriteEntry] { state.value }

    init(backend: StorageBackend = DefaultsBackend(), notifications: NotificationDispatcher? = nil) {
        self.state = PersistedState(key: "favoriteEntries", default: [], backend: backend)
        self.notifications = notifications
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
        state.update { favorites in
            if let index = favorites.firstIndex(where: { $0.projectId == entry.projectId && $0.taskId == entry.taskId }) {
                let removed = favorites.remove(at: index)
                FavoritesManager.logger.info("Removed favorite: \(removed.displayText)")
            } else {
                guard favorites.count < FavoritesManager.maxFavorites else {
                    FavoritesManager.logger.info("Cannot add favorite — max \(FavoritesManager.maxFavorites) reached")
                    notifications?.favoritesLimitReached()
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
                FavoritesManager.logger.info("Added favorite: \(fav.displayText)")
            }
        }
    }

    /// Remove a favorite by its ID.
    func remove(id: String) {
        state.update { favorites in
            if let index = favorites.firstIndex(where: { $0.id == id }) {
                let removed = favorites.remove(at: index)
                FavoritesManager.logger.info("Removed favorite: \(removed.displayText)")
            }
        }
    }

    /// Move favorites for drag-to-reorder. Persists new order.
    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        state.update { $0.move(fromOffsets: source, toOffset: destination) }
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
}
