import Testing
import Foundation
@testable import MocoCompanion

/// A handshake keeps the stale-result test independent of scheduling and wall time.
@MainActor
private final class BudgetReportGate {
    private var started = false
    private var startWaiter: CheckedContinuation<Void, Never>?
    private var reportWaiter: CheckedContinuation<Void, Never>?

    func fetch() async -> MocoProjectReport {
        await withCheckedContinuation { continuation in
            reportWaiter = continuation
            started = true
            startWaiter?.resume()
            startWaiter = nil
        }
        return TestFactories.makeProjectReport(budgetProgressInPercentage: 95)
    }

    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { startWaiter = $0 }
    }

    func finish() {
        reportWaiter?.resume()
        reportWaiter = nil
    }
}

@MainActor
@Suite("BudgetDepletionMonitor")
struct BudgetDepletionMonitorTests {
    private func budgetAPI(progress: Int = 95) -> MockBudgetAPI {
        var api = MockBudgetAPI()
        api.fetchProjectHandler = { _ in
            TestFactories.makeFullProject(tasks: [200, 201].map {
                ["id": $0, "name": "Task", "active": true, "billable": true,
                 "budget": 1000.0, "hourly_rate": 100.0] as [String: Any]
            })
        }
        api.fetchProjectReportHandler = { _ in
            TestFactories.makeProjectReport(budgetProgressInPercentage: progress, costsByTask: [200, 201].map {
                ["id": $0, "name": "Task", "hours_total": 10.0, "total_costs": 1000.0] as [String: Any]
            })
        }
        return api
    }

    @Test("Budget thresholds dedup per activity and task, across resumes", arguments: [0, 1, 2], [50, 95])
    func budgetUsesSessionIdentity(change: Int, progress: Int) async throws {
        var activity = TestFactories.makeActivity(id: 10, timerStartedAt: "2026-01-05T08:00:00Z")
        var api = MockTimerAPI()
        api.fetchActivitiesHandler = { _, _, _ in [activity] }
        api.createActivityHandler = { _, _, _, _, _, _ in activity }
        api.stopTimerHandler = { id in TestFactories.makeActivity(id: id) }
        api.startTimerHandler = { _ in activity }
        let timer = TimerService(clientFactory: { api }, userIdProvider: { 42 })
        await timer.sync()
        let budgetsAPI = budgetAPI(progress: progress)
        let budgets = BudgetService(clientFactory: { budgetsAPI }, userIdProvider: { 42 })
        let monitor = BudgetDepletionMonitor(timerService: timer, budgetService: budgets)
        let first = await monitor.check()
        #expect(first.count == 2)
        #expect(first.contains { $0.type == .budgetTaskWarning })
        #expect(first.contains { $0.type == .budgetProjectWarning })
        var ledger = DedupLedger()
        for alert in first { ledger.markFired(alert) }
        for alert in await monitor.check() { #expect(!ledger.shouldFire(alert)) }

        switch change {
        case 0:
            activity = TestFactories.makeActivity(id: 11, timerStartedAt: "2026-01-05T08:00:00Z")
            await timer.sync()
        case 1:
            await timer.pauseTimer()
            activity = TestFactories.makeActivity(id: 10, timerStartedAt: "2026-01-05T09:00:00Z")
            await timer.resumeTimer()
        default:
            activity = TestFactories.makeActivity(id: 10, taskId: 201, timerStartedAt: "2026-01-05T08:00:00Z")
            _ = await timer.startTimer(projectId: 100, taskId: 201, description: "Next task")
        }
        let second = await monitor.check()
        #expect(second.count == 2)
        for alert in second {
            // Resuming the same activity is one continuous booking: no repeat alert.
            #expect(ledger.shouldFire(alert) == (change != 1))
            ledger.markFired(alert)
        }
        for alert in await monitor.check() { #expect(!ledger.shouldFire(alert)) }
    }

    @Test("In-flight budget results are discarded after replacement, resume, or pause", arguments: [0, 1, 2])
    func staleBudgetResultIsDiscarded(change: Int) async {
        var activity = TestFactories.makeActivity(id: 10, timerStartedAt: "2026-01-05T08:00:00Z")
        var api = MockTimerAPI()
        api.fetchActivitiesHandler = { _, _, _ in [activity] }
        api.stopTimerHandler = { id in TestFactories.makeActivity(id: id) }
        api.startTimerHandler = { _ in activity }
        let timer = TimerService(clientFactory: { api }, userIdProvider: { 42 })
        await timer.sync()
        let gate = BudgetReportGate()
        var budgetsAPI = budgetAPI()
        budgetsAPI.fetchProjectReportHandler = { _ in await gate.fetch() }
        let budgets = BudgetService(clientFactory: { budgetsAPI }, userIdProvider: { 42 })
        let monitor = BudgetDepletionMonitor(timerService: timer, budgetService: budgets)
        let check = Task { await monitor.check() }
        await gate.waitUntilStarted()
        switch change {
        case 0:
            activity = TestFactories.makeActivity(id: 11, timerStartedAt: "2026-01-05T08:00:00Z")
            await timer.sync()
        case 1:
            await timer.pauseTimer()
            activity = TestFactories.makeActivity(id: 10, timerStartedAt: "2026-01-05T09:00:00Z")
            await timer.resumeTimer()
        default:
            await timer.pauseTimer()
        }
        gate.finish()
        #expect(await check.value.isEmpty)
        // The fetched data really qualified; silence came from the session guard.
        #expect(budgets.status(projectId: 100).projectLevel == .critical)
    }
}
