import Foundation
@testable import MocoCompanion

/// Test double for MonitorScheduler. Stores tick callbacks per monitor name
/// and lets tests fire them on demand — no real time required.
@MainActor
final class ManualMonitorScheduler: MonitorScheduler {
    private var callbacks: [String: @MainActor () async -> Void] = [:]
    private(set) var scheduledNames: [String] = []
    private(set) var immediateNames: [String] = []
    private(set) var cancelledNames: [String] = []
    private(set) var cancelAllCalled = false

    func schedule(_ monitor: any PollingMonitor, onTick: @escaping @MainActor () async -> Void) {
        callbacks[monitor.monitorName] = onTick
        scheduledNames.append(monitor.monitorName)
    }

    func scheduleImmediate(_ monitor: any PollingMonitor, onTick: @escaping @MainActor () async -> Void) {
        callbacks[monitor.monitorName] = onTick
        immediateNames.append(monitor.monitorName)
    }

    func cancelAll() {
        callbacks.removeAll()
        cancelAllCalled = true
    }

    func cancel(_ monitor: any PollingMonitor) {
        cancelledNames.append(monitor.monitorName)
        callbacks.removeValue(forKey: monitor.monitorName)
    }

    /// Fire one tick for the named monitor. The callback runs synchronously in the test's async context.
    func fire(monitorNamed name: String) async {
        await callbacks[name]?()
    }

    var registeredNames: [String] { Array(callbacks.keys) }
}
