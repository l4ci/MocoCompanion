import Foundation
import os

/// Orchestrates bidirectional sync between ShadowEntryStore and the Moco API.
/// Pull merges remote activities into the local shadow DB. Push sends dirty entries upstream.
/// Server-wins conflict resolution: dirty local entries overwritten by server version with conflictFlag=1.
actor SyncEngine {

    private let store: ShadowEntryStore
    private let clientFactory: () -> (any ActivityAPI & TimerAPI)?
    private let userIdProvider: () -> Int?
    private let syncState: SyncState
    /// Called when a validation error indicates the Moco instance requires descriptions.
    nonisolated(unsafe) var onDescriptionRequired: (() -> Void)?
    private let logger = Logger(category: "SyncEngine")
    nonisolated(unsafe) private static let isoFormatter = ISO8601DateFormatter()

    // MARK: - Reentrancy guard
    //
    // `sync(dates:)` has five call sites (AppDelegate's 300s periodic timer,
    // ActivityService, TimelineViewModel, AppDelegate's background poll) that
    // can fire concurrently. Because the actor suspends across awaits inside
    // `pullRemote`/`pushDirty`, two overlapping calls could both read the same
    // `.pendingCreate` row before either has written it back with a server ID,
    // producing a duplicate `createActivity`. Rather than dropping a request
    // that arrives while a cycle is in flight, we coalesce it: the requested
    // dates are folded into `pendingDates`, and the in-flight drain task keeps
    // running cycles for the accumulated union until nothing new arrived.
    // Late callers await that same task, so `await sync(dates:)` still means
    // "my dates have been synced" when it returns.
    private var pendingDates: Set<String> = []
    private var drainTask: Task<Void, Error>?
    private var pendingPush = false
    // Keep successful POST receipts until their local transaction commits.
    // A transient SQLite failure must retry promotion, not create remotely again.
    private var pendingPromotions: [String: (sent: ShadowEntry, response: MocoActivity)] = [:]

    init(
        store: ShadowEntryStore,
        clientFactory: @escaping () -> (any ActivityAPI & TimerAPI)?,
        userIdProvider: @escaping () -> Int?,
        syncState: SyncState
    ) {
        self.store = store
        self.clientFactory = clientFactory
        self.userIdProvider = userIdProvider
        self.syncState = syncState
    }

    // MARK: - Full Sync Cycle

    /// Run a complete pull+push sync for the given dates.
    ///
    /// If a cycle is already in flight, `dates` is merged into `pendingDates`
    /// and this call awaits the in-flight drain, which runs follow-up cycles
    /// until the accumulated set (including these dates) is empty.
    func sync(dates: [String]) async {
        do { try await enqueueSync(dates: dates) } catch { /* cycle recorded the error */ }
    }

    private func enqueueSync(dates: [String]) async throws {
        pendingDates.formUnion(dates)
        pendingPush = true
        if let task = drainTask {
            try await task.value
            return
        }
        let task = Task<Void, Error> {
            var lastError: Error?
            while pendingPush || !pendingDates.isEmpty {
                let dates = pendingDates.sorted()
                pendingDates.removeAll()
                pendingPush = false
                do { try await runSyncCycle(dates: dates) }
                catch { lastError = error }
            }
            drainTask = nil
            if let lastError { throw lastError }
        }
        drainTask = task
        try await task.value
    }

    /// One pull+push cycle for the given dates. Broken out of `sync(dates:)`
    /// so the reentrancy guard/coalescing loop can drive multiple cycles.
    private func runSyncCycle(dates: [String]) async throws {
        BreadcrumbTrail.shared.record("SyncEngine", "Sync started for dates: \(dates.joined(separator: ", "))")
        await MainActor.run { syncState.setSyncing(true) }
        defer { Task { @MainActor in syncState.setSyncing(false) } }

        do {
            for date in dates {
                try await pullRemote(date: date)
            }
            try await pushDirtyWorker()
            await MainActor.run {
                syncState.setLastSynced(Date.now)
                syncState.setLastError(nil)
            }
            let pending = try await store.dirtyEntries().count
            BreadcrumbTrail.shared.record("SyncEngine", "Sync completed: \(dates.count) dates, \(pending) pending")
            await MainActor.run { syncState.setPendingChanges(pending) }
        } catch {
            let mocoError = MocoError.from(error)
            await MainActor.run { syncState.setLastError(mocoError) }
            // Auto-detect "description required" from Moco validation errors
            if case .validationError(let message) = mocoError,
               message.localizedLowercase.contains("description") {
                onDescriptionRequired?()
            }
            logger.error("Sync failed: \(error.localizedDescription)")
            BreadcrumbTrail.shared.record("SyncEngine", "Sync failed: \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - Pull

    /// Fetch remote activities for a date and merge into the local store.
    /// New entries are inserted, changed entries are updated, conflicts are flagged.
    /// Entries deleted on the server are removed locally.
    func pullRemote(date: String) async throws {
        guard let client = clientFactory() else { return }
        guard let userId = userIdProvider() else {
            logger.info("pullRemote skipped — userId not available yet")
            return
        }

        let remoteActivities = try await client.fetchActivities(from: date, to: date, userId: userId)
        let remoteIds = Set(remoteActivities.map(\.id))

        var pullCount = 0
        var conflictCount = 0

        for activity in remoteActivities {
            let shadow = ShadowEntry.from(activity)
            let existing = try await store.entry(id: activity.id)

            if let existing {
                if existing.sync.status == .dirty && existing.sync.serverUpdatedAt != activity.updatedAt {
                    // Conflict: local is dirty and server changed — server wins
                    var resolved = shadow
                    resolved.sync.conflictFlag = true
                    resolved.sync.status = .synced
                    if try await store.updateFromServer(resolved, expectedRevision: existing.sync.revision) {
                        conflictCount += 1
                    }
                } else if existing.sync.status == .synced && existing.sync.serverUpdatedAt != activity.updatedAt {
                    // Server updated a synced entry — just update
                    if try await store.updateFromServer(shadow, expectedRevision: existing.sync.revision) {
                        pullCount += 1
                    }
                }
                // If updatedAt matches, skip — no change
            } else {
                // New entry from server
                try await store.insert(shadow)
                pullCount += 1
            }
        }

        // Remove entries deleted on the server (only synced ones)
        try await store.removeServerDeleted(keepingIds: remoteIds, forDate: date)

        logger.info("Pull \(date): \(pullCount) updated, \(conflictCount) conflicts")
        BreadcrumbTrail.shared.record("SyncEngine", "Pull \(date): \(pullCount) updated, \(conflictCount) conflicts")
    }

    // MARK: - Push

    /// Push all dirty local entries to the API.
    func pushDirty() async throws {
        try await enqueueSync(dates: [])
    }

    private func pushDirtyWorker() async throws {
        guard let client = clientFactory() else { return }

        let dirtyEntries = try await store.dirtyEntries()
        var pushCount = 0
        var failedCount = 0
        var lastError: Error?

        for (localId, promotion) in pendingPromotions {
            do {
                _ = try await store.promoteDraft(sent: promotion.sent, response: promotion.response)
                pendingPromotions.removeValue(forKey: localId)
                pendingPush = true
                pushCount += 1
            } catch {
                lastError = error
                failedCount += 1
            }
        }

        for entry in dirtyEntries {
            if let localId = entry.localId, pendingPromotions[localId] != nil { continue }
            do {
                // A row with neither server id nor local id can never become
                // eligible. Re-arming the drain for it would spin forever.
                guard entry.id != nil || entry.localId != nil else {
                    logger.error("Skipping unsyncable row without id or localId (status=\(String(describing: entry.sync.status)))")
                    continue
                }
                guard try await store.isUploadEligible(entry) else {
                    pendingPush = true
                    continue
                }
                switch entry.sync.status {
                case .pendingCreate:
                    let created = try await client.createActivity(
                        date: entry.date,
                        projectId: entry.projectId,
                        taskId: entry.taskId,
                        description: entry.description,
                        seconds: entry.seconds,
                        tag: entry.tag.isEmpty ? nil : entry.tag
                    )
                    if let localId = entry.localId { pendingPromotions[localId] = (entry, created) }
                    if try await store.promoteDraft(sent: entry, response: created) { pendingPush = true }
                    if let localId = entry.localId { pendingPromotions.removeValue(forKey: localId) }
                    pushCount += 1

                case .dirty:
                    guard let id = entry.id else { continue }
                    let updated = try await client.updateActivity(
                        activityId: id,
                        projectId: entry.projectId,
                        taskId: entry.taskId,
                        description: entry.description,
                        tag: entry.tag.isEmpty ? nil : entry.tag,
                        seconds: entry.seconds
                    )
                    if try await store.acknowledgeUpdate(sent: entry, response: updated) { pendingPush = true }
                    pushCount += 1

                case .pendingDelete:
                    guard let id = entry.id else { continue }
                    do {
                        try await client.deleteActivity(activityId: id)
                        try await store.delete(id: id)
                        pushCount += 1
                    } catch let error as MocoError where error.isNotFound {
                        // 404 — already deleted on server, clean up locally.
                        logger.info("Delete \(id): not found on server — removing local row")
                        try await store.delete(id: id)
                        pushCount += 1
                    } catch let error as MocoError where error.isForbidden {
                        // 403 — locked/billed, can't delete. Revert to synced
                        // so the entry stays visible as read-only.
                        logger.info("Delete \(id): forbidden (locked/billed) — reverting to synced")
                        try await store.rejectDelete(sent: entry)
                    }

                case .synced:
                    break
                }
            } catch {
                logger.warning("Push failed for entry (status=\(String(describing: entry.sync.status))): \(error.localizedDescription)")
                lastError = error
                failedCount += 1
                continue
            }
        }

        if failedCount > 0 && pushCount == 0, let lastError {
            logger.error("Push: all \(failedCount) entries failed")
            throw lastError
        } else if failedCount > 0 {
            logger.warning("Push: \(pushCount) synced, \(failedCount) failed (will retry on next sync)")
        } else {
            logger.info("Push: \(pushCount) entries synced")
        }
        BreadcrumbTrail.shared.record("SyncEngine", "Push: \(pushCount) synced, \(failedCount) failed")
    }

    // MARK: - Timer

    /// Start or stop a timer on a remote activity and update the local shadow.
    func syncTimer(activityId: Int, start: Bool) async throws {
        guard let client = clientFactory() else { return }

        let result: MocoActivity
        if start {
            result = try await client.startTimer(activityId: activityId)
        } else {
            result = try await client.stopTimer(activityId: activityId)
        }

        try await store.mergeFetchedActivity(result)
    }

    func reconcileTimerSnapshot(_ activities: [MocoActivity], forDate date: String) async throws -> [ShadowEntry] {
        try await store.reconcileTimerSnapshot(activities, forDate: date)
    }

    // MARK: - UI Convenience

    // MARK: - Entry Mutation

    /// Update specific fields on a synced entry, mark it dirty, and push immediately.
    func updateEntry(
        id: Int,
        projectId: Int? = nil,
        taskId: Int? = nil,
        description: String? = nil,
        tag: String? = nil,
        seconds: Int? = nil
    ) async throws {
        guard var entry = try await store.entry(id: id) else {
            logger.warning("updateEntry: entry \(id) not found in store")
            return
        }
        if let projectId { entry.projectId = projectId }
        if let taskId { entry.taskId = taskId }
        if let description { entry.description = description }
        if let tag { entry.tag = tag }
        if let seconds {
            entry.seconds = seconds
            entry.workedSeconds = seconds
            entry.hours = Double(seconds) / 3600.0
        }
        entry.sync.status = .dirty
        entry.sync.localUpdatedAt = Self.isoFormatter.string(from: Date.now)
        try await store.update(entry)
        try await pushDirty()
    }

    // MARK: - Read Helpers

    /// Insert an already-synced entry (created via API elsewhere) into the local store
    /// so the autotracker timeline reflects it without waiting for the next periodic sync.
    func insertSynced(_ entry: ShadowEntry) async throws {
        try await store.insert(entry)
    }

    /// Insert a local-only draft with `sync.status == .pendingCreate` — a booking
    /// made while offline. The row shows up immediately in the shadow store (and
    /// therefore the UI) and is pushed to Moco by the next `pushDirty()`, exactly
    /// like an Autotracker create-mode row. Recomputes `syncState.pendingChanges`
    /// from the store so the offline banner reflects the new row immediately
    /// instead of waiting for the next sync cycle.
    func insertPendingCreate(_ entry: ShadowEntry) async throws {
        try await store.insert(entry)
        let pending = try await store.dirtyEntries().count
        await MainActor.run { syncState.setPendingChanges(pending) }
    }

    /// Sync the given date and return entries mapped to MocoActivity.
    /// Sync the given date and return entries from the local store.
    func refresh(date: String) async -> [ShadowEntry] {
        await sync(dates: [date])
        return await entries(forDate: date)
    }

    /// Query entries for a date from the local store.
    func entries(forDate date: String) async -> [ShadowEntry] {
        do {
            return try await store.entries(forDate: date)
        } catch {
            logger.error("entries(forDate:) failed: \(error.localizedDescription)")
            await syncState.setLastError(MocoError.from(error))
            return []
        }
    }
}
