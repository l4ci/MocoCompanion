import Foundation

/// Declares the ability to stop a timer for a given activity.
/// TimerService conforms; DeleteUndoManager depends on this protocol
/// instead of a concrete TimerService reference.
@MainActor
protocol TimerStopProvider: AnyObject {
    func stopTimerIfActive(activityId: Int) async
}
