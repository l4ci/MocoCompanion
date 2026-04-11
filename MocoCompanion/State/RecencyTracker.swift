import Foundation
import os

/// Tracks which projects were recently used to boost their ranking in search.
/// Stores projectId → lastUsedDate in UserDefaults as JSON.
@Observable
@MainActor
final class RecencyTracker {
    private static let logger = Logger(category: "Recency")
    /// Number of days after which recency score decays to zero.
    private static let decayDays: Double = 14

    private let state: PersistedState<[String: TimeInterval]>

    /// projectId → last used date (decoded from storage on init)
    private(set) var usageMap: [Int: Date] = [:]

    /// Trailing-debounce persistence so a burst of usage events writes
    /// UserDefaults once, not N times. Every usage reschedules the flush
    /// for `persistDebounce` in the future; the final event wins.
    private var persistTask: Task<Void, Never>?
    private let persistDebounce: Duration = .seconds(2)

    init(backend: StorageBackend = DefaultsBackend()) {
        self.state = PersistedState(key: "projectRecency", default: [:], backend: backend)
        usageMap = Self.decode(state.value)
    }

    // MARK: - Public API

    /// Record that a project was just used.
    func recordUsage(projectId: Int) {
        usageMap[projectId] = Date()
        schedulePersist()
        Self.logger.info("Recorded usage for project \(projectId)")
    }

    /// Force an immediate flush of pending state. Call from
    /// `applicationWillTerminate` so no recorded usage is lost.
    func flushPendingWrites() {
        persistTask?.cancel()
        persistTask = nil
        persist()
    }

    /// Get a recency score for a project (0.0–1.0).
    /// 1.0 = used today, decays linearly to 0 over `decayDays`.
    func recencyScore(projectId: Int) -> Double {
        guard let lastUsed = usageMap[projectId] else { return 0 }
        let daysSince = -lastUsed.timeIntervalSinceNow / 86400
        guard daysSince < Self.decayDays else { return 0 }
        return max(0, 1.0 - daysSince / Self.decayDays)
    }

    /// Build a projectId → score dictionary for passing to FuzzyMatcher.
    func allScores() -> [Int: Double] {
        var scores: [Int: Double] = [:]
        for (projectId, _) in usageMap {
            let s = recencyScore(projectId: projectId)
            if s > 0 {
                scores[projectId] = s
            }
        }
        return scores
    }

    // MARK: - Private

    /// Schedule `persist()` after `persistDebounce`, cancelling any
    /// previously-scheduled flush.
    private func schedulePersist() {
        persistTask?.cancel()
        let delay = persistDebounce
        persistTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            self.persist()
        }
    }

    private func persist() {
        // Prune entries older than decayDays before saving
        let cutoff = Date().addingTimeInterval(-Self.decayDays * 86400)
        let pruned = usageMap.filter { $0.value > cutoff }
        if pruned.count < usageMap.count {
            Self.logger.info("Pruned \(self.usageMap.count - pruned.count) stale recency entries")
            usageMap = pruned
        }

        // Encode as [String: TimeInterval] for JSON compatibility
        let encoded = usageMap.reduce(into: [String: TimeInterval]()) { dict, pair in
            dict[String(pair.key)] = pair.value.timeIntervalSince1970
        }
        state.set(encoded)
    }

    private static func decode(_ raw: [String: TimeInterval]) -> [Int: Date] {
        raw.reduce(into: [Int: Date]()) { dict, pair in
            if let id = Int(pair.key) {
                dict[id] = Date(timeIntervalSince1970: pair.value)
            }
        }
    }
}
