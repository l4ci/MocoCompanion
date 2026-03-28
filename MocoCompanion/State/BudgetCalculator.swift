import Foundation

/// Pure computation for budget status, level thresholds, and hourly rate resolution.
/// No I/O, no caching, no @Observable — just input→output.
/// Extracted from BudgetService to enable thorough unit testing of the
/// complex billing-variant and threshold logic.
enum BudgetCalculator {

    // MARK: - Status Computation

    /// Compute the combined budget status for a project and optionally a task.
    static func status(
        report: MocoProjectReport,
        project: MocoFullProject,
        contracts: [MocoProjectContract],
        taskId: Int?,
        userId: Int?
    ) -> BudgetStatus {
        let projectLevel = projectLevel(report: report)
        let projectProgressPercent = report.budgetProgressInPercentage
        let projectHoursRemaining = report.hoursRemaining

        let taskLevel: BudgetLevel
        let taskHoursRemaining: Double?

        if let taskId {
            let result = self.taskLevel(
                taskId: taskId,
                project: project,
                report: report,
                contracts: contracts,
                userId: userId
            )
            taskLevel = result.level
            taskHoursRemaining = result.hoursRemaining
        } else {
            taskLevel = .none
            taskHoursRemaining = nil
        }

        return BudgetStatus(
            projectLevel: projectLevel,
            projectProgressPercent: projectProgressPercent,
            projectHoursRemaining: projectHoursRemaining,
            taskLevel: taskLevel,
            taskHoursRemaining: taskHoursRemaining
        )
    }

    // MARK: - Project Level

    /// Project-level budget severity from report progress percentage.
    static func projectLevel(report: MocoProjectReport) -> BudgetLevel {
        guard let progress = report.budgetProgressInPercentage else {
            return .none
        }
        switch progress {
        case ..<50:
            return .healthy
        case 50..<90:
            return .warning
        default:
            return .critical
        }
    }

    // MARK: - Task Level

    /// Task-level budget severity: derives remaining hours from task budget and consumed hours.
    /// Returns `.none` if the task has no budget or rate can't be resolved.
    static func taskLevel(
        taskId: Int,
        project: MocoFullProject,
        report: MocoProjectReport,
        contracts: [MocoProjectContract],
        userId: Int?
    ) -> (level: BudgetLevel, hoursRemaining: Double?) {
        guard let task = project.tasks.first(where: { $0.id == taskId }) else {
            return (.none, nil)
        }
        guard let taskBudget = task.budget, taskBudget > 0 else {
            return (.none, nil)
        }

        let consumedHours = (report.costsByTask ?? [])
            .first(where: { $0.id == taskId })?.hoursTotal ?? 0

        // Task budget is in currency — convert to hours using resolved rate
        let rate = resolveHourlyRate(
            billingVariant: project.billingVariant,
            projectRate: project.hourlyRate,
            task: task,
            contracts: contracts,
            userId: userId
        )

        if let rate, rate > 0 {
            let totalHours = taskBudget / rate
            let remaining = totalHours - consumedHours
            let level: BudgetLevel = remaining < 1.0 ? .critical : .healthy
            return (level, remaining)
        } else {
            return (.none, nil)
        }
    }

    // MARK: - Rate Resolution

    /// Resolve the effective hourly rate based on the project's billing variant.
    /// - "project" → project-level rate
    /// - "task" → task-level rate
    /// - "user" → user contract rate
    /// Returns nil if the rate is 0 or cannot be resolved.
    static func resolveHourlyRate(
        billingVariant: String,
        projectRate: Double,
        task: MocoFullTask?,
        contracts: [MocoProjectContract],
        userId: Int?
    ) -> Double? {
        let rate: Double?
        switch billingVariant {
        case "project":
            rate = projectRate
        case "task":
            rate = task?.hourlyRate
        case "user":
            if let userId {
                rate = contracts.first(where: { $0.userId == userId })?.hourlyRate
            } else {
                rate = nil
            }
        default:
            rate = projectRate  // Fallback to project rate for unknown variants
        }

        guard let resolved = rate, resolved > 0 else { return nil }
        return resolved
    }
}
