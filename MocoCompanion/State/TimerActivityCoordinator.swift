import Foundation

/// Handles operations that cross the timer/activity boundary.
/// Eliminates the circular dependency between TimerService and ActivityService:
/// - TimerService no longer holds a mutable `activityService` reference
/// - ActivityService no longer takes a `stopTimerIfActive` closure
///
/// Both services push events through closures set by the coordinator.
@MainActor
final class TimerActivityCoordinator {

    let timer: TimerService
    let activities: ActivityService

    init(timer: TimerService, activities: ActivityService) {
        self.timer = timer
        self.activities = activities

        // Wire timer → activity: push updated activities to the activity list
        timer.onActivityChanged = { [weak activities] activity in
            activities?.upsertActivity(activity)
        }

        // Wire timer → activity: refresh today stats after sync (reuse already-fetched activities)
        timer.onSyncCompleted = { [weak activities] fetchedActivities in
            guard let activityService = activities else { return }
            if let fetched = fetchedActivities {
                activityService.applyFetchedTodayActivities(fetched)
            } else {
                await activityService.refreshTodayStats()
            }
        }

        // Wire activity → timer: stop timer before deleting a timed activity
        activities.onNeedTimerStop = { [weak timer] activityId in
            guard let timer else { return }
            switch timer.timerState {
            case .running(let id, _) where id == activityId,
                 .paused(let id, _) where id == activityId:
                await timer.stopTimer()
            default: break
            }
        }
    }
}
