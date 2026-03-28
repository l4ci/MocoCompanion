import Foundation

// MARK: - Budget Level

/// Severity level for budget consumption.
/// Ordered by severity so max(projectLevel, taskLevel) gives the worst case.
enum BudgetLevel: Int, Sendable, Equatable, Comparable {
    case none = 0      // No budget configured or no data
    case healthy = 1   // Under 50% consumed
    case warning = 2   // 50–89% consumed
    case critical = 3  // 90%+ consumed or <1h remaining

    static func < (lhs: BudgetLevel, rhs: BudgetLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Budget Badge

/// Visual badge severity for EntryRow display.
/// Maps BudgetStatus to a specific color indicator.
enum BudgetBadge: Sendable, Equatable {
    case none             // No badge shown
    case projectWarning   // Yellow — project at 50–89% consumed
    case projectCritical  // Orange — project at 90%+ consumed
    case taskCritical     // Red — task has <1h remaining
}

// MARK: - Budget Status

/// Combined budget status for a project and optionally a task within it.
struct BudgetStatus: Sendable, Equatable {
    let projectLevel: BudgetLevel
    let projectProgressPercent: Int?
    let projectHoursRemaining: Double?
    let taskLevel: BudgetLevel
    let taskHoursRemaining: Double?

    /// Default status when no data is available.
    static let empty = BudgetStatus(
        projectLevel: .none, projectProgressPercent: nil, projectHoursRemaining: nil,
        taskLevel: .none, taskHoursRemaining: nil
    )

    /// The highest-severity badge to display, considering both project and task levels.
    /// Task-critical (red) takes precedence over project-critical (orange) over project-warning (yellow).
    var effectiveBadge: BudgetBadge {
        if taskLevel == .critical {
            return .taskCritical
        }
        switch projectLevel {
        case .critical:
            return .projectCritical
        case .warning:
            return .projectWarning
        case .healthy, .none:
            return .none
        }
    }
}
