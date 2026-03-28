import Foundation

// MARK: - Full Project (from GET /projects/{id})

/// Full project details including billing configuration and task budgets.
/// Richer than MocoProject (from /projects/assigned) — includes billing_variant, budget, and task hourly rates.
struct MocoFullProject: Codable, Identifiable, Sendable {
    let id: Int
    let name: String
    let identifier: String
    let active: Bool
    let billable: Bool
    let billingVariant: String
    let budget: Double?
    let hourlyRate: Double
    let tasks: [MocoFullTask]

    enum CodingKeys: String, CodingKey {
        case id, name, identifier, active, billable, budget, tasks
        case billingVariant = "billing_variant"
        case hourlyRate = "hourly_rate"
    }
}

/// Task within a full project response — includes budget and hourly rate.
struct MocoFullTask: Codable, Identifiable, Sendable {
    let id: Int
    let name: String
    let active: Bool
    let billable: Bool
    let budget: Double?
    let hourlyRate: Double?

    enum CodingKeys: String, CodingKey {
        case id, name, active, billable, budget
        case hourlyRate = "hourly_rate"
    }
}

// MARK: - Project Report (from GET /projects/{id}/report)

/// Project report with budget progress, hours, and per-task cost breakdown.
struct MocoProjectReport: Codable, Sendable {
    let budgetTotal: Double?
    let budgetProgressInPercentage: Int?
    let budgetRemaining: Double?
    let hoursTotal: Double?
    let hoursBillable: Double?
    let hoursRemaining: Double?
    let costsByTask: [MocoReportTaskCost]?

    enum CodingKeys: String, CodingKey {
        case hoursTotal = "hours_total"
        case hoursBillable = "hours_billable"
        case hoursRemaining = "hours_remaining"
        case budgetTotal = "budget_total"
        case budgetProgressInPercentage = "budget_progress_in_percentage"
        case budgetRemaining = "budget_remaining"
        case costsByTask = "costs_by_task"
    }
}

/// Per-task cost entry in a project report.
struct MocoReportTaskCost: Codable, Identifiable, Sendable {
    let id: Int
    let name: String
    let hoursTotal: Double?
    let totalCosts: Double?

    enum CodingKeys: String, CodingKey {
        case id, name
        case hoursTotal = "hours_total"
        case totalCosts = "total_costs"
    }
}

// MARK: - Project Contracts (from GET /projects/{id}/contracts)

/// User contract on a project — defines per-user billing rate and budget.
struct MocoProjectContract: Codable, Identifiable, Sendable {
    let id: Int
    let userId: Int
    let firstname: String
    let lastname: String
    let billable: Bool
    let active: Bool
    let budget: Double?
    let hourlyRate: Double

    enum CodingKeys: String, CodingKey {
        case id, firstname, lastname, billable, active, budget
        case userId = "user_id"
        case hourlyRate = "hourly_rate"
    }
}
