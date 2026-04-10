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
    private let logger = Logger(subsystem: "com.mococompanion", category: "SyncEngine")

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
    func sync(dates: [String]) async {
        await MainActor.run { syncState.setSyncing(true) }
        defer { Task { @MainActor in syncState.setSyncing(false) } }

        do {
            for date in dates {
                try await pullRemote(date: date)
            }
            try await pushDirty()
            await MainActor.run {
                syncState.setLastSynced(Date())
                syncState.setLastError(nil)
            }
            let pending = try await store.dirtyEntries().count
            await MainActor.run { syncState.setPendingChanges(pending) }
        } catch {
            let mocoError = MocoError.from(error)
            await MainActor.run { syncState.setLastError(mocoError) }
            logger.error("Sync failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Pull

    /// Fetch remote activities for a date and merge into the local store.
    /// New entries are inserted, changed entries are updated, conflicts are flagged.
    /// Entries deleted on the server are removed locally.
    func pullRemote(date: String) async throws {
        guard let client = clientFactory() else { return }
        let userId = userIdProvider()

        let remoteActivities = try await client.fetchActivities(from: date, to: date, userId: userId)
        let remoteIds = Set(remoteActivities.map(\.id))

        var pullCount = 0
        var conflictCount = 0

        for activity in remoteActivities {
            let shadow = ShadowEntry.from(activity)
            let existing = try await store.entry(id: activity.id)

            if let existing {
                if existing.syncStatus == .dirty && existing.serverUpdatedAt != activity.updatedAt {
                    // Conflict: local is dirty and server changed — server wins
                    var resolved = shadow
                    resolved.conflictFlag = true
                    resolved.syncStatus = .synced
                    try await store.updateFromServer(resolved)
                    try await store.markConflict(id: activity.id)
                    conflictCount += 1
                } else if existing.syncStatus == .synced && existing.serverUpdatedAt != activity.updatedAt {
                    // Server updated a synced entry — just update
                    try await store.updateFromServer(shadow)
                    pullCount += 1
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
    }

    // MARK: - Push

    /// Push all dirty local entries to the API.
    func pushDirty() async throws {
        guard let client = clientFactory() else { return }

        let dirtyEntries = try await store.dirtyEntries()
        var pushCount = 0

        for entry in dirtyEntries {
            switch entry.syncStatus {
            case .pendingCreate:
                let created = try await client.createActivity(
                    date: entry.date,
                    projectId: entry.projectId,
                    taskId: entry.taskId,
                    description: entry.description,
                    seconds: entry.seconds,
                    tag: entry.tag.isEmpty ? nil : entry.tag
                )
                // Remove the local-only entry, insert with server ID
                if let localId = entry.localId {
                    try await store.deleteByLocalId(localId)
                }
                let serverShadow = ShadowEntry.from(created)
                try await store.insert(serverShadow)
                pushCount += 1

            case .dirty:
                guard let id = entry.id else { continue }
                let updated = try await client.updateActivity(
                    activityId: id,
                    description: entry.description,
                    tag: entry.tag.isEmpty ? nil : entry.tag,
                    seconds: entry.seconds
                )
                try await store.markSynced(id: id, serverUpdatedAt: updated.updatedAt)
                pushCount += 1

            case .pendingDelete:
                guard let id = entry.id else { continue }
                try await client.deleteActivity(activityId: id)
                try await store.delete(id: id)
                pushCount += 1

            case .synced:
                break
            }
        }

        logger.info("Push: \(pushCount) entries synced")
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

        let shadow = ShadowEntry.from(result)
        try await store.updateFromServer(shadow)
    }

    // MARK: - UI Convenience

    /// Query entries for a date, mapped to MocoActivity for the existing UI layer.
    func entriesForUI(date: String) async -> [MocoActivity] {
        do {
            let entries = try await store.entries(forDate: date)
            return entries.map { $0.toMocoActivity() }
        } catch {
            logger.error("entriesForUI failed: \(error.localizedDescription)")
            return []
        }
    }
}
