import Foundation

// MARK: - Production Implementations

/// Bridges real services into the command protocol.
@MainActor
final class LiveQuickEntryCommands: QuickEntryCommands {
    private let timerService: TimerService
    private let activityService: ActivityService
    private let notificationDispatcher: NotificationDispatcher

    init(timerService: TimerService, activityService: ActivityService,
         notificationDispatcher: NotificationDispatcher) {
        self.timerService = timerService
        self.activityService = activityService
        self.notificationDispatcher = notificationDispatcher
    }

    var timerState: TimerState { timerService.timerState }

    func toggleTimer() async {
        await timerService.handleEmptySubmit()
    }

    func startTimer(entry: SearchEntry, description: String) async -> Result<String, QuickEntryCommandError> {
        let result = await timerService.startTimer(
            projectId: entry.projectId, taskId: entry.taskId, description: description
        )
        switch result {
        case .success: return .success(entry.projectName)
        case .failure(let error): return .failure(.apiFailure(error))
        }
    }

    func bookManual(entry: SearchEntry, hours: Double, description: String) async -> Result<String, QuickEntryCommandError> {
        let seconds = Int(hours * 3600)
        let result = await activityService.bookManualEntry(
            date: DateUtilities.todayString(),
            projectId: entry.projectId, taskId: entry.taskId,
            description: description, seconds: seconds
        )
        switch result {
        case .success:
            let formatted = String(format: "%.1fh", hours)
            return .success("\(entry.projectName) (\(formatted))")
        case .failure(let error): return .failure(.apiFailure(error))
        }
    }

    func reportValidationError(_ message: String) {
        notificationDispatcher.send(.apiError, message: message)
    }
}

/// Bridges read-only data sources into the data protocol.
@MainActor
final class LiveQuickEntryDataSource: QuickEntryDataSource {
    private let favoritesManager: FavoritesManager
    private let settings: SettingsStore
    private let recentEntriesTracker: RecentEntriesTracker
    private let descriptionStore: DescriptionStore
    private let entriesProvider: () -> [SearchEntry]
    private let searchFn: (String) -> [FuzzyMatcher.Match]

    init(favoritesManager: FavoritesManager, settings: SettingsStore,
         recentEntriesTracker: RecentEntriesTracker, descriptionStore: DescriptionStore,
         entriesProvider: @escaping () -> [SearchEntry],
         searchFn: @escaping (String) -> [FuzzyMatcher.Match]) {
        self.favoritesManager = favoritesManager
        self.settings = settings
        self.recentEntriesTracker = recentEntriesTracker
        self.descriptionStore = descriptionStore
        self.entriesProvider = entriesProvider
        self.searchFn = searchFn
    }

    var favoritesEnabled: Bool { settings.favoritesEnabled }
    var autoCompleteEnabled: Bool { settings.autoCompleteEnabled }

    func activeFavorites() -> [FavoritesManager.FavoriteEntry] {
        guard favoritesEnabled else { return [] }
        return favoritesManager.activeFavorites(validEntries: entriesProvider())
    }

    func activeRecents(excludingFavoriteIds favIds: Set<String>) -> [RecentEntriesTracker.RecentEntry] {
        recentEntriesTracker.activeEntries(validEntries: entriesProvider())
            .filter { !favIds.contains($0.id) }
    }

    func allEntries() -> [SearchEntry] { entriesProvider() }
    func search(query: String) -> [FuzzyMatcher.Match] { searchFn(query) }
    func suggestDescription(for input: String) -> String? { descriptionStore.suggest(for: input) }
}
