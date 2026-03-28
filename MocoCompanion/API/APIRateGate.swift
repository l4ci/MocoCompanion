import Foundation
import os

/// Tracks API request timestamps and enforces rate limits by delaying
/// requests that would exceed the allowed window.
///
/// Moco API limits: 120 requests per 2 minutes (standard), 1200 per 2 minutes (unlimited).
/// The gate uses a sliding window to track recent requests and delays when approaching the limit.
actor APIRateGate {
    private let logger = Logger(category: "RateGate")

    /// Maximum requests allowed in the window.
    let limit: Int
    /// Window duration in seconds.
    let windowSeconds: TimeInterval
    /// Safety margin — start delaying when this fraction of the limit is used.
    let safetyThreshold: Double

    /// Timestamps of recent requests within the current window.
    private var timestamps: [Date] = []
    /// If set, all requests are delayed until this date (from Retry-After header).
    private var retryAfterDate: Date?

    init(limit: Int = 120, windowSeconds: TimeInterval = 120, safetyThreshold: Double = 0.85) {
        self.limit = limit
        self.windowSeconds = windowSeconds
        self.safetyThreshold = safetyThreshold
    }

    /// Wait until it's safe to make a request. Returns immediately if under the threshold.
    func waitForCapacity() async {
        // Respect Retry-After if set
        if let retryDate = retryAfterDate {
            let delay = retryDate.timeIntervalSinceNow
            if delay > 0 {
                logger.info("Rate gate: waiting \(String(format: "%.1f", delay))s for Retry-After")
                try? await Task.sleep(for: .seconds(delay))
            }
            retryAfterDate = nil
        }

        pruneOldTimestamps()

        let threshold = Int(Double(limit) * safetyThreshold)
        if timestamps.count >= threshold {
            // Calculate how long to wait until the oldest request exits the window
            guard let oldest = timestamps.first else { return }
            let waitUntil = oldest.addingTimeInterval(windowSeconds)
            let delay = waitUntil.timeIntervalSinceNow
            if delay > 0 {
                let count = self.timestamps.count
                let max = self.limit
                logger.info("Rate gate: \(count)/\(max) requests in window, delaying \(String(format: "%.1f", delay))s")
                try? await Task.sleep(for: .seconds(min(delay, 5))) // Cap at 5s to avoid long stalls
            }
        }
    }

    /// Record that a request was made.
    func recordRequest() {
        timestamps.append(Date())
    }

    /// Record a Retry-After response from the server.
    func recordRetryAfter(seconds: Int?) {
        let delay = TimeInterval(seconds ?? 10) // Default 10s if no header
        retryAfterDate = Date().addingTimeInterval(delay)
        logger.warning("Rate gate: Retry-After set for \(delay)s")
    }

    /// Number of requests in the current window (for diagnostics).
    var currentWindowCount: Int {
        pruneOldTimestamps()
        return timestamps.count
    }

    /// Remove timestamps outside the sliding window.
    private func pruneOldTimestamps() {
        let cutoff = Date().addingTimeInterval(-windowSeconds)
        timestamps.removeAll { $0 < cutoff }
    }
}
