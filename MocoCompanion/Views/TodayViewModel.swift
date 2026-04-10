import Foundation
import SwiftUI

/// Extracted business logic for the Today/Yesterday/Tomorrow views.
/// Owns navigation state, action decisions, and timer dispatch.
/// TodayView binds to this and handles only rendering + focus.
///
/// Services are internal — the view accesses state through ViewModel-level
/// computed properties. Only `activityService`, `timerService`, and
/// `deleteUndoManager` remain accessible for subview injection where
/// @Observable reactivity on the concrete type is required.
@Observable
@MainActor
final class TodayViewModel {
    // MARK: - Dependencies
    // These are intentionally internal, not private, because TodayView passes
    // them to subviews (TodayActivityRow, UnplannedTasksSection) that need
    // @Observable reactivity on the concrete types.

    let activityService: ActivityService
    let timerService: TimerService
    let deleteUndoManager: DeleteUndoManager
    let planningStore: PlanningStore
    let favoritesManager: FavoritesManager
    var syncState: SyncState?

    // MARK: - Navigation State

    var selectedDay: DaySelection = .today {
        didSet {
            selectedIndex = 0
            selectedActivityId = nil
        }
    }
    var selectedIndex = 0
    var selectedActivityId: Int?
    var hoveredActivityId: Int?
    var editingActivityId: Int?
    var deletingActivityId: Int?

    /// Bumped on data changes to force SwiftUI re-render even when selectedIndex
    /// doesn't change (e.g., deleting the last item clamps to the same index).
    var dataVersion = 0

    /// When the last successful data sync completed. Drives the "Xm ago" label.
    /// Prefers SyncState (shadow DB) when available, falls back to local timestamp.
    var lastSyncedAt: Date? {
        get { syncState?.lastSyncedAt ?? _lastSyncedAt }
        set { _lastSyncedAt = newValue }
    }
    private var _lastSyncedAt: Date?

    /// Whether a manual refresh is in progress.
    var isRefreshing = false

    init(
        timerService: TimerService,
        activityService: ActivityService,
        planningStore: PlanningStore,
        deleteUndoManager: DeleteUndoManager,
        favoritesManager: FavoritesManager
    ) {
        self.timerService = timerService
        self.activityService = activityService
        self.planningStore = planningStore
        self.deleteUndoManager = deleteUndoManager
        self.favoritesManager = favoritesManager
    }

    // MARK: - Data Refresh

    /// Refresh data for the currently selected day. Updates lastSyncedAt on completion.
    func refreshCurrentDay() async {
        isRefreshing = true
        switch selectedDay {
        case .today:
            await activityService.refreshTodayStats()
            await planningStore.refreshAllPlanning()
        case .yesterday:
            await activityService.refreshYesterdayActivities()
        case .tomorrow:
            await planningStore.refreshAllPlanning()
        }
        lastSyncedAt = Date()
        isRefreshing = false
    }

    func refreshTodayStats() async {
        await activityService.refreshTodayStats()
    }

    func refreshYesterdayActivities() async {
        await activityService.refreshYesterdayActivities()
    }

    func refreshAllPlanning() async {
        await planningStore.refreshAllPlanning()
    }

    func refreshAbsences() async {
        await planningStore.refreshAbsences()
    }

    // MARK: - Forwarded State (ActivityService)

    /// Opaque version token — changes whenever todayActivities changes.
    /// Lets the view observe activity list changes through the ViewModel boundary
    /// without exposing activityService directly.
    var todayActivitiesVersion: Int { activityService.todayActivities.count ^ (activityService.todayActivities.first?.id ?? 0) }

    /// Opaque version token for yesterdayActivities.
    var yesterdayActivitiesVersion: Int { activityService.yesterdayActivities.count ^ (activityService.yesterdayActivities.first?.id ?? 0) }

    /// Today's total tracked hours.
    var todayTotalHours: Double { activityService.todayTotalHours }

    /// Today's billable percentage (0–100).
    var todayBillablePercentage: Double { activityService.todayBillablePercentage }

    /// Yesterday's activities — used by stats footer when isYesterday is true.
    var yesterdayActivities: [ShadowEntry] { activityService.yesterdayActivities }

    // MARK: - Forwarded State (DeleteUndoManager)

    /// The currently pending delete, if any. Drives the undo toast.
    var pendingDelete: DeleteUndoManager.PendingDelete? { deleteUndoManager.pendingDelete }

    func undoDelete() {
        deleteUndoManager.undoDelete()
    }

    // MARK: - Forwarded State (PlanningStore)

    /// Absence (if any) for a specific date string.
    func absence(for dateString: String) -> MocoSchedule? {
        planningStore.absence(for: dateString)
    }

    /// Unplanned tasks for today.
    var unplannedTasks: [PlanningStore.UnplannedTask] { planningStore.unplannedTasks }

    /// Tomorrow's planning entries.
    var tomorrowPlanningEntries: [MocoPlanningEntry] { planningStore.tomorrowPlanningEntries }

    /// Planned hours for a project+task today, or nil if not planned.
    func plannedHours(projectId: Int, taskId: Int) -> Double? {
        planningStore.plannedHours(projectId: projectId, taskId: taskId)
    }

    // MARK: - Forwarded State (TimerService)

    /// Whether the given activity is currently paused.
    func isPausedActivity(_ activity: ShadowEntry) -> Bool {
        timerService.isPausedActivity(activity)
    }

    // MARK: - Derived State

    var isYesterday: Bool { selectedDay == .yesterday }
    var isTomorrow: Bool { selectedDay == .tomorrow }

    var sortedActivities: [ShadowEntry] {
        switch selectedDay {
        case .today:
            return activityService.sortedTodayActivities
        case .yesterday:
            let activeId = timerService.activeActivityId
            return activityService.sortedYesterdayActivities.filter { activity in
                if activity.isTimerRunning { return false }
                if let activeId, activity.id == activeId { return false }
                return true
            }
        case .tomorrow:
            return []
        }
    }

    var activeEntryIndex: Int? {
        guard selectedDay == .today else { return nil }
        return sortedActivities.firstIndex { $0.isTimerRunning || timerService.isPausedActivity($0) }
    }

    /// Total navigable items (tracked + unplanned on today).
    var totalNavigableCount: Int {
        let base = sortedActivities.count
        if selectedDay == .today { return base + planningStore.unplannedTasks.count }
        return base
    }

    /// Whether the selected index points to an unplanned task.
    var isUnplannedSelected: Bool {
        selectedDay == .today && selectedIndex >= sortedActivities.count && selectedIndex < totalNavigableCount
    }

    /// The unplanned task at the current selection, if any.
    var selectedUnplannedTask: PlanningStore.UnplannedTask? {
        guard isUnplannedSelected else { return nil }
        let offset = selectedIndex - sortedActivities.count
        let tasks = planningStore.unplannedTasks
        guard tasks.indices.contains(offset) else { return nil }
        return tasks[offset]
    }

    // MARK: - Navigation

    func moveSelection(by delta: Int) {
        // If the mouse was hovering a row, snap selection there first
        // so keyboard navigation continues from where the mouse was.
        if let hoverId = hoveredActivityId,
           let hoverIdx = sortedActivities.firstIndex(where: { $0.id == hoverId }) {
            selectedIndex = hoverIdx
            hoveredActivityId = nil
        }

        let count = totalNavigableCount
        guard count > 0 else { return }
        selectedIndex = max(0, min(count - 1, selectedIndex + delta))
        trackSelectedId()
    }

    func selectByShortcut(_ shortcut: Int) {
        let activeIdx = activeEntryIndex ?? -1
        var mapped = shortcut
        if activeIdx >= 0 && mapped >= activeIdx {
            mapped += 1
        }
        guard mapped >= 0 && mapped < totalNavigableCount else { return }
        selectedIndex = mapped
        trackSelectedId()
    }

    func shortcutIndex(for listIndex: Int) -> Int {
        if listIndex == activeEntryIndex { return -1 }
        let activeIdx = activeEntryIndex ?? -1
        if activeIdx < 0 { return listIndex }
        return listIndex > activeIdx ? listIndex - 1 : listIndex
    }

    func syncSelectionAfterDataChange() {
        // Clear hover state — the hovered entry may have been deleted
        hoveredActivityId = nil
        // Bump version to force re-render even if selectedIndex stays the same
        dataVersion &+= 1

        if let targetId = selectedActivityId,
           let newIndex = sortedActivities.firstIndex(where: { $0.id == targetId }) {
            selectedIndex = newIndex
        } else {
            // Selected entry was deleted or not found — clamp and update
            selectedIndex = max(0, min(selectedIndex, sortedActivities.count - 1))
            trackSelectedId()
        }
    }

    func trackSelectedId() {
        if sortedActivities.indices.contains(selectedIndex) {
            selectedActivityId = sortedActivities[selectedIndex].id
        }
    }

    // MARK: - Actions

    /// Primary Enter action — unified logic for all days and selection types.
    /// Returns the action result so the caller can decide on panel dismiss.
    func performEntryAction() -> TimerActionResult {
        guard !isTomorrow else { return .noOp }

        // Unplanned task → switch to Track tab with entry pre-selected for description
        if let task = selectedUnplannedTask {
            let entry = SearchEntry(
                projectId: task.projectId,
                taskId: task.taskId,
                customerName: task.customerName,
                projectName: task.projectName,
                taskName: task.taskName
            )
            return .selectedPlannedEntry(entry)
        }

        guard sortedActivities.indices.contains(selectedIndex) else { return .noOp }
        let activity = sortedActivities[selectedIndex]
        selectedActivityId = activity.id

        if isYesterday {
            Task {
                _ = await timerService.startTimer(
                    projectId: activity.projectId,
                    taskId: activity.taskId,
                    description: activity.description
                )
            }
            return .startedTimer(projectId: activity.projectId, taskId: activity.taskId, description: activity.description)
        }

        return toggleTimerForActivity(activity)
    }

    /// ⌘+Zahl shortcut action — select by shortcut index, then perform tracking action.
    func performShortcutAction(_ shortcut: Int) -> TimerActionResult {
        selectByShortcut(shortcut)
        return performEntryAction()
    }

    func startEditingSelected() {
        guard !isTomorrow else { return }
        guard sortedActivities.indices.contains(selectedIndex) else { return }
        let activity = sortedActivities[selectedIndex]
        guard !activity.isReadOnly else { return }
        editingActivityId = activity.id
    }

    func startDeletingSelected() {
        guard !isTomorrow else { return }
        guard sortedActivities.indices.contains(selectedIndex) else { return }
        let activity = sortedActivities[selectedIndex]
        guard !activity.isReadOnly else { return }
        deletingActivityId = activity.id
    }

    func favoriteSelected() {
        guard sortedActivities.indices.contains(selectedIndex) else { return }
        let activity = sortedActivities[selectedIndex]
        let entry = SearchEntry(
            projectId: activity.projectId,
            taskId: activity.taskId,
            customerName: activity.customerName,
            projectName: activity.projectName,
            taskName: activity.taskName
        )
        favoritesManager.toggle(entry)
    }

    /// Edit payload for the selected activity (description + hours draft).
    func editPayload() -> (description: String, hours: String)? {
        guard sortedActivities.indices.contains(selectedIndex) else { return nil }
        let activity = sortedActivities[selectedIndex]
        return (activity.description, String(format: "%.2f", activity.hours))
    }

    // MARK: - Private

    private func toggleTimerForActivity(_ activity: ShadowEntry) -> TimerActionResult {
        switch timerService.timerState {
        case .running(let runningId, _) where runningId == activity.id:
            Task { await timerService.pauseTimer() }
            return .pausedTimer

        case .paused(let pausedId, let projectName) where pausedId == activity.id:
            Task { await timerService.resumeTimer() }
            return .resumedTimer(activityId: pausedId, projectName: projectName)

        default:
            guard let activityId = activity.id else { return .noOp }
            Task {
                await timerService.toggleTimer(for: activityId, projectName: activity.projectName)
            }
            return .continuedTimer(activityId: activityId, projectName: activity.projectName)
        }
    }

    // MARK: - Keyboard Dispatch

    enum KeyAction {
        case handled
        case ignored
        case switchTab
        case startEntry(SearchEntry)
        case dismiss
        case startEdit(description: String, hours: String)
        case typeToSearch(String)
    }

    func handleKeyPress(key: KeyEquivalent, characters: String, modifiers: NSEvent.ModifierFlags) -> KeyAction {
        if editingActivityId != nil && key == .escape {
            editingActivityId = nil
            return .handled
        }
        if deletingActivityId != nil && key == .escape {
            deletingActivityId = nil
            return .handled
        }

        guard editingActivityId == nil && deletingActivityId == nil else { return .ignored }

        switch key {
        case .tab:
            return .switchTab

        case .downArrow:
            moveSelection(by: 1)
            return .handled

        case .upArrow:
            moveSelection(by: -1)
            return .handled

        case .leftArrow:
            switch selectedDay {
            case .tomorrow: selectedDay = .today
            case .today: selectedDay = .yesterday
            case .yesterday: break
            }
            return .handled

        case .rightArrow:
            switch selectedDay {
            case .yesterday: selectedDay = .today
            case .today: selectedDay = .tomorrow
            case .tomorrow: break
            }
            return .handled

        case .return:
            let result = performEntryAction()
            if case .selectedPlannedEntry(let entry) = result {
                return .startEntry(entry)
            }
            if PanelDismissPolicy.shouldDismiss(after: result) {
                return .dismiss
            }
            return .handled

        case .delete, .deleteForward:
            startDeletingSelected()
            return .handled

        default:
            break
        }

        if modifiers == .command, let char = characters.first,
           let num = Int(String(char)), num >= 1 && num <= 9 {
            let result = performShortcutAction(num - 1)
            if case .selectedPlannedEntry(let entry) = result {
                return .startEntry(entry)
            }
            if PanelDismissPolicy.shouldDismiss(after: result) {
                return .dismiss
            }
            return .handled
        }

        let lower = characters.lowercased()
        if lower == "e" {
            if let payload = editPayload() {
                return .startEdit(description: payload.description, hours: payload.hours)
            }
            return .handled
        }
        if lower == "d" {
            startDeletingSelected()
            return .handled
        }
        if lower == "f" {
            favoriteSelected()
            return .handled
        }

        if modifiers.isEmpty || modifiers == .shift,
           let char = characters.first, char.isLetter || char.isNumber {
            return .typeToSearch(characters)
        }

        return .ignored
    }
}
