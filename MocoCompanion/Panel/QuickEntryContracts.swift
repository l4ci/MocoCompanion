import Foundation

/// All side effects the quick-entry flow can produce.
/// Replaces 3 direct service dependencies with a single mockable interface.
@MainActor
protocol QuickEntryCommands {
    /// Current timer state — read by search logic for selection behavior.
    var timerState: TimerState { get }

    /// Pause or resume the running timer (empty-submit behavior).
    func toggleTimer() async

    /// Start a timer for the given entry. Returns the display name on success.
    func startTimer(entry: SearchEntry, description: String) async -> Result<String, QuickEntryCommandError>

    /// Book manual hours for the given entry. Returns the display name on success.
    func bookManual(entry: SearchEntry, hours: Double, description: String) async -> Result<String, QuickEntryCommandError>

    /// Report a validation error to the user.
    func reportValidationError(_ message: String)
}

enum QuickEntryCommandError: Error {
    case apiFailure(MocoError)
}

/// All read-only data sources the quick-entry flow needs.
/// Replaces 4 service refs + 2 closures with a single mockable interface.
@MainActor
protocol QuickEntryDataSource {
    var favoritesEnabled: Bool { get }
    var autoCompleteEnabled: Bool { get }
    func activeFavorites() -> [FavoritesManager.FavoriteEntry]
    func activeRecents(excludingFavoriteIds: Set<String>) -> [RecentEntriesTracker.RecentEntry]
    func allEntries() -> [SearchEntry]
    func search(query: String) -> [FuzzyMatcher.Match]
    func suggestDescription(for input: String) -> String?
}
