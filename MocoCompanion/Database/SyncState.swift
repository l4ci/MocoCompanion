import Foundation

/// Observable sync status for UI. Updated by SyncEngine on the MainActor.
@Observable @MainActor final class SyncState {

    private(set) var lastSyncedAt: Date?
    private(set) var isSyncing: Bool = false
    private(set) var pendingChanges: Int = 0
    private(set) var lastError: MocoError?

    /// Timestamp of the last Log view (panel) activity refresh.
    /// Persists across TodayView recreation (tab switches) so the
    /// 5-minute throttle works correctly.
    var lastPanelRefreshAt: Date?

    func setSyncing(_ value: Bool) {
        isSyncing = value
    }

    func setLastSynced(_ date: Date) {
        lastSyncedAt = date
    }

    func setPendingChanges(_ count: Int) {
        pendingChanges = count
    }

    func setLastError(_ error: MocoError?) {
        lastError = error
    }
}
