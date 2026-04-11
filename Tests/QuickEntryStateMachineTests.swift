import Testing
import Foundation
@testable import MocoCompanion

// MARK: - Mocks

@MainActor
final class MockQuickEntryCommands: QuickEntryCommands {
    var timerState: TimerState = .idle
    var toggleTimerCalled = false
    var startTimerResult: Result<String, QuickEntryCommandError> = .success("TestProject")
    var bookManualResult: Result<String, QuickEntryCommandError> = .success("TestProject (1.5h)")
    var lastValidationError: String?

    func toggleTimer() async { toggleTimerCalled = true }

    func startTimer(entry: SearchEntry, description: String) async -> Result<String, QuickEntryCommandError> {
        startTimerResult
    }

    func bookManual(entry: SearchEntry, hours: Double, description: String) async -> Result<String, QuickEntryCommandError> {
        bookManualResult
    }

    func reportValidationError(_ message: String) {
        lastValidationError = message
    }
}

@MainActor
final class MockQuickEntryDataSource: QuickEntryDataSource {
    var favoritesEnabled = true
    var autoCompleteEnabled = false
    var favorites: [FavoritesManager.FavoriteEntry] = []
    var recents: [RecentEntriesTracker.RecentEntry] = []
    var entries: [SearchEntry] = []
    var searchResults: [FuzzyMatcher.Match] = []

    func activeFavorites() -> [FavoritesManager.FavoriteEntry] { favorites }
    func activeRecents(excludingFavoriteIds: Set<String>) -> [RecentEntriesTracker.RecentEntry] {
        recents.filter { !excludingFavoriteIds.contains($0.id) }
    }
    func allEntries() -> [SearchEntry] { entries }
    func search(query: String) -> [FuzzyMatcher.Match] { searchResults }
    func suggestDescription(for input: String) -> String? {
        guard autoCompleteEnabled, !input.isEmpty else { return nil }
        return input + "-autocomplete"
    }
}

// MARK: - Helpers

private func makeEntry(projectId: Int = 1, taskId: Int = 10, projectName: String = "Project", taskName: String = "Task") -> SearchEntry {
    SearchEntry(projectId: projectId, taskId: taskId, customerName: "Customer", projectName: projectName, taskName: taskName)
}

private func makeFavorite(projectId: Int = 1, taskId: Int = 10) -> FavoritesManager.FavoriteEntry {
    FavoritesManager.FavoriteEntry(projectId: projectId, taskId: taskId, customerName: "Cust", projectName: "FavProject", taskName: "FavTask")
}

private func makeRecent(projectId: Int = 2, taskId: Int = 20, description: String = "some work") -> RecentEntriesTracker.RecentEntry {
    RecentEntriesTracker.RecentEntry(projectId: projectId, taskId: taskId, customerName: "Cust", projectName: "RecentProject", taskName: "RecentTask", description: description, date: Date())
}

// MARK: - Tests

@Suite("QuickEntryStateMachine")
struct QuickEntryStateMachineTests {

    @MainActor
    private func makeSM(
        commands: MockQuickEntryCommands = MockQuickEntryCommands(),
        dataSource: MockQuickEntryDataSource = MockQuickEntryDataSource()
    ) -> (QuickEntryStateMachine, MockQuickEntryCommands, MockQuickEntryDataSource) {
        let sm = QuickEntryStateMachine(commands: commands, dataSource: dataSource)
        return (sm, commands, dataSource)
    }

    // MARK: - Initial State

    @Test("Initial phase is searching")
    @MainActor func initialState() {
        let (sm, _, _) = makeSM()
        #expect(sm.phase.isSearching)
        #expect(sm.selectedEntry == nil)
        #expect(sm.isSubmitting == false)
    }

    // MARK: - Display Items

    @Test("Empty search shows favorites then recents")
    @MainActor func displayItemsFavoritesAndRecents() {
        let ds = MockQuickEntryDataSource()
        ds.favorites = [makeFavorite(projectId: 1)]
        ds.recents = [makeRecent(projectId: 2)]
        let (sm, _, _) = makeSM(dataSource: ds)

        let items = sm.displayItems
        #expect(items.count == 2)
        #expect(items[0].section == .favorite)
        #expect(items[1].section == .recent)
    }

    @Test("Empty search falls back to suggestions when no favorites or recents")
    @MainActor func displayItemsSuggestions() {
        let ds = MockQuickEntryDataSource()
        ds.entries = (1...8).map { makeEntry(projectId: $0, taskId: $0 * 10, projectName: "P\($0)") }
        let (sm, _, _) = makeSM(dataSource: ds)

        let items = sm.displayItems
        #expect(items.count == 5) // capped at 5
        #expect(items[0].section == .suggestion)
    }

    @Test("Short search query (<2 chars) returns empty")
    @MainActor func shortSearchReturnsEmpty() {
        let (sm, _, _) = makeSM()
        sm.searchText = "A"
        #expect(sm.displayItems.isEmpty)
    }

    @Test("Search query >= 2 chars uses search function")
    @MainActor func searchUsesDataSource() {
        let ds = MockQuickEntryDataSource()
        let entry = makeEntry()
        ds.searchResults = [FuzzyMatcher.Match(entry: entry, score: 1.0, matchedIndices: [])]
        let (sm, _, _) = makeSM(dataSource: ds)

        sm.searchText = "Pro"
        // Note: debounce may delay, but displayItems should compute immediately for >= 2 chars
        let items = sm.displayItems
        #expect(items.count == 1)
        #expect(items[0].section == .search)
    }

    // MARK: - Selection & Phase Transitions

    @Test("selectCurrentResult transitions to describing phase")
    @MainActor func selectTransitionsToDescribing() {
        let ds = MockQuickEntryDataSource()
        ds.favorites = [makeFavorite()]
        let (sm, _, _) = makeSM(dataSource: ds)

        sm.selectedIndex = 0
        let entry = sm.selectCurrentResult()

        #expect(entry != nil)
        #expect(sm.phase.isDescribing)
        #expect(sm.selectedEntry?.projectName == "FavProject")
    }

    @Test("selectCurrentResult with invalid index returns nil")
    @MainActor func selectInvalidIndex() {
        let (sm, _, _) = makeSM()
        sm.selectedIndex = 99
        let entry = sm.selectCurrentResult()
        #expect(entry == nil)
        #expect(sm.phase.isSearching) // no transition
    }

    @Test("selectEntry skips search and goes to describing")
    @MainActor func selectEntryDirect() {
        let (sm, _, _) = makeSM()
        let entry = makeEntry(projectName: "DirectProject")
        sm.selectEntry(entry)

        #expect(sm.phase.isDescribing)
        #expect(sm.selectedEntry?.projectName == "DirectProject")
        #expect(sm.descriptionText == "")
    }

    @Test("editing searchText while describing returns to searching and clears selection")
    @MainActor func editSearchTextDuringDescribingResets() {
        let ds = MockQuickEntryDataSource()
        ds.favorites = [makeFavorite()]
        let (sm, _, _) = makeSM(dataSource: ds)

        // Enter describing phase via a selection.
        sm.selectedIndex = 0
        _ = sm.selectCurrentResult()
        #expect(sm.phase.isDescribing)
        #expect(sm.selectedEntry != nil)

        // Simulate user filling in description/manual state.
        sm.descriptionText = "half-written note"
        sm.isManualMode = true
        sm.manualHours = "1.5"
        sm.autocompleteSuggestion = "suggestion"

        // User edits the search field.
        sm.searchText = "new query"

        #expect(sm.phase.isSearching)
        #expect(sm.selectedEntry == nil)
        #expect(sm.descriptionText == "")
        #expect(sm.autocompleteSuggestion == nil)
        #expect(sm.isManualMode == false)
        #expect(sm.manualHours == "")
    }

    @Test("clearing searchText via ✕ while describing returns to searching")
    @MainActor func clearSearchTextDuringDescribingResets() {
        let ds = MockQuickEntryDataSource()
        ds.favorites = [makeFavorite()]
        let (sm, _, _) = makeSM(dataSource: ds)

        sm.searchText = "foo"
        sm.selectedIndex = 0
        _ = sm.selectCurrentResult()
        #expect(sm.phase.isDescribing)

        // Clicking the ✕ button sets searchText = "".
        sm.searchText = ""

        #expect(sm.phase.isSearching)
        #expect(sm.selectedEntry == nil)
    }

    // MARK: - Navigation

    @Test("moveSelection clamps to bounds")
    @MainActor func moveSelectionClamps() {
        let ds = MockQuickEntryDataSource()
        ds.favorites = [makeFavorite(), makeFavorite(projectId: 2, taskId: 20)]
        let (sm, _, _) = makeSM(dataSource: ds)

        sm.selectedIndex = 0
        sm.moveSelection(by: -5)
        #expect(sm.selectedIndex == 0)

        sm.moveSelection(by: 100)
        #expect(sm.selectedIndex == 1) // 2 items, max index = 1
    }

    @Test("moveSelection allows -1 when timer is active")
    @MainActor func moveSelectionTimerHint() {
        let cmds = MockQuickEntryCommands()
        cmds.timerState = .running(activityId: 1, projectName: "P")
        let ds = MockQuickEntryDataSource()
        ds.favorites = [makeFavorite()]
        let (sm, _, _) = makeSM(commands: cmds, dataSource: ds)

        sm.selectedIndex = 0
        sm.moveSelection(by: -1)
        #expect(sm.selectedIndex == -1) // -1 = timer toggle position
    }

    // MARK: - Empty Submit

    @Test("Empty submit with active timer toggles timer")
    @MainActor func emptySubmitTogglesTimer() async {
        let cmds = MockQuickEntryCommands()
        cmds.timerState = .running(activityId: 1, projectName: "P")
        let (sm, _, _) = makeSM(commands: cmds)

        sm.selectedIndex = -1
        let handled = sm.handleEmptySubmit()
        #expect(handled == true)
    }

    @Test("Empty submit without active timer returns false")
    @MainActor func emptySubmitNoTimer() {
        let (sm, _, _) = makeSM()
        sm.selectedIndex = 0
        let handled = sm.handleEmptySubmit()
        #expect(handled == false)
    }

    // MARK: - Submit Description

    @Test("Submit starts timer and transitions to success")
    @MainActor func submitStartsTimer() async {
        let cmds = MockQuickEntryCommands()
        cmds.startTimerResult = .success("MyProject")
        let (sm, _, _) = makeSM(commands: cmds)

        sm.selectEntry(makeEntry(projectName: "MyProject"))
        sm.descriptionText = "working on feature"

        let result = await sm.submitDescription()
        if case .success(let name) = result {
            #expect(name == "MyProject")
        } else {
            Issue.record("Expected .success, got \(result)")
        }
    }

    @Test("Submit API failure returns .apiError")
    @MainActor func submitApiFailure() async {
        let cmds = MockQuickEntryCommands()
        cmds.startTimerResult = .failure(.apiFailure(.serverError(statusCode: 500, message: "boom")))
        let (sm, _, _) = makeSM(commands: cmds)

        sm.selectEntry(makeEntry())
        let result = await sm.submitDescription()
        if case .apiError = result {
            // expected
        } else {
            Issue.record("Expected .apiError, got \(result)")
        }
    }

    @Test("Manual mode with invalid hours returns .validationError")
    @MainActor func manualInvalidHours() async {
        let cmds = MockQuickEntryCommands()
        let (sm, _, _) = makeSM(commands: cmds)

        sm.selectEntry(makeEntry())
        sm.isManualMode = true
        sm.manualHours = "abc"

        let result = await sm.submitDescription()
        if case .validationError = result {
            #expect(cmds.lastValidationError != nil)
        } else {
            Issue.record("Expected .validationError, got \(result)")
        }
    }

    @Test("Manual mode with valid hours books manual entry")
    @MainActor func manualValidHours() async {
        let cmds = MockQuickEntryCommands()
        cmds.bookManualResult = .success("Project (1.5h)")
        let (sm, _, _) = makeSM(commands: cmds)

        sm.selectEntry(makeEntry())
        sm.isManualMode = true
        sm.manualHours = "1.5"

        let result = await sm.submitDescription()
        if case .success(let name) = result {
            #expect(name == "Project (1.5h)")
        } else {
            Issue.record("Expected .success, got \(result)")
        }
    }

    // MARK: - Reset

    @Test("Reset clears all state")
    @MainActor func resetClearsState() {
        let (sm, _, _) = makeSM()

        sm.searchText = "test"
        sm.descriptionText = "desc"
        sm.selectedIndex = 5
        sm.isManualMode = true
        sm.manualHours = "2"

        sm.reset()

        #expect(sm.searchText == "")
        #expect(sm.descriptionText == "")
        #expect(sm.selectedIndex == 0) // no active timer → 0
        #expect(sm.phase.isSearching)
        #expect(sm.isManualMode == false)
        #expect(sm.manualHours == "")
    }

    @Test("Reset with active timer sets index to -1")
    @MainActor func resetWithTimer() {
        let cmds = MockQuickEntryCommands()
        cmds.timerState = .running(activityId: 1, projectName: "P")
        let (sm, _, _) = makeSM(commands: cmds)

        sm.reset()
        #expect(sm.selectedIndex == -1)
    }

    // MARK: - Autocomplete

    @Test("Autocomplete suggestion updates when enabled")
    @MainActor func autocompleteSuggestion() {
        let ds = MockQuickEntryDataSource()
        ds.autoCompleteEnabled = true
        let (sm, _, _) = makeSM(dataSource: ds)

        sm.descriptionText = "work"
        sm.updateAutocompleteSuggestion()
        #expect(sm.autocompleteSuggestion == "work-autocomplete")
    }

    @Test("Accept autocomplete replaces description text")
    @MainActor func acceptAutocomplete() {
        let ds = MockQuickEntryDataSource()
        ds.autoCompleteEnabled = true
        let (sm, _, _) = makeSM(dataSource: ds)

        sm.descriptionText = "work"
        sm.updateAutocompleteSuggestion()

        let accepted = sm.acceptAutocomplete()
        #expect(accepted == true)
        #expect(sm.descriptionText == "work-autocomplete")
        #expect(sm.autocompleteSuggestion == nil)
    }

    @Test("Accept autocomplete returns false when no suggestion")
    @MainActor func acceptAutocompleteNoSuggestion() {
        let (sm, _, _) = makeSM()
        let accepted = sm.acceptAutocomplete()
        #expect(accepted == false)
    }

    // MARK: - Recents exclude favorites

    @Test("Recents exclude entries that are also favorites")
    @MainActor func recentsExcludeFavorites() {
        let ds = MockQuickEntryDataSource()
        let fav = makeFavorite(projectId: 1, taskId: 10)
        ds.favorites = [fav]
        ds.recents = [
            makeRecent(projectId: 1, taskId: 10), // same as favorite — excluded
            makeRecent(projectId: 2, taskId: 20),  // different — kept
        ]
        let (sm, _, _) = makeSM(dataSource: ds)

        let items = sm.displayItems
        let recentItems = items.filter { $0.section == .recent }
        #expect(recentItems.count == 1)
        #expect(recentItems[0].entry.projectId == 2)
    }
}
