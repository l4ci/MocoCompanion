import Foundation

/// Determines whether the panel should close after a timer action.
/// Single source of truth — replaces 6+ scattered `NSApp.keyWindow?.close()` decisions.
enum PanelDismissPolicy {
    /// Determine whether the panel should dismiss after a timer action.
    /// - Parameters:
    ///   - action: The timer action that was just dispatched.
    ///   - day: Which day tab is active.
    /// - Returns: `true` if the panel should close.
    static func shouldDismiss(after action: TimerActionResult) -> Bool {
        switch action {
        case .startedTimer, .continuedTimer, .resumedTimer:
            return true
        case .pausedTimer:
            return false
        case .selectedPlannedEntry:
            return false  // Don't dismiss — switching to Track tab
        case .startedEditing, .noOp:
            return false
        }
    }
}

/// The result of a user action on an entry in the Today/Yesterday view.
enum TimerActionResult {
    /// A new timer was started (from yesterday replay, unplanned task, or idle entry).
    case startedTimer(projectId: Int, taskId: Int, description: String)
    /// An existing timer was continued (entry was not running/paused).
    case continuedTimer(activityId: Int, projectName: String)
    /// The running timer was paused.
    case pausedTimer
    /// A paused timer was resumed.
    case resumedTimer(activityId: Int, projectName: String)
    /// Entered edit mode (no timer change).
    case startedEditing
    /// A planned (but not yet tracked) task was selected for tracking.
    case selectedPlannedEntry(SearchEntry)
    /// Nothing happened (e.g., tomorrow is read-only, invalid selection).
    case noOp
}
