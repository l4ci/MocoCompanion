import Foundation

/// Timer lifecycle states — extracted as a standalone type for testability.
/// Used by TimerService, MenuBarDisplayState, StatusItemController, and views.
enum TimerState: Equatable, Sendable {
    case idle
    case running(activityId: Int, projectName: String)
    case paused(activityId: Int, projectName: String)
}
