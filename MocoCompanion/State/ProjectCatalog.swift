import Foundation
import os

/// Owns the project list, search index, and loading state.
/// Extracted from AppState to separate project catalog concerns from service wiring.
@Observable
@MainActor
final class ProjectCatalog {
    private let logger = Logger(category: "ProjectCatalog")

    var projects: [MocoProject] = [] {
        didSet {
            _searchEntries = nil
        }
    }
    var isLoading = false

    private var _searchEntries: [SearchEntry]?

    var searchEntries: [SearchEntry] {
        if let cached = _searchEntries { return cached }
        let entries = SearchEntry.from(projects: projects)
        _searchEntries = entries
        return entries
    }

    var assignedProjectIds: [Int] { projects.map(\.id) }

    init() {
        let cached = ProjectCache.load()
        if !cached.isEmpty { projects = cached }
    }

    func fetchProjects(
        client: (any MocoClientProtocol)?,
        onError: (MocoError) -> Void,
        dispatcher: NotificationDispatcher
    ) async {
        guard let client else {
            logger.warning("Cannot fetch projects — API not configured")
            onError(.invalidConfiguration)
            return
        }
        isLoading = true
        do {
            let fetched = try await client.fetchAssignedProjects()
            projects = fetched
            ProjectCache.save(fetched)
            logger.info("Fetched \(fetched.count) projects")
            dispatcher.send(.projectsRefreshed, message: "\(fetched.count) projects synced")
        } catch {
            let mocoError = MocoError.from(error)
            onError(mocoError)
            dispatcher.send(.apiError, message: mocoError.errorDescription ?? "Unknown error")
            logger.error("fetchProjects failed: \(error.localizedDescription)")
            Task { await AppLogger.shared.app("fetchProjects failed: \(error.localizedDescription)", level: .error, context: "ProjectCatalog") }
        }
        isLoading = false
    }
}
