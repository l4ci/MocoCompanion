import Foundation
import os
import SwiftUI

/// Owns the project list, search index, and loading state.
/// Extracted from AppState to separate project catalog concerns from service wiring.
@Observable
@MainActor
final class ProjectCatalog {
    private let logger = Logger(category: "ProjectCatalog")

    var projects: [MocoProject] = [] {
        didSet {
            _searchEntries = nil
            _colorCache = nil
        }
    }
    var isLoading = false

    @ObservationIgnored private var _searchEntries: [SearchEntry]?
    /// Lazy lookup table for project colors. Rebuilt whenever `projects`
    /// changes. Avoids the O(n) linear scan in `color(for:)` that was
    /// called per row in list views.
    @ObservationIgnored private var _colorCache: [Int: Color]?

    var searchEntries: [SearchEntry] {
        if let cached = _searchEntries { return cached }
        let entries = SearchEntry.from(projects: projects)
        _searchEntries = entries
        return entries
    }

    var assignedProjectIds: [Int] { projects.map(\.id) }

    /// Resolved project color from Moco, or nil if the project is unknown or has no color set.
    func color(for projectId: Int) -> Color? {
        if let cache = _colorCache {
            return cache[projectId]
        }
        var cache: [Int: Color] = [:]
        cache.reserveCapacity(projects.count)
        for project in projects {
            if let hex = project.color, let color = Color(hex: hex) {
                cache[project.id] = color
            }
        }
        _colorCache = cache
        return cache[projectId]
    }

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

extension ProjectCatalog {
    /// Filter search entries by fuzzy query.
    /// When query is empty, returns `favorites` if non-empty, otherwise the full catalog.
    func filter(query: String, favorites: [SearchEntry] = []) -> [SearchEntry] {
        guard !query.isEmpty else {
            return favorites.isEmpty ? searchEntries : favorites
        }
        return FuzzyMatcher.search(query: query, in: searchEntries).map(\.entry)
    }
}
