import Foundation
import os

/// Monitors budget thresholds while a timer is running.
///
/// Polls `BudgetService` every 60 seconds during active tracking and emits
/// alerts when budget thresholds are crossed. The MonitorEngine handles dedup —
/// each threshold fires at most once per tracking session.
@MainActor
final class BudgetDepletionMonitor: PollingMonitor {
    let monitorName = "BudgetDepletion"
    let pollInterval: Duration = .seconds(120)

    private let logger = Logger(category: "BudgetDepletion")
    private let timerService: TimerService
    private let budgetService: BudgetService

    init(timerService: TimerService, budgetService: BudgetService) {
        self.timerService = timerService
        self.budgetService = budgetService
    }

    /// Only poll when a timer is actively running.
    var isActive: Bool {
        if case .running = timerService.timerState { return true }
        return false
    }

    func check() async -> [MonitorAlert] {
        guard case .running = timerService.timerState,
              let activity = timerService.currentActivity else { return [] }

        let projectId = activity.projectId
        let taskId = activity.taskId
        let projectName = activity.projectName

        // Refresh budget data so we check against latest server state.
        await budgetService.refreshProject(projectId)
        let status = budgetService.status(projectId: projectId, taskId: taskId)
        logger.debug("Threshold check: project=\(projectId) badge=\(String(describing: status.effectiveBadge))")

        var alerts: [MonitorAlert] = []

        if status.taskLevel == .critical {
            alerts.append(MonitorAlert(
                type: .budgetTaskWarning,
                message: String(localized: "notification.budgetTaskWarning") + " " + projectName,
                dedupKey: "BudgetDepletion:task-critical",
                dedupStrategy: .once
            ))
        }

        if status.projectLevel == .critical {
            alerts.append(MonitorAlert(
                type: .budgetProjectWarning,
                message: String(localized: "notification.budgetProjectWarning") + " " + projectName,
                dedupKey: "BudgetDepletion:project-critical",
                dedupStrategy: .once
            ))
        }

        if status.projectLevel == .warning {
            alerts.append(MonitorAlert(
                type: .budgetProjectWarning,
                message: String(localized: "notification.budgetProjectWarning") + " " + projectName,
                dedupKey: "BudgetDepletion:project-warning",
                dedupStrategy: .once
            ))
        }

        return alerts
    }

    func resetSession() {
        // Dedup keys are cleared by the engine using monitorName prefix.
        logger.info("Session reset — dedup flags will be cleared by engine")
    }
}
