import Foundation

/// Owns the state machine and computed properties for the quick-entry flow.
/// Phases: searching → describing → success/error.
/// QuickEntryView delegates state queries and transitions to this object.
@Observable
@MainActor
final class QuickEntryStateMachine {

    // MARK: - Types

    enum FocusField {
        case search
        case description
        case hours
    }

    enum EntryPhase {
        case searching
        case describing
        case success(projectName: String)
        case error(message: String)

        var animationKey: String {
            switch self {
            case .searching: "searching"
            case .describing: "describing"
            case .success: "success"
            case .error: "error"
            }
        }

        var isSearching: Bool {
            if case .searching = self { return true }
            return false
        }

        var isDescribing: Bool {
            if case .describing = self { return true }
            return false
        }
    }

    enum ResultSection: Equatable {
        case favorite, recent, suggestion, search
    }

    // MARK: - State

    var searchText = "" {
        didSet {
            _cachedDisplayItems = nil
            _cachedSearchResults = nil
            hoveredIndex = nil
            scheduleSearchDebounce()
            // Editing the search field while an entry is selected cancels the
            // selection and returns to the search list.
            if phase.isDescribing && searchText != oldValue {
                phase = .searching
                selectedEntry = nil
                descriptionText = ""
                autocompleteSuggestion = nil
                isManualMode = false
                manualHours = ""
            }
        }
    }
    var descriptionText = ""
    var selectedIndex = -1
    var selectedEntry: SearchEntry?
    var isSubmitting = false
    var phase: EntryPhase = .searching
    var hoveredIndex: Int? = nil
    var autocompleteSuggestion: String? = nil
    var isManualMode = false
    var manualHours = ""

    /// Debounced search flag — views read displayItems which check this.
    private var searchReady = true
    private var debounceTask: Task<Void, Never>?

    /// Cached display items — invalidated on searchText change.
    private var _cachedDisplayItems: [(entry: SearchEntry, section: ResultSection, description: String?)]?
    private var _cachedSearchResults: [FuzzyMatcher.Match]?

    // MARK: - Dependencies

    private let commands: QuickEntryCommands
    private let dataSource: QuickEntryDataSource

    init(commands: QuickEntryCommands, dataSource: QuickEntryDataSource) {
        self.commands = commands
        self.dataSource = dataSource
    }

    // MARK: - Computed Properties

    var extractedTag: String? {
        TagExtractor.extract(from: descriptionText)
    }

    var hasActiveTimer: Bool {
        commands.timerState != .idle
    }

    var isSearchEmpty: Bool {
        searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var hasMinSearchChars: Bool {
        searchText.trimmingCharacters(in: .whitespaces).count >= 2
    }

    var showingFavorites: Bool {
        !hasMinSearchChars && !activeFavorites.isEmpty
    }

    var showingRecents: Bool {
        !hasMinSearchChars && !activeRecents.isEmpty
    }

    var activeFavorites: [FavoritesManager.FavoriteEntry] {
        dataSource.activeFavorites()
    }

    var activeRecents: [RecentEntriesTracker.RecentEntry] {
        let favIds = Set(activeFavorites.map(\.id))
        return dataSource.activeRecents(excludingFavoriteIds: favIds)
    }

    var displayItems: [(entry: SearchEntry, section: ResultSection, description: String?)] {
        if let cached = _cachedDisplayItems { return cached }
        let result = computeDisplayItems()
        _cachedDisplayItems = result
        return result
    }

    var searchResults: [FuzzyMatcher.Match] {
        if let cached = _cachedSearchResults { return cached }
        let result = displayItems.map { FuzzyMatcher.Match(entry: $0.entry, score: 0, matchedIndices: []) }
        _cachedSearchResults = result
        return result
    }

    private func computeDisplayItems() -> [(entry: SearchEntry, section: ResultSection, description: String?)] {
        if !hasMinSearchChars {
            var items: [(SearchEntry, ResultSection, String?)] = []
            for fav in activeFavorites {
                items.append((SearchEntry(from: fav), .favorite, nil))
            }
            for recent in activeRecents {
                items.append((SearchEntry(from: recent), .recent, recent.description.isEmpty ? nil : recent.description))
            }
            if items.isEmpty {
                for entry in dataSource.allEntries().prefix(5) {
                    items.append((entry, .suggestion, nil))
                }
            }
            return items
        }
        return dataSource.search(query: searchText).map { match in
            (match.entry, ResultSection.search, nil)
        }
    }

    private func scheduleSearchDebounce() {
        debounceTask?.cancel()
        // For empty or short queries, no debounce needed
        guard searchText.trimmingCharacters(in: .whitespaces).count >= 2 else {
            _cachedDisplayItems = nil
            _cachedSearchResults = nil
            return
        }
        debounceTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            _cachedDisplayItems = nil
            _cachedSearchResults = nil
        }
    }

    // MARK: - Actions

    func reset() {
        searchText = ""
        descriptionText = ""
        selectedIndex = hasActiveTimer ? -1 : 0
        selectedEntry = nil
        isSubmitting = false
        phase = .searching
        autocompleteSuggestion = nil
        isManualMode = false
        manualHours = ""
        _cachedDisplayItems = nil
        _cachedSearchResults = nil
        debounceTask?.cancel()
    }

    func selectCurrentResult() -> SearchEntry? {
        let items = displayItems
        guard items.indices.contains(selectedIndex) else { return nil }
        let item = items[selectedIndex]
        selectedEntry = item.entry
        phase = .describing
        descriptionText = item.description ?? ""
        autocompleteSuggestion = nil
        return item.entry
    }

    /// Pre-select an entry directly (e.g., from a planned task in the Today view).
    /// Skips the search phase and goes straight to describing.
    func selectEntry(_ entry: SearchEntry) {
        selectedEntry = entry
        phase = .describing
        descriptionText = ""
        autocompleteSuggestion = nil
    }

    func moveSelection(by delta: Int) {
        // Snap to hovered row so keyboard continues from mouse position
        if let hovered = hoveredIndex {
            selectedIndex = hovered
            hoveredIndex = nil
        } else {
            hoveredIndex = nil
        }
        let count = searchResults.count
        let minIndex = (isSearchEmpty && hasActiveTimer) ? -1 : 0
        let maxIndex = count - 1
        if count == 0 && hasActiveTimer {
            selectedIndex = -1
            return
        }
        guard count > 0 else { return }
        let newIndex = selectedIndex + delta
        selectedIndex = max(minIndex, min(maxIndex, newIndex))
    }

    func selectByIndex(_ index: Int) -> SearchEntry? {
        guard searchResults.indices.contains(index) else { return nil }
        selectedIndex = index
        return selectCurrentResult()
    }

    func updateAutocompleteSuggestion() {
        guard dataSource.autoCompleteEnabled else {
            autocompleteSuggestion = nil
            return
        }
        autocompleteSuggestion = dataSource.suggestDescription(for: descriptionText)
    }

    func acceptAutocomplete() -> Bool {
        guard let suggestion = autocompleteSuggestion else { return false }
        descriptionText = suggestion
        autocompleteSuggestion = nil
        return true
    }

    // MARK: - Submit

    /// Result of a submit operation. View uses this to decide animations and panel close.
    enum SubmitResult {
        case success(displayName: String)
        case validationError
        case apiError
    }

    /// Handle empty-search submit: pause/resume timer or select current result.
    /// Returns true if the action was handled (timer toggle), false if the view should select a result.
    func handleEmptySubmit() -> Bool {
        if selectedIndex == -1 && hasActiveTimer {
            Task { await commands.toggleTimer() }
            return true
        }
        return false
    }

    /// Submit a description — either start a timer or book manual hours.
    func submitDescription() async -> SubmitResult {
        guard let entry = selectedEntry else { return .apiError }

        if isManualMode {
            guard let hours = DateUtilities.parseHours(manualHours), hours > 0, hours <= 24 else {
                commands.reportValidationError(String(localized: "validation.hours"))
                return .validationError
            }

            isSubmitting = true
            let result = await commands.bookManual(entry: entry, hours: hours, description: descriptionText)
            isSubmitting = false

            switch result {
            case .failure(let commandError):
                if case .apiFailure(let mocoError) = commandError {
                    phase = .error(message: mocoError.errorDescription ?? "Unknown error")
                }
                return .apiError
            case .success(let displayName):
                phase = .success(projectName: displayName)
                return .success(displayName: displayName)
            }
        } else {
            isSubmitting = true
            let result = await commands.startTimer(entry: entry, description: descriptionText)
            isSubmitting = false

            switch result {
            case .failure(let commandError):
                if case .apiFailure(let mocoError) = commandError {
                    phase = .error(message: mocoError.errorDescription ?? "Unknown error")
                }
                return .apiError
            case .success(let displayName):
                phase = .success(projectName: displayName)
                return .success(displayName: displayName)
            }
        }
    }
}
