import Foundation
import Network
import os

/// Monitors network connectivity using NWPathMonitor.
/// Publishes `isOnline` as an observable property for UI binding.
@Observable
@MainActor
final class NetworkMonitor {
    private let logger = Logger(category: "Network")
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.mococompanion.networkmonitor")

    /// Whether the device currently has network connectivity.
    private(set) var isOnline: Bool = true

    /// Callback fired when connectivity is restored (transitions from offline → online).
    var onReconnect: (() async -> Void)?

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let wasOffline = !self.isOnline
                self.isOnline = path.status == .satisfied

                if wasOffline && self.isOnline {
                    self.logger.info("Network restored — triggering reconnect")
                    await self.onReconnect?()
                } else if !self.isOnline {
                    self.logger.info("Network lost — entering offline mode")
                }
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
