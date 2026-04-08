import Foundation

/// Observable wrapper around a PersistedValue that auto-saves on mutation.
/// Eliminates the repeated init→load→mutate→save pattern across persistence classes.
///
///     let state = PersistedState(key: "favorites", default: [FavoriteEntry]())
///     state.update { $0.append(newEntry) }  // mutates and persists in one call
///
@Observable
@MainActor
final class PersistedState<T: Codable & Sendable>: Sendable {
    private let store: PersistedValue<T>

    /// The current in-memory value. Updated via `update()`.
    private(set) var value: T

    init(key: String, default defaultValue: T, backend: StorageBackend = DefaultsBackend()) {
        self.store = PersistedValue(key: key, default: defaultValue, backend: backend)
        self.value = store.load()
    }

    /// Mutate the value and persist. The mutation closure receives an inout reference.
    func update(_ mutation: (inout T) -> Void) {
        mutation(&value)
        store.save(value)
    }

    /// Replace the value entirely and persist.
    func set(_ newValue: T) {
        value = newValue
        store.save(newValue)
    }
}
