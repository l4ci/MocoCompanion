import Testing
import Foundation

// MARK: - Test Helpers

/// Spy monitor that records check() calls and returns configurable alerts.
@MainActor
private final class SpyMonitor: PollingMonitor {
    let monitorName: String
    let pollInterval: Duration = .seconds(60)
    var isActive: Bool
    var stubbedAlerts: [MonitorAlert] = []
    private(set) var checkCallCount = 0
    private(set) var resetSessionCallCount = 0

    init(name: String, active: Bool = true) {
        self.monitorName = name
        self.isActive = active
    }

    func check() async -> [MonitorAlert] {
        checkCallCount += 1
        return stubbedAlerts
    }

    func resetSession() {
        resetSessionCallCount += 1
    }
}

/// Capturing dispatcher that records what was sent without posting system notifications.
@MainActor
private final class CapturingDispatcher {
    var dispatchedTypes: [NotificationCatalog.NotificationType] = []
    var dispatchedMessages: [String] = []

    func asNotificationDispatcher() -> NotificationDispatcher {
        NotificationDispatcher(isEnabledCheck: { [weak self] type in
            self?.dispatchedTypes.append(type)
            return false  // suppress real UNUserNotificationCenter posting
        })
    }
}

// MARK: - Tests

@Suite("MonitorEngine")
struct MonitorEngineTests {

    @MainActor
    private func makeEngine() -> (MonitorEngine, ManualMonitorScheduler, CapturingDispatcher) {
        let scheduler = ManualMonitorScheduler()
        let capturing = CapturingDispatcher()
        let engine = MonitorEngine(dispatcher: capturing.asNotificationDispatcher(), scheduler: scheduler)
        return (engine, scheduler, capturing)
    }

    // MARK: - Registration

    @Test("register schedules monitor with scheduler")
    @MainActor func registerSchedulesMonitor() {
        let (engine, scheduler, _) = makeEngine()
        let monitor = SpyMonitor(name: "budget")

        engine.register(monitor)

        #expect(scheduler.scheduledNames.contains("budget"))
    }

    @Test("register with immediateFirstCheck uses scheduleImmediate")
    @MainActor func registerImmediateUsesImmediatePath() {
        let (engine, scheduler, _) = makeEngine()
        let monitor = SpyMonitor(name: "yesterday")

        engine.register(monitor, immediateFirstCheck: true)

        #expect(scheduler.immediateNames.contains("yesterday"))
        #expect(!scheduler.scheduledNames.contains("yesterday"))
    }

    // MARK: - Polling

    @Test("tick calls check() when monitor is active")
    @MainActor func tickCallsCheckWhenActive() async {
        let (engine, scheduler, _) = makeEngine()
        let monitor = SpyMonitor(name: "idle", active: true)
        engine.register(monitor)

        await scheduler.fire(monitorNamed: "idle")

        #expect(monitor.checkCallCount == 1)
    }

    @Test("tick skips check() when monitor is inactive")
    @MainActor func tickSkipsCheckWhenInactive() async {
        let (engine, scheduler, _) = makeEngine()
        let monitor = SpyMonitor(name: "budget", active: false)
        engine.register(monitor)

        await scheduler.fire(monitorNamed: "budget")
        await scheduler.fire(monitorNamed: "budget")

        #expect(monitor.checkCallCount == 0)
    }

    // MARK: - Dispatch

    @Test("alert from check() is dispatched when not yet fired")
    @MainActor func alertIsDispatchedFirstTime() async {
        let (engine, scheduler, capturing) = makeEngine()
        let monitor = SpyMonitor(name: "idle")
        monitor.stubbedAlerts = [MonitorAlert(
            type: .idleReminder,
            message: "Time to track!",
            dedupKey: "idle:reminder",
            dedupStrategy: .once
        )]
        engine.register(monitor)

        await scheduler.fire(monitorNamed: "idle")

        #expect(capturing.dispatchedTypes.contains(.idleReminder))
    }

    // MARK: - Dedup

    @Test(".once dedup fires exactly once regardless of tick count")
    @MainActor func dedupOnceFiresOnce() async {
        let (engine, scheduler, capturing) = makeEngine()
        let monitor = SpyMonitor(name: "budget")
        monitor.stubbedAlerts = [MonitorAlert(
            type: .budgetProjectWarning,
            message: "80% consumed",
            dedupKey: "budget:project-warning",
            dedupStrategy: .once
        )]
        engine.register(monitor)

        await scheduler.fire(monitorNamed: "budget")
        await scheduler.fire(monitorNamed: "budget")
        await scheduler.fire(monitorNamed: "budget")

        let count = capturing.dispatchedTypes.filter { $0 == .budgetProjectWarning }.count
        #expect(count == 1)
    }

    @Test("resetSession clears dedup so monitor can fire again")
    @MainActor func resetSessionClearsDedup() async {
        let (engine, scheduler, capturing) = makeEngine()
        let monitor = SpyMonitor(name: "budget")
        monitor.stubbedAlerts = [MonitorAlert(
            type: .budgetProjectWarning,
            message: "80% consumed",
            dedupKey: "budget:project-warning",
            dedupStrategy: .once
        )]
        engine.register(monitor)

        // Fire once — dedup blocks subsequent fires
        await scheduler.fire(monitorNamed: "budget")
        await scheduler.fire(monitorNamed: "budget")  // suppressed by dedup

        // Reset session — dedup keys cleared for this monitor
        engine.resetSession(for: monitor)
        await scheduler.fire(monitorNamed: "budget")  // should fire again

        let count = capturing.dispatchedTypes.filter { $0 == .budgetProjectWarning }.count
        #expect(count == 2)
        #expect(monitor.resetSessionCallCount == 1)
    }

    @Test("resetSession only clears keys for that monitor, not others")
    @MainActor func resetSessionDoesNotClearOtherMonitors() async {
        let (engine, scheduler, capturing) = makeEngine()

        let budget = SpyMonitor(name: "budget")
        budget.stubbedAlerts = [MonitorAlert(
            type: .budgetProjectWarning,
            message: "80%",
            dedupKey: "budget:project-warning",
            dedupStrategy: .once
        )]

        let idle = SpyMonitor(name: "idle")
        idle.stubbedAlerts = [MonitorAlert(
            type: .idleReminder,
            message: "Track it",
            dedupKey: "idle:reminder",
            dedupStrategy: .once
        )]

        engine.register(budget)
        engine.register(idle)

        await scheduler.fire(monitorNamed: "budget")
        await scheduler.fire(monitorNamed: "idle")

        // Reset budget only
        engine.resetSession(for: budget)

        await scheduler.fire(monitorNamed: "budget")  // re-fires after reset
        await scheduler.fire(monitorNamed: "idle")     // still deduped

        let budgetCount = capturing.dispatchedTypes.filter { $0 == .budgetProjectWarning }.count
        let idleCount = capturing.dispatchedTypes.filter { $0 == .idleReminder }.count
        #expect(budgetCount == 2)
        #expect(idleCount == 1)
    }

    // MARK: - Unregister / Stop

    @Test("unregister cancels the monitor's scheduler entry")
    @MainActor func unregisterCancelsScheduler() {
        let (engine, scheduler, _) = makeEngine()
        let monitor = SpyMonitor(name: "idle")
        engine.register(monitor)

        engine.unregister(monitor)

        #expect(scheduler.cancelledNames.contains("idle"))
    }

    @Test("stopAll cancels the scheduler")
    @MainActor func stopAllCancelsScheduler() {
        let (engine, scheduler, _) = makeEngine()
        let m1 = SpyMonitor(name: "budget")
        let m2 = SpyMonitor(name: "idle")
        engine.register(m1)
        engine.register(m2)

        engine.stopAll()

        #expect(scheduler.cancelAllCalled)
    }
}
