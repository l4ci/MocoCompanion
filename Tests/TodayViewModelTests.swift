import Testing
import Foundation
import SwiftUI
import AppKit

@Suite("TodayViewModel")
struct TodayViewModelTests {

    // MARK: - Helpers

    /// Constructs a TodayViewModel with real TimerService + ActivityService backed by mock APIs.
    /// Follows the same closure-based mock pattern as ActivityServiceTests and TimerServiceTests.
    @MainActor
    private func makeViewModel(
        timerAPI: MockTimerAPI = MockTimerAPI(),
        activityAPI: MockActivityAPI = MockActivityAPI()
    ) -> (TodayViewModel, TimerService, ActivityService) {
        let dispatcher = NotificationDispatcher(isEnabledCheck: { _ in false })

        let timerService = TimerService(
            clientFactory: { timerAPI },
            userIdProvider: { 42 }
        )

        let activityService = ActivityService(
            clientFactory: { activityAPI },
            notificationDispatcher: dispatcher,
            userIdProvider: { 42 }
        )

        // Wire extracted stores for forwarding
        let planningStore = PlanningStore(
            clientFactory: { activityAPI },
            userIdProvider: { 42 },
            todayActivitiesProvider: { [weak activityService] in activityService?.todayActivities ?? [] }
        )
        activityService.planningStore = planningStore
        let deleteUndo = DeleteUndoManager(
            clientFactory: { activityAPI },
            activityService: activityService,
            notificationDispatcher: dispatcher
        )
        activityService.deleteUndoManager = deleteUndo

        let favoritesManager = FavoritesManager(backend: InMemoryBackend())

        let viewModel = TodayViewModel(
            timerService: timerService,
            activityService: activityService,
            favoritesManager: favoritesManager
        )

        return (viewModel, timerService, activityService)
    }

    /// Populate the activity service with today activities and return the view model.
    @MainActor
    private func makeViewModelWithActivities(
        _ activities: [MocoActivity],
        timerAPI: MockTimerAPI = MockTimerAPI()
    ) async -> (TodayViewModel, TimerService, ActivityService) {
        var api = MockActivityAPI()
        api.fetchActivitiesHandler = { _, _, _ in activities }
        let (vm, ts, as_) = makeViewModel(timerAPI: timerAPI, activityAPI: api)
        await as_.refreshTodayStats()
        return (vm, ts, as_)
    }

    // MARK: - moveSelection

    @Test("moveSelection down increments selectedIndex")
    @MainActor func moveSelectionDown() async {
        let a1 = TestFactories.makeActivity(id: 1)
        let a2 = TestFactories.makeActivity(id: 2)
        let (vm, _, _) = await makeViewModelWithActivities([a1, a2])

        #expect(vm.selectedIndex == 0)
        vm.moveSelection(by: 1)
        #expect(vm.selectedIndex == 1)
    }

    @Test("moveSelection up from 0 clamps to 0")
    @MainActor func moveSelectionUpClamps() async {
        let a1 = TestFactories.makeActivity(id: 1)
        let (vm, _, _) = await makeViewModelWithActivities([a1])

        #expect(vm.selectedIndex == 0)
        vm.moveSelection(by: -1)
        #expect(vm.selectedIndex == 0)
    }

    @Test("moveSelection beyond count clamps to last index")
    @MainActor func moveSelectionBeyondCount() async {
        let a1 = TestFactories.makeActivity(id: 1)
        let a2 = TestFactories.makeActivity(id: 2)
        let (vm, _, _) = await makeViewModelWithActivities([a1, a2])

        vm.moveSelection(by: 10)
        #expect(vm.selectedIndex == 1)
    }

    @Test("moveSelection does nothing when list is empty")
    @MainActor func moveSelectionEmptyList() {
        let (vm, _, _) = makeViewModel()
        vm.moveSelection(by: 1)
        #expect(vm.selectedIndex == 0)
    }

    // MARK: - selectByShortcut

    @Test("selectByShortcut maps index correctly with no active entry")
    @MainActor func selectByShortcutNoActive() async {
        let a1 = TestFactories.makeActivity(id: 1, timerStartedAt: nil)
        let a2 = TestFactories.makeActivity(id: 2, timerStartedAt: nil)
        let a3 = TestFactories.makeActivity(id: 3, timerStartedAt: nil)
        let (vm, _, _) = await makeViewModelWithActivities([a1, a2, a3])

        // No active entry, so shortcut index maps directly
        vm.selectByShortcut(2)
        #expect(vm.selectedIndex == 2)
    }

    @Test("selectByShortcut skips active entry index")
    @MainActor func selectByShortcutSkipsActive() async {
        // Active entry (timer running) sorts first in sortedActivities
        let running = TestFactories.makeActivity(id: 1, timerStartedAt: "2026-04-01T10:00:00Z")
        let stopped1 = TestFactories.makeActivity(id: 2, timerStartedAt: nil)
        let stopped2 = TestFactories.makeActivity(id: 3, timerStartedAt: nil)
        let (vm, _, _) = await makeViewModelWithActivities([running, stopped1, stopped2])

        // activeEntryIndex should be 0 (the running one)
        #expect(vm.activeEntryIndex == 0)

        // shortcut 0 targets visual index 0, but since activeIdx=0, mapped becomes 0+1=1
        vm.selectByShortcut(0)
        #expect(vm.selectedIndex == 1)

        // shortcut 1 targets visual index 1, since 1 >= activeIdx(0), mapped becomes 1+1=2
        vm.selectByShortcut(1)
        #expect(vm.selectedIndex == 2)
    }

    @Test("selectByShortcut ignores out-of-range shortcut")
    @MainActor func selectByShortcutOutOfRange() async {
        let a1 = TestFactories.makeActivity(id: 1, timerStartedAt: nil)
        let (vm, _, _) = await makeViewModelWithActivities([a1])

        vm.selectedIndex = 0
        vm.selectByShortcut(5) // Way out of range
        #expect(vm.selectedIndex == 0) // Unchanged
    }

    // MARK: - shortcutIndex

    @Test("shortcutIndex maps correctly with no active entry")
    @MainActor func shortcutIndexNoActive() async {
        let a1 = TestFactories.makeActivity(id: 1, timerStartedAt: nil)
        let a2 = TestFactories.makeActivity(id: 2, timerStartedAt: nil)
        let (vm, _, _) = await makeViewModelWithActivities([a1, a2])

        #expect(vm.shortcutIndex(for: 0) == 0)
        #expect(vm.shortcutIndex(for: 1) == 1)
    }

    @Test("shortcutIndex returns -1 for active entry")
    @MainActor func shortcutIndexActiveEntry() async {
        let running = TestFactories.makeActivity(id: 1, timerStartedAt: "2026-04-01T10:00:00Z")
        let stopped = TestFactories.makeActivity(id: 2, timerStartedAt: nil)
        let (vm, _, _) = await makeViewModelWithActivities([running, stopped])

        #expect(vm.activeEntryIndex == 0)
        #expect(vm.shortcutIndex(for: 0) == -1) // Active entry gets -1
        #expect(vm.shortcutIndex(for: 1) == 0)  // After active, shifted down by 1
    }

    // MARK: - syncSelectionAfterDataChange

    @Test("syncSelectionAfterDataChange reselects by ID when entry still exists")
    @MainActor func syncReselectsById() async {
        let a1 = TestFactories.makeActivity(id: 1, timerStartedAt: nil)
        let a2 = TestFactories.makeActivity(id: 2, timerStartedAt: nil)
        let (vm, _, activityService) = await makeViewModelWithActivities([a1, a2])

        // Select the second entry
        vm.moveSelection(by: 1)
        #expect(vm.selectedActivityId == 2)
        let versionBefore = vm.dataVersion

        // Data refreshes but entry 2 still exists
        vm.syncSelectionAfterDataChange()

        #expect(vm.selectedActivityId == 2)
        #expect(vm.dataVersion == versionBefore &+ 1)
    }

    @Test("syncSelectionAfterDataChange clamps when selected entry is deleted")
    @MainActor func syncClampsOnDelete() async {
        let a1 = TestFactories.makeActivity(id: 1, timerStartedAt: nil)
        let a2 = TestFactories.makeActivity(id: 2, timerStartedAt: nil)
        var api = MockActivityAPI()
        api.fetchActivitiesHandler = { _, _, _ in [a1, a2] }
        let (vm, _, activityService) = makeViewModel(activityAPI: api)
        await activityService.refreshTodayStats()

        // Select entry at index 1 (id: 2)
        vm.moveSelection(by: 1)
        #expect(vm.selectedIndex == 1)

        // Simulate removing entry 2 — apply directly (mock is a struct, can't mutate after capture)
        activityService.applyFetchedTodayActivities([a1])

        // Now sortedActivities has only 1 item, selectedActivityId=2 won't be found
        vm.syncSelectionAfterDataChange()

        // Should clamp to last valid index (0)
        #expect(vm.selectedIndex == 0)
    }

    @Test("syncSelectionAfterDataChange bumps dataVersion")
    @MainActor func syncBumpsVersion() async {
        let a1 = TestFactories.makeActivity(id: 1)
        let (vm, _, _) = await makeViewModelWithActivities([a1])

        let before = vm.dataVersion
        vm.syncSelectionAfterDataChange()
        #expect(vm.dataVersion == before &+ 1)
    }

    @Test("syncSelectionAfterDataChange clears hoveredActivityId")
    @MainActor func syncClearsHover() async {
        let a1 = TestFactories.makeActivity(id: 1)
        let (vm, _, _) = await makeViewModelWithActivities([a1])

        vm.hoveredActivityId = 1
        vm.syncSelectionAfterDataChange()
        #expect(vm.hoveredActivityId == nil)
    }

    // MARK: - sortedActivities

    @Test("sortedActivities returns today activities on .today")
    @MainActor func sortedActivitiesToday() async {
        let a1 = TestFactories.makeActivity(id: 1)
        let a2 = TestFactories.makeActivity(id: 2)
        let (vm, _, _) = await makeViewModelWithActivities([a1, a2])

        #expect(vm.selectedDay == .today)
        #expect(vm.sortedActivities.count == 2)
    }

    @Test("sortedActivities filters running/active entries on .yesterday")
    @MainActor func sortedActivitiesYesterdayFilters() async {
        // Set up yesterday activities with one running timer
        let calendar = Calendar.current
        let yesterdayDate = calendar.date(byAdding: .day, value: -1, to: Date())!
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let yesterday = formatter.string(from: yesterdayDate)

        let running = TestFactories.makeActivity(id: 1, date: yesterday, timerStartedAt: "2026-04-01T10:00:00Z")
        let stopped = TestFactories.makeActivity(id: 2, date: yesterday, timerStartedAt: nil)

        var api = MockActivityAPI()
        // Today returns empty, yesterday returns our entries
        api.fetchActivitiesHandler = { from, to, _ in
            let today = DateUtilities.todayString()
            if from == today { return [] }
            return [running, stopped]
        }
        let (vm, _, activityService) = makeViewModel(activityAPI: api)
        await activityService.refreshTodayStats()
        await activityService.refreshYesterdayActivities()

        vm.selectedDay = .yesterday

        // Running timer should be filtered out, only stopped remains
        let sorted = vm.sortedActivities
        #expect(sorted.count == 1)
        #expect(sorted.first?.id == 2)
    }

    @Test("sortedActivities returns empty on .tomorrow")
    @MainActor func sortedActivitiesTomorrow() async {
        let a1 = TestFactories.makeActivity(id: 1)
        let (vm, _, _) = await makeViewModelWithActivities([a1])

        vm.selectedDay = .tomorrow
        #expect(vm.sortedActivities.isEmpty)
    }

    // MARK: - isUnplannedSelected / selectedUnplannedTask

    @Test("isUnplannedSelected true when index points past activities to unplanned tasks")
    @MainActor func isUnplannedSelectedTrue() async {
        let a1 = TestFactories.makeActivity(id: 1, projectId: 100, taskId: 200)

        var api = MockActivityAPI()
        api.fetchActivitiesHandler = { _, _, _ in [a1] }
        // Planning entry for a different task (unplanned)
        let planned = TestFactories.makePlanningEntry(id: 10, projectId: 101, taskId: 201, taskName: "Unplanned")
        api.fetchPlanningEntriesHandler = { _, _ in [planned] }

        let (vm, _, activityService) = makeViewModel(activityAPI: api)
        await activityService.refreshTodayStats()
        await activityService.refreshTodayPlanning()

        // 1 activity + 1 unplanned task = 2 navigable items
        #expect(vm.totalNavigableCount == 2)

        // Move to the unplanned task (index 1)
        vm.moveSelection(by: 1)
        #expect(vm.isUnplannedSelected == true)
        #expect(vm.selectedUnplannedTask?.taskId == 201)
    }

    @Test("isUnplannedSelected false when on regular activity")
    @MainActor func isUnplannedSelectedFalse() async {
        let a1 = TestFactories.makeActivity(id: 1)
        let (vm, _, _) = await makeViewModelWithActivities([a1])

        #expect(vm.selectedIndex == 0)
        #expect(vm.isUnplannedSelected == false)
        #expect(vm.selectedUnplannedTask == nil)
    }

    @Test("isUnplannedSelected false on non-today day")
    @MainActor func isUnplannedNotToday() async {
        let a1 = TestFactories.makeActivity(id: 1)
        let (vm, _, _) = await makeViewModelWithActivities([a1])

        vm.selectedDay = .yesterday
        vm.selectedIndex = 5 // Arbitrary index past activities
        #expect(vm.isUnplannedSelected == false)
    }

    // MARK: - Day Switching

    @Test("setting selectedDay resets selectedIndex to 0")
    @MainActor func daySwitchResetsIndex() async {
        let a1 = TestFactories.makeActivity(id: 1)
        let a2 = TestFactories.makeActivity(id: 2)
        let (vm, _, _) = await makeViewModelWithActivities([a1, a2])

        vm.moveSelection(by: 1)
        #expect(vm.selectedIndex == 1)

        vm.selectedDay = .yesterday
        #expect(vm.selectedIndex == 0)
    }

    @Test("setting selectedDay clears selectedActivityId")
    @MainActor func daySwitchClearsActivityId() async {
        let a1 = TestFactories.makeActivity(id: 1)
        let (vm, _, _) = await makeViewModelWithActivities([a1])

        vm.trackSelectedId()
        #expect(vm.selectedActivityId == 1)

        vm.selectedDay = .tomorrow
        #expect(vm.selectedActivityId == nil)
    }

    // MARK: - handleKeyPress: Escape in edit/delete mode

    @Test("Escape during edit mode cancels edit and returns .handled")
    @MainActor func escapeInEditMode() async {
        let a1 = TestFactories.makeActivity(id: 1)
        let (vm, _, _) = await makeViewModelWithActivities([a1])

        vm.editingActivityId = 1
        let result = vm.handleKeyPress(key: .escape, characters: "\u{1B}", modifiers: [])
        #expect(vm.editingActivityId == nil)
        guard case .handled = result else {
            Issue.record("Expected .handled, got \(result)")
            return
        }
    }

    @Test("Escape during delete mode cancels delete and returns .handled")
    @MainActor func escapeInDeleteMode() async {
        let a1 = TestFactories.makeActivity(id: 1)
        let (vm, _, _) = await makeViewModelWithActivities([a1])

        vm.deletingActivityId = 1
        let result = vm.handleKeyPress(key: .escape, characters: "\u{1B}", modifiers: [])
        #expect(vm.deletingActivityId == nil)
        guard case .handled = result else {
            Issue.record("Expected .handled, got \(result)")
            return
        }
    }

    @Test("Non-escape key during edit mode returns .ignored")
    @MainActor func keyBlockedDuringEditMode() async {
        let a1 = TestFactories.makeActivity(id: 1)
        let (vm, _, _) = await makeViewModelWithActivities([a1])

        vm.editingActivityId = 1
        let result = vm.handleKeyPress(key: .downArrow, characters: "", modifiers: [])
        guard case .ignored = result else {
            Issue.record("Expected .ignored during edit mode, got \(result)")
            return
        }
        // editingActivityId should remain set
        #expect(vm.editingActivityId == 1)
    }

    @Test("Non-escape key during delete mode returns .ignored")
    @MainActor func keyBlockedDuringDeleteMode() async {
        let a1 = TestFactories.makeActivity(id: 1)
        let (vm, _, _) = await makeViewModelWithActivities([a1])

        vm.deletingActivityId = 1
        let result = vm.handleKeyPress(key: .tab, characters: "\t", modifiers: [])
        guard case .ignored = result else {
            Issue.record("Expected .ignored during delete mode, got \(result)")
            return
        }
        #expect(vm.deletingActivityId == 1)
    }

    // MARK: - handleKeyPress: Navigation keys

    @Test("Tab returns .switchTab")
    @MainActor func tabSwitchesTab() {
        let (vm, _, _) = makeViewModel()
        let result = vm.handleKeyPress(key: .tab, characters: "\t", modifiers: [])
        guard case .switchTab = result else {
            Issue.record("Expected .switchTab, got \(result)")
            return
        }
    }

    @Test("Down arrow moves selection down and returns .handled")
    @MainActor func downArrowMovesDown() async {
        let a1 = TestFactories.makeActivity(id: 1)
        let a2 = TestFactories.makeActivity(id: 2)
        let (vm, _, _) = await makeViewModelWithActivities([a1, a2])

        #expect(vm.selectedIndex == 0)
        let result = vm.handleKeyPress(key: .downArrow, characters: "", modifiers: [])
        #expect(vm.selectedIndex == 1)
        guard case .handled = result else {
            Issue.record("Expected .handled, got \(result)")
            return
        }
    }

    @Test("Up arrow moves selection up and returns .handled")
    @MainActor func upArrowMovesUp() async {
        let a1 = TestFactories.makeActivity(id: 1)
        let a2 = TestFactories.makeActivity(id: 2)
        let (vm, _, _) = await makeViewModelWithActivities([a1, a2])

        vm.moveSelection(by: 1) // Move to index 1 first
        let result = vm.handleKeyPress(key: .upArrow, characters: "", modifiers: [])
        #expect(vm.selectedIndex == 0)
        guard case .handled = result else {
            Issue.record("Expected .handled, got \(result)")
            return
        }
    }

    // MARK: - handleKeyPress: Day switching via arrow keys

    @Test("Left arrow on .today switches to .yesterday")
    @MainActor func leftArrowTodayToYesterday() {
        let (vm, _, _) = makeViewModel()
        #expect(vm.selectedDay == .today)
        let result = vm.handleKeyPress(key: .leftArrow, characters: "", modifiers: [])
        #expect(vm.selectedDay == .yesterday)
        guard case .handled = result else {
            Issue.record("Expected .handled, got \(result)")
            return
        }
    }

    @Test("Left arrow on .yesterday stays .yesterday")
    @MainActor func leftArrowYesterdayStays() {
        let (vm, _, _) = makeViewModel()
        vm.selectedDay = .yesterday
        let result = vm.handleKeyPress(key: .leftArrow, characters: "", modifiers: [])
        #expect(vm.selectedDay == .yesterday)
        guard case .handled = result else {
            Issue.record("Expected .handled, got \(result)")
            return
        }
    }

    @Test("Right arrow on .today switches to .tomorrow")
    @MainActor func rightArrowTodayToTomorrow() {
        let (vm, _, _) = makeViewModel()
        #expect(vm.selectedDay == .today)
        let result = vm.handleKeyPress(key: .rightArrow, characters: "", modifiers: [])
        #expect(vm.selectedDay == .tomorrow)
        guard case .handled = result else {
            Issue.record("Expected .handled, got \(result)")
            return
        }
    }

    @Test("Right arrow on .tomorrow stays .tomorrow")
    @MainActor func rightArrowTomorrowStays() {
        let (vm, _, _) = makeViewModel()
        vm.selectedDay = .tomorrow
        let result = vm.handleKeyPress(key: .rightArrow, characters: "", modifiers: [])
        #expect(vm.selectedDay == .tomorrow)
        guard case .handled = result else {
            Issue.record("Expected .handled, got \(result)")
            return
        }
    }

    @Test("Left arrow on .tomorrow switches to .today")
    @MainActor func leftArrowTomorrowToToday() {
        let (vm, _, _) = makeViewModel()
        vm.selectedDay = .tomorrow
        let result = vm.handleKeyPress(key: .leftArrow, characters: "", modifiers: [])
        #expect(vm.selectedDay == .today)
        guard case .handled = result else {
            Issue.record("Expected .handled, got \(result)")
            return
        }
    }

    @Test("Right arrow on .yesterday switches to .today")
    @MainActor func rightArrowYesterdayToToday() {
        let (vm, _, _) = makeViewModel()
        vm.selectedDay = .yesterday
        let result = vm.handleKeyPress(key: .rightArrow, characters: "", modifiers: [])
        #expect(vm.selectedDay == .today)
        guard case .handled = result else {
            Issue.record("Expected .handled, got \(result)")
            return
        }
    }

    // MARK: - handleKeyPress: Return key

    @Test("Return on .tomorrow returns .handled (noOp)")
    @MainActor func returnOnTomorrow() {
        let (vm, _, _) = makeViewModel()
        vm.selectedDay = .tomorrow
        let result = vm.handleKeyPress(key: .return, characters: "\r", modifiers: [])
        guard case .handled = result else {
            Issue.record("Expected .handled for tomorrow return, got \(result)")
            return
        }
    }

    @Test("Return on .today with idle activity returns .dismiss (continuedTimer)")
    @MainActor func returnOnTodayDismisses() async {
        let a1 = TestFactories.makeActivity(id: 1, timerStartedAt: nil)
        let (vm, _, _) = await makeViewModelWithActivities([a1])

        #expect(vm.selectedDay == .today)
        let result = vm.handleKeyPress(key: .return, characters: "\r", modifiers: [])
        // continuedTimer → PanelDismissPolicy.shouldDismiss returns true → .dismiss
        guard case .dismiss = result else {
            Issue.record("Expected .dismiss for today return with idle activity, got \(result)")
            return
        }
    }

    @Test("Return on .yesterday with activities returns .dismiss (startedTimer)")
    @MainActor func returnOnYesterdayDismisses() async {
        // Set up yesterday activities
        let calendar = Calendar.current
        let yesterdayDate = calendar.date(byAdding: .day, value: -1, to: Date())!
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let yesterday = formatter.string(from: yesterdayDate)

        let a1 = TestFactories.makeActivity(id: 1, date: yesterday, timerStartedAt: nil)

        var timerAPI = MockTimerAPI()
        // Stub createActivity for the startTimer path
        timerAPI.createActivityHandler = { _, _, _, _, _, _ in
            TestFactories.makeActivity(id: 99, timerStartedAt: "2026-04-01T10:00:00Z")
        }
        timerAPI.startTimerHandler = { _ in
            TestFactories.makeActivity(id: 99, timerStartedAt: "2026-04-01T10:00:00Z")
        }

        var activityAPI = MockActivityAPI()
        activityAPI.fetchActivitiesHandler = { from, to, _ in
            let today = DateUtilities.todayString()
            if from == today { return [] }
            return [a1]
        }

        let (vm, _, activityService) = makeViewModel(timerAPI: timerAPI, activityAPI: activityAPI)
        await activityService.refreshTodayStats()
        await activityService.refreshYesterdayActivities()

        vm.selectedDay = .yesterday
        #expect(vm.sortedActivities.count == 1)

        let result = vm.handleKeyPress(key: .return, characters: "\r", modifiers: [])
        // startedTimer → PanelDismissPolicy.shouldDismiss returns true → .dismiss
        guard case .dismiss = result else {
            Issue.record("Expected .dismiss for yesterday return, got \(result)")
            return
        }
    }

    @Test("Return with unplanned task selected returns .startEntry")
    @MainActor func returnOnUnplannedTask() async {
        let a1 = TestFactories.makeActivity(id: 1, projectId: 100, taskId: 200)

        var api = MockActivityAPI()
        api.fetchActivitiesHandler = { _, _, _ in [a1] }
        let planned = TestFactories.makePlanningEntry(id: 10, projectId: 101, taskId: 201, taskName: "Unplanned")
        api.fetchPlanningEntriesHandler = { _, _ in [planned] }

        let (vm, _, activityService) = makeViewModel(activityAPI: api)
        await activityService.refreshTodayStats()
        await activityService.refreshTodayPlanning()

        // Move to the unplanned task
        vm.moveSelection(by: 1)
        #expect(vm.isUnplannedSelected == true)

        let result = vm.handleKeyPress(key: .return, characters: "\r", modifiers: [])
        guard case .startEntry(let entry) = result else {
            Issue.record("Expected .startEntry for unplanned task, got \(result)")
            return
        }
        #expect(entry.taskId == 201)
    }

    @Test("Return on .today with running timer returns .handled (pausedTimer)")
    @MainActor func returnOnRunningTimerPauses() async {
        let running = TestFactories.makeActivity(id: 1, timerStartedAt: "2026-04-01T10:00:00Z")

        var timerAPI = MockTimerAPI()
        // fetchActivities returns the running activity so sync() sets timerState = .running
        timerAPI.fetchActivitiesHandler = { _, _, _ in [running] }
        timerAPI.stopTimerHandler = { _ in
            TestFactories.makeActivity(id: 1, timerStartedAt: nil)
        }

        let (vm, timerService, _) = await makeViewModelWithActivities([running], timerAPI: timerAPI)

        // Drive timerService into .running state via sync
        await timerService.sync()
        guard case .running(let id, _) = timerService.timerState else {
            Issue.record("Expected timer to be running after sync")
            return
        }
        #expect(id == 1)

        let result = vm.handleKeyPress(key: .return, characters: "\r", modifiers: [])
        // pausedTimer → PanelDismissPolicy.shouldDismiss returns false → .handled
        guard case .handled = result else {
            Issue.record("Expected .handled for paused timer, got \(result)")
            return
        }
    }

    // MARK: - handleKeyPress: Delete keys

    @Test("Delete key sets deletingActivityId and returns .handled")
    @MainActor func deleteKeySetsDeleting() async {
        let a1 = TestFactories.makeActivity(id: 1)
        let (vm, _, _) = await makeViewModelWithActivities([a1])

        let result = vm.handleKeyPress(key: .delete, characters: "", modifiers: [])
        #expect(vm.deletingActivityId == 1)
        guard case .handled = result else {
            Issue.record("Expected .handled, got \(result)")
            return
        }
    }

    @Test("DeleteForward key sets deletingActivityId and returns .handled")
    @MainActor func deleteForwardKeySetsDeleting() async {
        let a1 = TestFactories.makeActivity(id: 1)
        let (vm, _, _) = await makeViewModelWithActivities([a1])

        let result = vm.handleKeyPress(key: .deleteForward, characters: "", modifiers: [])
        #expect(vm.deletingActivityId == 1)
        guard case .handled = result else {
            Issue.record("Expected .handled, got \(result)")
            return
        }
    }

    // MARK: - handleKeyPress: ⌘-number shortcuts

    @Test("⌘1 with activities returns .dismiss (continuedTimer)")
    @MainActor func commandNumberShortcut() async {
        let a1 = TestFactories.makeActivity(id: 1, timerStartedAt: nil)
        let a2 = TestFactories.makeActivity(id: 2, timerStartedAt: nil)
        let (vm, _, _) = await makeViewModelWithActivities([a1, a2])

        // ⌘1 = shortcut index 0 → first activity → continuedTimer → dismiss
        let result = vm.handleKeyPress(key: KeyEquivalent("1"), characters: "1", modifiers: .command)
        guard case .dismiss = result else {
            Issue.record("Expected .dismiss for ⌘1, got \(result)")
            return
        }
    }

    @Test("⌘-number with unplanned task returns .startEntry")
    @MainActor func commandNumberUnplanned() async {
        // Set up: 1 activity + 1 unplanned task. ⌘1 should target the activity (shortcut 0).
        // Need an index where unplanned is reached. With 1 activity, shortcut 1 → mapped index 1 → unplanned.
        let a1 = TestFactories.makeActivity(id: 1, projectId: 100, taskId: 200)

        var api = MockActivityAPI()
        api.fetchActivitiesHandler = { _, _, _ in [a1] }
        let planned = TestFactories.makePlanningEntry(id: 10, projectId: 101, taskId: 201, taskName: "Unplanned")
        api.fetchPlanningEntriesHandler = { _, _ in [planned] }

        let (vm, _, activityService) = makeViewModel(activityAPI: api)
        await activityService.refreshTodayStats()
        await activityService.refreshTodayPlanning()

        // ⌘2 = shortcut index 1 → selectByShortcut(1) → mapped index 1 → unplanned task
        let result = vm.handleKeyPress(key: KeyEquivalent("2"), characters: "2", modifiers: .command)
        // selectByShortcut for index 1 with 1 activity → index 1 → isUnplannedSelected → startEntry
        guard case .startEntry(let entry) = result else {
            Issue.record("Expected .startEntry for ⌘2 hitting unplanned, got \(result)")
            return
        }
        #expect(entry.taskId == 201)
    }

    // MARK: - handleKeyPress: Single-char shortcuts

    @Test("'e' with valid activity returns .startEdit with description and hours")
    @MainActor func eKeyStartsEdit() async {
        let a1 = TestFactories.makeActivity(id: 1, hours: 2.5, description: "My work")
        let (vm, _, _) = await makeViewModelWithActivities([a1])

        let result = vm.handleKeyPress(key: KeyEquivalent("e"), characters: "e", modifiers: [])
        guard case .startEdit(let description, let hours) = result else {
            Issue.record("Expected .startEdit, got \(result)")
            return
        }
        #expect(description == "My work")
        #expect(hours == "2.50")
    }

    @Test("'e' with no activities returns .handled")
    @MainActor func eKeyNoActivities() {
        let (vm, _, _) = makeViewModel()
        let result = vm.handleKeyPress(key: KeyEquivalent("e"), characters: "e", modifiers: [])
        guard case .handled = result else {
            Issue.record("Expected .handled for 'e' with no activities, got \(result)")
            return
        }
    }

    @Test("'d' sets deletingActivityId and returns .handled")
    @MainActor func dKeyStartsDelete() async {
        let a1 = TestFactories.makeActivity(id: 1)
        let (vm, _, _) = await makeViewModelWithActivities([a1])

        let result = vm.handleKeyPress(key: KeyEquivalent("d"), characters: "d", modifiers: [])
        #expect(vm.deletingActivityId == 1)
        guard case .handled = result else {
            Issue.record("Expected .handled, got \(result)")
            return
        }
    }

    @Test("'f' toggles favorite and returns .handled")
    @MainActor func fKeyTogglesFavorite() async {
        let a1 = TestFactories.makeActivity(id: 1, projectId: 100, projectName: "Proj",
                                             taskId: 200, taskName: "Task",
                                             customerName: "Cust")
        let (vm, _, _) = await makeViewModelWithActivities([a1])

        let result = vm.handleKeyPress(key: KeyEquivalent("f"), characters: "f", modifiers: [])
        guard case .handled = result else {
            Issue.record("Expected .handled, got \(result)")
            return
        }
        // Verify the favorite was actually toggled
        #expect(vm.favoritesManager.isFavorite(projectId: 100, taskId: 200))
    }

    // MARK: - handleKeyPress: Type-to-search and unhandled

    @Test("Printable char with no modifiers returns .typeToSearch")
    @MainActor func printableCharTypeToSearch() {
        let (vm, _, _) = makeViewModel()
        let result = vm.handleKeyPress(key: KeyEquivalent("x"), characters: "x", modifiers: [])
        guard case .typeToSearch(let chars) = result else {
            Issue.record("Expected .typeToSearch, got \(result)")
            return
        }
        #expect(chars == "x")
    }

    @Test("Printable char with shift returns .typeToSearch")
    @MainActor func shiftCharTypeToSearch() {
        let (vm, _, _) = makeViewModel()
        let result = vm.handleKeyPress(key: KeyEquivalent("A"), characters: "A", modifiers: .shift)
        guard case .typeToSearch(let chars) = result else {
            Issue.record("Expected .typeToSearch for shifted char, got \(result)")
            return
        }
        #expect(chars == "A")
    }

    @Test("Modifier key combo (⌘+non-number) returns .ignored")
    @MainActor func modifierComboIgnored() {
        let (vm, _, _) = makeViewModel()
        let result = vm.handleKeyPress(key: KeyEquivalent("z"), characters: "z", modifiers: .command)
        guard case .ignored = result else {
            Issue.record("Expected .ignored for ⌘Z, got \(result)")
            return
        }
    }

    @Test("Number char with no modifiers returns .typeToSearch (not ⌘-shortcut)")
    @MainActor func numberCharTypeToSearch() {
        let (vm, _, _) = makeViewModel()
        let result = vm.handleKeyPress(key: KeyEquivalent("5"), characters: "5", modifiers: [])
        guard case .typeToSearch(let chars) = result else {
            Issue.record("Expected .typeToSearch for digit without ⌘, got \(result)")
            return
        }
        #expect(chars == "5")
    }

    // MARK: - performEntryAction: Today with idle timer

    @Test("performEntryAction on today with idle timer returns .continuedTimer")
    @MainActor func performEntryActionTodayIdle() async {
        let a1 = TestFactories.makeActivity(id: 1, timerStartedAt: nil)
        let (vm, _, _) = await makeViewModelWithActivities([a1])

        let result = vm.performEntryAction()
        guard case .continuedTimer(let activityId, _) = result else {
            Issue.record("Expected .continuedTimer, got \(result)")
            return
        }
        #expect(activityId == 1)
    }

    // MARK: - performEntryAction: Today with running timer on selected activity

    @Test("performEntryAction on today with running timer returns .pausedTimer")
    @MainActor func performEntryActionTodayRunning() async {
        let running = TestFactories.makeActivity(id: 1, timerStartedAt: "2026-04-01T10:00:00Z")

        var timerAPI = MockTimerAPI()
        timerAPI.fetchActivitiesHandler = { _, _, _ in [running] }
        timerAPI.stopTimerHandler = { _ in
            TestFactories.makeActivity(id: 1, timerStartedAt: nil)
        }

        let (vm, timerService, _) = await makeViewModelWithActivities([running], timerAPI: timerAPI)
        await timerService.sync()

        // Verify timer is running on activity 1
        guard case .running(let runId, _) = timerService.timerState else {
            Issue.record("Expected timer running after sync")
            return
        }
        #expect(runId == 1)

        let result = vm.performEntryAction()
        guard case .pausedTimer = result else {
            Issue.record("Expected .pausedTimer, got \(result)")
            return
        }
    }

    // MARK: - performEntryAction: Today with paused timer on selected activity

    @Test("performEntryAction on today with paused timer returns .resumedTimer")
    @MainActor func performEntryActionTodayPaused() async {
        let running = TestFactories.makeActivity(id: 1, projectName: "MyProj", timerStartedAt: "2026-04-01T10:00:00Z")

        var timerAPI = MockTimerAPI()
        timerAPI.fetchActivitiesHandler = { _, _, _ in [running] }
        timerAPI.stopTimerHandler = { _ in
            TestFactories.makeActivity(id: 1, projectName: "MyProj", timerStartedAt: nil)
        }

        let (vm, timerService, _) = await makeViewModelWithActivities([running], timerAPI: timerAPI)

        // Drive to running, then pause to get paused state
        await timerService.sync()
        guard case .running = timerService.timerState else {
            Issue.record("Expected running after sync")
            return
        }
        await timerService.pauseTimer()
        guard case .paused(let pausedId, _) = timerService.timerState else {
            Issue.record("Expected paused after pauseTimer")
            return
        }
        #expect(pausedId == 1)

        let result = vm.performEntryAction()
        guard case .resumedTimer(let activityId, let projectName) = result else {
            Issue.record("Expected .resumedTimer, got \(result)")
            return
        }
        #expect(activityId == 1)
        #expect(projectName == "MyProj")
    }

    // MARK: - performEntryAction: Yesterday

    @Test("performEntryAction on yesterday returns .startedTimer")
    @MainActor func performEntryActionYesterday() async {
        let calendar = Calendar.current
        let yesterdayDate = calendar.date(byAdding: .day, value: -1, to: Date())!
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let yesterday = formatter.string(from: yesterdayDate)

        let a1 = TestFactories.makeActivity(id: 1, date: yesterday, projectId: 100, taskId: 200, description: "Yesterday work", timerStartedAt: nil)

        var timerAPI = MockTimerAPI()
        timerAPI.createActivityHandler = { _, _, _, _, _, _ in
            TestFactories.makeActivity(id: 99, timerStartedAt: "2026-04-01T10:00:00Z")
        }
        timerAPI.startTimerHandler = { _ in
            TestFactories.makeActivity(id: 99, timerStartedAt: "2026-04-01T10:00:00Z")
        }

        var activityAPI = MockActivityAPI()
        activityAPI.fetchActivitiesHandler = { from, to, _ in
            let today = DateUtilities.todayString()
            if from == today { return [] }
            return [a1]
        }

        let (vm, _, activityService) = makeViewModel(timerAPI: timerAPI, activityAPI: activityAPI)
        await activityService.refreshTodayStats()
        await activityService.refreshYesterdayActivities()

        vm.selectedDay = .yesterday
        #expect(vm.sortedActivities.count == 1)

        let result = vm.performEntryAction()
        guard case .startedTimer(let projId, let taskId, let desc) = result else {
            Issue.record("Expected .startedTimer, got \(result)")
            return
        }
        #expect(projId == 100)
        #expect(taskId == 200)
        #expect(desc == "Yesterday work")
    }

    // MARK: - performEntryAction: Tomorrow

    @Test("performEntryAction on tomorrow returns .noOp")
    @MainActor func performEntryActionTomorrow() {
        let (vm, _, _) = makeViewModel()
        vm.selectedDay = .tomorrow
        let result = vm.performEntryAction()
        guard case .noOp = result else {
            Issue.record("Expected .noOp, got \(result)")
            return
        }
    }

    // MARK: - performEntryAction: Unplanned task

    @Test("performEntryAction with unplanned task returns .selectedPlannedEntry")
    @MainActor func performEntryActionUnplanned() async {
        let a1 = TestFactories.makeActivity(id: 1, projectId: 100, taskId: 200)

        var api = MockActivityAPI()
        api.fetchActivitiesHandler = { _, _, _ in [a1] }
        let planned = TestFactories.makePlanningEntry(id: 10, projectId: 101, taskId: 201, taskName: "Unplanned Task")
        api.fetchPlanningEntriesHandler = { _, _ in [planned] }

        let (vm, _, activityService) = makeViewModel(activityAPI: api)
        await activityService.refreshTodayStats()
        await activityService.refreshTodayPlanning()

        // Move selection to unplanned task
        vm.moveSelection(by: 1)
        #expect(vm.isUnplannedSelected == true)

        let result = vm.performEntryAction()
        guard case .selectedPlannedEntry(let entry) = result else {
            Issue.record("Expected .selectedPlannedEntry, got \(result)")
            return
        }
        #expect(entry.taskId == 201)
        #expect(entry.taskName == "Unplanned Task")
    }

    // MARK: - startEditingSelected / startDeletingSelected guards

    @Test("startEditingSelected on tomorrow does nothing")
    @MainActor func startEditingTomorrowGuard() {
        let (vm, _, _) = makeViewModel()
        vm.selectedDay = .tomorrow
        vm.startEditingSelected()
        #expect(vm.editingActivityId == nil)
    }

    @Test("startEditingSelected with valid index sets editingActivityId")
    @MainActor func startEditingValidIndex() async {
        let a1 = TestFactories.makeActivity(id: 42)
        let (vm, _, _) = await makeViewModelWithActivities([a1])

        vm.startEditingSelected()
        #expect(vm.editingActivityId == 42)
    }

    @Test("startDeletingSelected on tomorrow does nothing")
    @MainActor func startDeletingTomorrowGuard() {
        let (vm, _, _) = makeViewModel()
        vm.selectedDay = .tomorrow
        vm.startDeletingSelected()
        #expect(vm.deletingActivityId == nil)
    }

    @Test("startDeletingSelected with valid index sets deletingActivityId")
    @MainActor func startDeletingValidIndex() async {
        let a1 = TestFactories.makeActivity(id: 77)
        let (vm, _, _) = await makeViewModelWithActivities([a1])

        vm.startDeletingSelected()
        #expect(vm.deletingActivityId == 77)
    }

    // MARK: - editPayload

    @Test("editPayload returns description and formatted hours for valid index")
    @MainActor func editPayloadValid() async {
        let a1 = TestFactories.makeActivity(id: 1, hours: 3.75, description: "Design review")
        let (vm, _, _) = await makeViewModelWithActivities([a1])

        let payload = vm.editPayload()
        #expect(payload != nil)
        #expect(payload?.description == "Design review")
        #expect(payload?.hours == "3.75")
    }

    @Test("editPayload returns nil when no activities exist")
    @MainActor func editPayloadInvalid() {
        let (vm, _, _) = makeViewModel()
        let payload = vm.editPayload()
        #expect(payload == nil)
    }

    // MARK: - favoriteSelected

    @Test("favoriteSelected toggles favorite for the selected activity")
    @MainActor func favoriteSelectedToggle() async {
        let a1 = TestFactories.makeActivity(id: 1, projectId: 100, projectName: "Proj",
                                             taskId: 200, taskName: "Task",
                                             customerName: "Cust")
        let (vm, _, _) = await makeViewModelWithActivities([a1])

        // Not a favorite initially
        #expect(!vm.favoritesManager.isFavorite(projectId: 100, taskId: 200))

        vm.favoriteSelected()

        // Now it's a favorite
        #expect(vm.favoritesManager.isFavorite(projectId: 100, taskId: 200))

        // Toggle again to remove
        vm.favoriteSelected()
        #expect(!vm.favoritesManager.isFavorite(projectId: 100, taskId: 200))
    }
}
