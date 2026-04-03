import Testing
import Foundation

@Suite("BudgetService")
struct BudgetServiceTests {

    // MARK: - Helpers

    @MainActor
    private func makeService(
        api: MockBudgetAPI? = MockBudgetAPI(),
        userIdProvider: @escaping () -> Int? = { 42 }
    ) -> BudgetService {
        BudgetService(
            clientFactory: { api },
            userIdProvider: userIdProvider
        )
    }

    /// Pre-wired mock that returns valid project, report, and contracts.
    private func makePopulatedAPI() -> MockBudgetAPI {
        var api = MockBudgetAPI()
        api.fetchProjectHandler = { _ in
            TestFactories.makeFullProject()
        }
        api.fetchProjectReportHandler = { _ in
            TestFactories.makeProjectReport()
        }
        api.fetchProjectContractsHandler = { _ in
            [TestFactories.makeProjectContract()]
        }
        return api
    }

    // MARK: - Status for uncached project

    @Test("status returns .empty for uncached project")
    @MainActor func statusReturnsEmptyForUncached() {
        let service = makeService()
        let status = service.status(projectId: 999)
        #expect(status == .empty)
    }

    // MARK: - Nil client

    @Test("refreshBudgets with nil client returns without crashing")
    @MainActor func nilClientDoesNotCrash() async {
        let service = makeService(api: nil)
        // Should silently return — no crash
        await service.refreshBudgets(projectIds: [100])
        let status = service.status(projectId: 100)
        #expect(status == .empty)
    }

    // MARK: - Refresh populates cache

    @Test("refreshBudgets populates cache so status returns computed result")
    @MainActor func refreshPopulatesCache() async {
        let api = makePopulatedAPI()
        let service = makeService(api: api)

        #expect(service.status(projectId: 100) == .empty)

        await service.refreshBudgets(projectIds: [100])

        let status = service.status(projectId: 100)
        #expect(status != .empty)
        // The factory defaults give 50% progress → should be projectLevel .warning (50-89%)
        #expect(status.projectLevel == .warning)
        #expect(status.projectProgressPercent == 50)
    }

    // MARK: - Rate limit stops batch

    @Test("refreshBudgets stops batch on rate limit error")
    @MainActor func rateLimitStopsBatch() async {
        var callCount = 0
        var api = MockBudgetAPI()
        api.fetchProjectReportHandler = { projectId in
            callCount += 1
            if projectId == 101 {
                throw MocoError.rateLimited(retryAfter: 60)
            }
            return TestFactories.makeProjectReport()
        }
        api.fetchProjectHandler = { _ in TestFactories.makeFullProject() }
        api.fetchProjectContractsHandler = { _ in [] }

        let service = makeService(api: api)

        // Request 3 projects — second one rate-limits, third should not be attempted
        await service.refreshBudgets(projectIds: [100, 101, 102])

        // First project fetched successfully, second hit rate limit, third skipped
        #expect(service.status(projectId: 100) != .empty)
        #expect(service.status(projectId: 101) == .empty)
        #expect(service.status(projectId: 102) == .empty)
    }

    // MARK: - Cache reuse (< 60s skip)

    @Test("refreshBudgets skips projects with fresh cache (< 60s)")
    @MainActor func cacheReuseSkipsRefresh() async {
        var reportFetchCount = 0
        var api = MockBudgetAPI()
        api.fetchProjectHandler = { _ in TestFactories.makeFullProject() }
        api.fetchProjectReportHandler = { _ in
            reportFetchCount += 1
            return TestFactories.makeProjectReport()
        }
        api.fetchProjectContractsHandler = { _ in [] }

        let service = makeService(api: api)

        // First refresh — should fetch
        await service.refreshBudgets(projectIds: [100])
        #expect(reportFetchCount == 1)

        // Second refresh immediately — should skip (< 60s)
        await service.refreshBudgets(projectIds: [100])
        #expect(reportFetchCount == 1)  // Still 1, not called again
    }

    // MARK: - 403 on contracts falls back gracefully

    @Test("403 on contracts falls back to empty contracts, still caches project")
    @MainActor func contractsForbiddenFallback() async {
        var api = MockBudgetAPI()
        api.fetchProjectHandler = { _ in TestFactories.makeFullProject() }
        api.fetchProjectReportHandler = { _ in TestFactories.makeProjectReport() }
        api.fetchProjectContractsHandler = { _ in
            throw MocoError.serverError(statusCode: 403, message: "Forbidden")
        }

        let service = makeService(api: api)
        await service.refreshBudgets(projectIds: [100])

        // Should still have cached data despite contract failure
        let status = service.status(projectId: 100)
        #expect(status != .empty)
        #expect(status.projectProgressPercent == 50)
    }
}
