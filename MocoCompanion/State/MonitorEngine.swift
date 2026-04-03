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

// MARK: - Monitor Engine

/// Runs all registered monitors, handles dedup, and dispatches notifications.
/// Single `stopAll()` for app termination.
@MainActor
final class MonitorEngine {
    private let logger = Logger(category: "MonitorEngine")
    private let dispatcher: NotificationDispatcher

    private var tasks: [ObjectIdentifier: Task<Void, Never>] = [:]
    private var dedupLedger = DedupLedger()
    /// Keep strong references to monitors so they aren't deallocated.
    private var monitors: [ObjectIdentifier: PollingMonitor] = [:]

    init(dispatcher: NotificationDispatcher) {
        self.dispatcher = dispatcher
    }

    /// Register and start polling a monitor.
    /// - Parameter immediateFirstCheck: If true, run the first check immediately instead of waiting for the poll interval.
    func register(_ monitor: PollingMonitor, immediateFirstCheck: Bool = false) {
        let id = ObjectIdentifier(monitor)
        tasks[id]?.cancel()
        monitors[id] = monitor

        tasks[id] = Task { [weak self] in
            guard let self else { return }
            self.logger.info("\(monitor.monitorName): started")

            // Optional immediate first check before entering the polling loop
            if immediateFirstCheck && monitor.isActive {
                let alerts = await monitor.check()
                for alert in alerts {
                    if self.dedupLedger.shouldFire(alert) {
                        self.dispatcher.send(alert.type, message: alert.message)
                        self.dedupLedger.markFired(alert)
                        self.logger.info("\(monitor.monitorName): fired \(alert.dedupKey)")
                    }
                }
            }

            while !Task.isCancelled {
                try? await Task.sleep(for: monitor.pollInterval)
                guard !Task.isCancelled else { break }

                guard monitor.isActive else { continue }

                let alerts = await monitor.check()
                for alert in alerts {
                    if self.dedupLedger.shouldFire(alert) {
                        self.dispatcher.send(alert.type, message: alert.message)
                        self.dedupLedger.markFired(alert)
                        self.logger.info("\(monitor.monitorName): fired \(alert.dedupKey)")
                    }
                }
            }
            self.logger.info("\(monitor.monitorName): stopped")
        }
    }

    /// Unregister a specific monitor.
    func unregister(_ monitor: PollingMonitor) {
        let id = ObjectIdentifier(monitor)
        tasks[id]?.cancel()
        tasks.removeValue(forKey: id)
        monitors.removeValue(forKey: id)
    }

    /// Reset dedup state for a specific monitor (e.g., new tracking session).
    func resetSession(for monitor: PollingMonitor) {
        monitor.resetSession()
        dedupLedger.clearPrefix(monitor.monitorName + ":")
    }

    /// Stop all monitors. Call from applicationWillTerminate.
    func stopAll() {
        tasks.values.forEach { $0.cancel() }
        tasks.removeAll()
        monitors.removeAll()
    }
}
