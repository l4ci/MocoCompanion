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

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        identifier = try container.decodeIfPresent(String.self, forKey: .identifier) ?? ""
        active = try container.decode(Bool.self, forKey: .active)
        billable = try container.decode(Bool.self, forKey: .billable)
        billingVariant = try container.decodeIfPresent(String.self, forKey: .billingVariant) ?? ""
        budget = try container.decodeIfPresent(Double.self, forKey: .budget)
        hourlyRate = try container.decodeIfPresent(Double.self, forKey: .hourlyRate) ?? 0
        tasks = try container.decodeIfPresent([MocoFullTask].self, forKey: .tasks) ?? []
    }

    init(id: Int, name: String, identifier: String = "", active: Bool = true, billable: Bool = true, billingVariant: String = "", budget: Double? = nil, hourlyRate: Double = 0, tasks: [MocoFullTask] = []) {
        self.id = id; self.name = name; self.identifier = identifier; self.active = active
        self.billable = billable; self.billingVariant = billingVariant; self.budget = budget
        self.hourlyRate = hourlyRate; self.tasks = tasks
    }

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

    init(id: Int, userId: Int, firstname: String = "", lastname: String = "", billable: Bool = false, active: Bool = true, budget: Double? = nil, hourlyRate: Double = 0) {
        self.id = id; self.userId = userId; self.firstname = firstname; self.lastname = lastname
        self.billable = billable; self.active = active; self.budget = budget; self.hourlyRate = hourlyRate
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        userId = try container.decode(Int.self, forKey: .userId)
        firstname = try container.decodeIfPresent(String.self, forKey: .firstname) ?? ""
        lastname = try container.decodeIfPresent(String.self, forKey: .lastname) ?? ""
        billable = try container.decodeIfPresent(Bool.self, forKey: .billable) ?? false
        active = try container.decodeIfPresent(Bool.self, forKey: .active) ?? true
        budget = try container.decodeIfPresent(Double.self, forKey: .budget)
        hourlyRate = try container.decodeIfPresent(Double.self, forKey: .hourlyRate) ?? 0
    }
}
