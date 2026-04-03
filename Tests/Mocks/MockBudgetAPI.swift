import Foundation

/// Closure-based mock for BudgetAPI (project details, reports, contracts).
struct MockBudgetAPI: BudgetAPI, @unchecked Sendable {
    var fetchProjectHandler: (Int) async throws -> MocoFullProject = { _ in
        throw MocoError.serverError(statusCode: 500, message: "fetchProject not stubbed")
    }
    var fetchProjectReportHandler: (Int) async throws -> MocoProjectReport = { _ in
        throw MocoError.serverError(statusCode: 500, message: "fetchProjectReport not stubbed")
    }
    var fetchProjectContractsHandler: (Int) async throws -> [MocoProjectContract] = { _ in [] }

    func fetchProject(id: Int) async throws -> MocoFullProject {
        try await fetchProjectHandler(id)
    }

    func fetchProjectReport(projectId: Int) async throws -> MocoProjectReport {
        try await fetchProjectReportHandler(projectId)
    }

    func fetchProjectContracts(projectId: Int) async throws -> [MocoProjectContract] {
        try await fetchProjectContractsHandler(projectId)
    }
}
