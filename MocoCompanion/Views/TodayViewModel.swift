import Foundation
import SwiftUI

/// Extracted business logic for the Today/Yesterday/Tomorrow views.
/// Owns navigation state, action decisions, and timer dispatch.
/// TodayView binds to this and handles only rendering + focus.
@Observable
@MainActor
final class TodayViewModel {
    // MARK: - Dependencies

    let timerService: TimerService
    let activityService: ActivityService
    let favoritesManager: FavoritesManager

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

    init(timerService: TimerService, activityService: ActivityService, favoritesManager: FavoritesManager) {
        self.timerService = timerService
        self.activityService = activityService
        self.favoritesManager = favoritesManager
    }

    // MARK: - Derived State

    var isYesterday: Bool { selectedDay == .yesterday }
    var isTomorrow: Bool { selectedDay == .tomorrow }

    var sortedActivities: [MocoActivity] {
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
        if selectedDay == .today { return base + activityService.unplannedTasks.count }
        return base
    }

    /// Whether the selected index points to an unplanned task.
    var isUnplannedSelected: Bool {
        selectedDay == .today && selectedIndex >= sortedActivities.count && selectedIndex < totalNavigableCount
    }

    /// The unplanned task at the current selection, if any.
    var selectedUnplannedTask: ActivityService.UnplannedTask? {
        guard isUnplannedSelected else { return nil }
        let offset = selectedIndex - sortedActivities.count
        let tasks = activityService.unplannedTasks
        guard tasks.indices.contains(offset) else { return nil }
        return tasks[offset]
    }

    // MARK: - Navigation

    func moveSelection(by delta: Int) {
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
        if sortedActivities.indices.contains(mapped) {
            selectedIndex = mapped
            trackSelectedId()
        }
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

    // MARK: - Actions (return what happened, let the View handle dismiss)

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
            // Yesterday: start a new timer with the same project/task/description
            Task {
                _ = await timerService.startTimer(
                    projectId: activity.project.id,
                    taskId: activity.task.id,
                    description: activity.description
                )
            }
            return .startedTimer(projectId: activity.project.id, taskId: activity.task.id, description: activity.description)
        }

        // Today: context-aware toggle
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
        editingActivityId = sortedActivities[selectedIndex].id
    }

    func startDeletingSelected() {
        guard !isTomorrow else { return }
        guard sortedActivities.indices.contains(selectedIndex) else { return }
        deletingActivityId = sortedActivities[selectedIndex].id
    }

    func favoriteSelected() {
        guard sortedActivities.indices.contains(selectedIndex) else { return }
        let activity = sortedActivities[selectedIndex]
        let entry = SearchEntry(
            projectId: activity.project.id,
            taskId: activity.task.id,
            customerName: activity.customer.name,
            projectName: activity.project.name,
            taskName: activity.task.name
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

    private func toggleTimerForActivity(_ activity: MocoActivity) -> TimerActionResult {
        // Determine what toggleTimer will do
        switch timerService.timerState {
        case .running(let runningId, _) where runningId == activity.id:
            Task { await timerService.pauseTimer() }
            return .pausedTimer

        case .paused(let pausedId, let projectName) where pausedId == activity.id:
            Task { await timerService.resumeTimer() }
            return .resumedTimer(activityId: pausedId, projectName: projectName)

        default:
            Task {
                await timerService.toggleTimer(for: activity.id, projectName: activity.project.name)
            }
            return .continuedTimer(activityId: activity.id, projectName: activity.project.name)
        }
    }

    // MARK: - Keyboard Dispatch

    /// Result of keyboard dispatch — the view maps these to SwiftUI actions.
    enum KeyAction {
        /// Key was handled, no view-layer action needed.
        case handled
        /// Key was not handled — let SwiftUI propagate it.
        case ignored
        /// Switch to the Track tab.
        case switchTab
        /// Start tracking a planned entry — view should switch to Track tab with entry.
        case startEntry(SearchEntry)
        /// Dismiss the panel.
        case dismiss
        /// Start editing the selected entry — view provides the drafts.
        case startEdit(description: String, hours: String)
        /// Forward typed characters to search.
        case typeToSearch(String)
    }

    /// Unified keyboard dispatch. Replaces 12 individual onKeyPress handlers in the view.
    /// Returns a KeyAction that the view maps to SwiftUI side effects.
    func handleKeyPress(key: KeyEquivalent, characters: String, modifiers: NSEvent.ModifierFlags) -> KeyAction {
        // Handle Escape during edit/delete mode — cancel without closing panel
        if editingActivityId != nil && key == .escape {
            editingActivityId = nil
            return .handled
        }
        if deletingActivityId != nil && key == .escape {
            deletingActivityId = nil
            return .handled
        }

        // Block all other keys during edit/delete mode
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

        // ⌘1–⌘9 shortcuts
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

        // Single character shortcuts
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

        // Type-to-search: forward printable characters
        if modifiers.isEmpty || modifiers == .shift,
           let char = characters.first, char.isLetter || char.isNumber {
            return .typeToSearch(characters)
        }

        return .ignored
    }
}
