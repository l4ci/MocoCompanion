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

    private let now: @Sendable () -> Date
    private let sleep: @Sendable (TimeInterval) async throws -> Void

    init(
        limit: Int = 120,
        windowSeconds: TimeInterval = 120,
        safetyThreshold: Double = 0.85,
        now: @escaping @Sendable () -> Date = { .now },
        sleep: @escaping @Sendable (TimeInterval) async throws -> Void = {
            try await Task.sleep(for: .seconds($0))
        }
    ) {
        self.now = now
        self.sleep = sleep
        self.limit = limit
        self.windowSeconds = windowSeconds
        self.safetyThreshold = safetyThreshold
    }

    /// Wait and reserve a request slot atomically. Every wake-up rechecks both
    /// limits because other callers and Retry-After responses can run meanwhile.
    func waitForCapacity() async throws {
        while true {
            try Task.checkCancellation()
            let current = now()
            pruneOldTimestamps(at: current)

            if let retryDate = retryAfterDate, retryDate > current {
                try await sleep(retryDate.timeIntervalSince(current))
                continue
            }
            retryAfterDate = nil

            let threshold = max(1, Int(Double(limit) * safetyThreshold))
            if timestamps.count >= threshold, let oldest = timestamps.first {
                try await sleep(oldest.addingTimeInterval(windowSeconds).timeIntervalSince(current))
                continue
            }

            // No suspension between the capacity check and reservation.
            timestamps.append(current)
            return
        }
    }

    /// Record a Retry-After response from the server.
    func recordRetryAfter(seconds: Int?) {
        let delay = TimeInterval(seconds ?? 10) // Default 10s if no header
        let deadline = now().addingTimeInterval(delay)
        retryAfterDate = max(retryAfterDate ?? deadline, deadline)
        logger.warning("Rate gate: Retry-After set for \(delay)s")
    }

    /// Number of requests in the current window (for diagnostics).
    var currentWindowCount: Int {
        pruneOldTimestamps(at: now())
        return timestamps.count
    }

    /// Remove timestamps outside the sliding window.
    private func pruneOldTimestamps(at current: Date) {
        let cutoff = current.addingTimeInterval(-windowSeconds)
        timestamps.removeAll { $0 <= cutoff }
    }
}
