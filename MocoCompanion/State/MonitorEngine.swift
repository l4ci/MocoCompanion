import Foundation
import os

// MARK: - Monitor Event

/// What a single check cycle can emit.
struct MonitorAlert: Sendable {
    let type: NotificationCatalog.NotificationType
    let message: String
    let dedupKey: String
    let dedupStrategy: DedupStrategy

    enum DedupStrategy: Sendable {
        /// Fire once until dedup state is reset.
        case once
        /// Fire at most once per interval.
        case rateLimited(TimeInterval)
        /// Fire at most once per calendar day.
        case perDay
    }
}

// MARK: - Polling Monitor Protocol

/// A monitor that checks conditions on a polling interval and produces alerts.
/// Implement `check()` with your domain logic — the engine handles polling, lifecycle, and dedup.
@MainActor
protocol PollingMonitor: AnyObject {
    /// Human-readable name for logging.
    var monitorName: String { get }

    /// How often to poll.
    var pollInterval: Duration { get }

    /// Whether the monitor should actively check right now.
    /// When false, the loop sleeps but doesn't stop.
    var isActive: Bool { get }

    /// Run one check cycle. Return alerts to dispatch. Empty = no action.
    func check() async -> [MonitorAlert]

    /// Called when the engine resets dedup state for this monitor.
    func resetSession()
}

extension PollingMonitor {
    var isActive: Bool { true }
    func resetSession() {}
}

// MARK: - Monitor Scheduler Protocol

/// Owns the timing policy for polling monitors. The engine delegates all time/Task
/// management here, making orchestration logic testable without real Task.sleep.
@MainActor
protocol MonitorScheduler: AnyObject {
    /// Register a monitor. The scheduler calls `onTick` at the monitor's poll interval.
    /// The scheduler must respect the monitor's `pollInterval`.
    func schedule(_ monitor: any PollingMonitor, onTick: @escaping @MainActor () async -> Void)

    /// Optionally fire one immediate tick before entering the interval loop.
    /// Called by the engine for monitors registered with `immediateFirstCheck: true`.
    func scheduleImmediate(_ monitor: any PollingMonitor, onTick: @escaping @MainActor () async -> Void)

    /// Cancel all scheduled timers.
    func cancelAll()

    /// Cancel the timer for a specific monitor.
    func cancel(_ monitor: any PollingMonitor)
}

// MARK: - Production Scheduler

/// Production implementation using `Task.sleep` per monitor.
@MainActor
final class TaskMonitorScheduler: MonitorScheduler {
    private let logger = Logger(category: "MonitorScheduler")
    private var tasks: [ObjectIdentifier: Task<Void, Never>] = [:]

    func schedule(_ monitor: any PollingMonitor, onTick: @escaping @MainActor () async -> Void) {
        let id = ObjectIdentifier(monitor)
        tasks[id]?.cancel()
        tasks[id] = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: monitor.pollInterval)
                guard !Task.isCancelled else { break }
                await onTick()
            }
            self.logger.debug("\(monitor.monitorName): scheduler loop exited")
        }
    }

    func scheduleImmediate(_ monitor: any PollingMonitor, onTick: @escaping @MainActor () async -> Void) {
        let id = ObjectIdentifier(monitor)
        tasks[id]?.cancel()
        tasks[id] = Task { [weak self] in
            guard let self else { return }
            // Immediate first tick
            await onTick()
            // Then periodic
            while !Task.isCancelled {
                try? await Task.sleep(for: monitor.pollInterval)
                guard !Task.isCancelled else { break }
                await onTick()
            }
            self.logger.debug("\(monitor.monitorName): scheduler loop exited")
        }
    }

    func cancelAll() {
        tasks.values.forEach { $0.cancel() }
        tasks.removeAll()
    }

    func cancel(_ monitor: any PollingMonitor) {
        let id = ObjectIdentifier(monitor)
        tasks[id]?.cancel()
        tasks.removeValue(forKey: id)
    }
}

// MARK: - Monitor Engine

/// Runs all registered monitors, handles dedup, and dispatches notifications.
/// Timing is delegated to MonitorScheduler — swap for ManualMonitorScheduler in tests.
@MainActor
final class MonitorEngine {
    private let logger = Logger(category: "MonitorEngine")
    private let dispatcher: NotificationDispatcher
    private let scheduler: any MonitorScheduler

    private var dedupLedger = DedupLedger()
    /// Strong references so monitors aren't deallocated.
    private var monitors: [ObjectIdentifier: any PollingMonitor] = [:]

    init(dispatcher: NotificationDispatcher, scheduler: (any MonitorScheduler)? = nil) {
        self.dispatcher = dispatcher
        self.scheduler = scheduler ?? TaskMonitorScheduler()
    }

    /// Register and start polling a monitor.
    /// - Parameter immediateFirstCheck: If true, run the first check immediately instead of waiting for the poll interval.
    func register(_ monitor: any PollingMonitor, immediateFirstCheck: Bool = false) {
        let id = ObjectIdentifier(monitor)
        monitors[id] = monitor
        scheduler.cancel(monitor)

        let tick: @MainActor () async -> Void = { [weak self] in
            await self?.poll(monitor)
        }

        if immediateFirstCheck {
            scheduler.scheduleImmediate(monitor, onTick: tick)
        } else {
            scheduler.schedule(monitor, onTick: tick)
        }

        logger.info("\(monitor.monitorName): registered")
    }

    /// Unregister a specific monitor.
    func unregister(_ monitor: any PollingMonitor) {
        let id = ObjectIdentifier(monitor)
        scheduler.cancel(monitor)
        monitors.removeValue(forKey: id)
    }

    /// Reset dedup state for a specific monitor (e.g., new tracking session).
    func resetSession(for monitor: any PollingMonitor) {
        monitor.resetSession()
        dedupLedger.clearPrefix(monitor.monitorName + ":")
    }

    /// Stop all monitors. Call from applicationWillTerminate.
    func stopAll() {
        scheduler.cancelAll()
        monitors.removeAll()
    }

    // MARK: - Private

    private func poll(_ monitor: any PollingMonitor) async {
        guard monitor.isActive else { return }
        let alerts = await monitor.check()
        for alert in alerts {
            if dedupLedger.shouldFire(alert) {
                dispatcher.send(alert.type, message: alert.message)
                dedupLedger.markFired(alert)
                logger.info("\(monitor.monitorName): fired \(alert.dedupKey)")
            }
        }
    }
}
