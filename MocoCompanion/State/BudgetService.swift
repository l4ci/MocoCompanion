import Foundation
import os

// MARK: - BudgetService

/// Manages budget data: fetches project reports/contracts, resolves rates, and provides
/// synchronous status lookups from an in-memory cache.
/// Follows the ActivityService pattern: @Observable @MainActor with clientFactory/userIdProvider.
@Observable
@MainActor
final class BudgetService {
    private let logger = Logger(category: "BudgetService")

    // MARK: - Cache

    /// Maximum number of projects kept in the budget cache at once. Beyond
    /// this, least-recently-used entries are evicted. Covers the typical
    /// consultancy workload (≤32 active projects at once) while preventing
    /// unbounded heap growth across long sessions.
    private static let cacheCapacity = 32

    /// Cached budget data per project ID. `accessOrder` tracks LRU recency.
    private var projectCaches: [Int: ProjectBudgetCache] = [:]
    private var accessOrder: [Int] = []

    /// Internal cache entry for a single project's budget data.
    private struct ProjectBudgetCache {
        let report: MocoProjectReport
        let fullProject: MocoFullProject
        let contracts: [MocoProjectContract]
        let fetchedAt: Date
    }

    // MARK: - Test Inspection

    #if DEBUG
    /// Test-only count of cached entries. Do not use in production code.
    var _cachedProjectCount: Int { projectCaches.count }
    #endif

    // MARK: - Cache Operations

    /// Record a read access to keep the LRU order honest.
    private func touch(_ projectId: Int) {
        if let idx = accessOrder.firstIndex(of: projectId) {
            accessOrder.remove(at: idx)
        }
        accessOrder.append(projectId)
    }

    /// Insert or replace a cache entry and evict if we're over capacity.
    private func storeCache(_ cache: ProjectBudgetCache, for projectId: Int) {
        projectCaches[projectId] = cache
        touch(projectId)
        while projectCaches.count > Self.cacheCapacity, let oldest = accessOrder.first {
            accessOrder.removeFirst()
            projectCaches.removeValue(forKey: oldest)
        }
    }

    // MARK: - Dependencies

    private let clientFactory: () -> (any BudgetAPI)?
    private let userIdProvider: () -> Int?

    init(
        clientFactory: @escaping () -> (any BudgetAPI)?,
        userIdProvider: @escaping () -> Int? = { nil }
    ) {
        self.clientFactory = clientFactory
        self.userIdProvider = userIdProvider
    }

    // MARK: - Public Query API

    /// Synchronous lookup of budget status from cache.
    /// Returns `.empty` if no data is cached for the given project.
    func status(projectId: Int, taskId: Int? = nil) -> BudgetStatus {
        guard let cache = projectCaches[projectId] else {
            return .empty
        }
        touch(projectId)
        return computeStatus(cache: cache, taskId: taskId)
    }

    // MARK: - Refresh

    /// Fetch budget data for multiple projects. Errors are caught per-project so one
    /// failure doesn't block the rest. Rate limiting is handled centrally by APIRateGate.
    func refreshBudgets(projectIds: [Int]) async {
        guard let client = clientFactory() else { return }
        let userId = userIdProvider()

        for (index, projectId) in projectIds.enumerated() {
            let hitRateLimit = await refreshSingleProject(projectId: projectId, client: client, userId: userId)
            if hitRateLimit {
                logger.warning("Rate limited during budget refresh — stopping after \(index + 1) of \(projectIds.count) projects")
                break
            }
        }

        logger.info("Budget refresh complete: \(self.projectCaches.count) projects cached")
    }

    /// Refresh budget data for a single project (e.g. after timer start/stop).
    func refreshProject(_ projectId: Int) async {
        guard let client = clientFactory() else { return }
        let userId = userIdProvider()
        await refreshSingleProject(projectId: projectId, client: client, userId: userId)
    }

    // MARK: - Private: Fetch & Cache

    /// Returns `true` if the API returned a rate limit error (caller should stop the batch).
    @discardableResult
    private func refreshSingleProject(
        projectId: Int,
        client: any BudgetAPI,
        userId: Int?
    ) async -> Bool {
        do {
            let existingCache = projectCaches[projectId]
            let cacheAge = existingCache.map { Date.now.timeIntervalSince($0.fetchedAt) } ?? .infinity
            let reuseDetails = cacheAge < 300  // 5 minutes for project/contracts

            // Skip entirely if the whole cache (including report) is fresh (<60s)
            // This prevents redundant fetches when multiple triggers fire close together
            if cacheAge < 60 {
                logger.debug("Budget cache for project \(projectId) is fresh (\(Int(cacheAge))s) — skipping")
                return false
            }

            // Always fetch report (changes frequently) unless very recent
            let report = try await client.fetchProjectReport(projectId: projectId)

            let fullProject: MocoFullProject
            let contracts: [MocoProjectContract]

            if reuseDetails, let existing = existingCache {
                fullProject = existing.fullProject
                contracts = existing.contracts
            } else {
                fullProject = try await client.fetchProject(id: projectId)
                contracts = await fetchContractsSafely(projectId: projectId, client: client)
            }

            storeCache(
                ProjectBudgetCache(
                    report: report,
                    fullProject: fullProject,
                    contracts: contracts,
                    fetchedAt: Date.now
                ),
                for: projectId
            )
            return false
        } catch let error as MocoError {
            switch error {
            case .rateLimited(let retryAfter):
                logger.warning("Rate limited fetching budget for project \(projectId), retry after \(retryAfter ?? 0)s")
                Task {
                    await AppLogger.shared.app(
                        "Budget refresh rate limited for project \(projectId)",
                        level: .warning, context: "BudgetService"
                    )
                }
                return true
            default:
                logger.error("Budget refresh failed for project \(projectId): \(error.localizedDescription)")
                return false
            }
        } catch {
            logger.error("Budget refresh failed for project \(projectId): \(error.localizedDescription)")
            return false
        }
    }

    /// Fetch contracts with graceful fallback on 403 (user may lack permission).
    private func fetchContractsSafely(
        projectId: Int,
        client: any BudgetAPI
    ) async -> [MocoProjectContract] {
        do {
            return try await client.fetchProjectContracts(projectId: projectId)
        } catch let error as MocoError {
            if case .serverError(let statusCode, _) = error, statusCode == 403 {
                logger.warning("No permission for contracts on project \(projectId), falling back to project rate")
            } else {
                logger.error("Failed to fetch contracts for project \(projectId): \(error.localizedDescription)")
            }
        } catch {
            logger.error("Failed to fetch contracts for project \(projectId): \(error.localizedDescription)")
        }
        return []
    }

    // MARK: - Private: Status Computation

    private func computeStatus(cache: ProjectBudgetCache, taskId: Int?) -> BudgetStatus {
        BudgetCalculator.status(
            report: cache.report,
            project: cache.fullProject,
            contracts: cache.contracts,
            taskId: taskId,
            userId: userIdProvider()
        )
    }
}
