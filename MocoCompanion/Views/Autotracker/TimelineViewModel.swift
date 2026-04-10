import Foundation
import os

// MARK: - Timeline ViewModel

/// Drives the Autotracker timeline window: loads shadow entries and app records
/// for a selected date, merges app records into usage blocks, and segregates
/// entries by positioning status.
@Observable @MainActor final class TimelineViewModel {
    private static let logger = Logger(category: "TimelineViewModel")

    // MARK: - Dependencies

    private let shadowEntryStore: ShadowEntryStore
    let autotracker: Autotracker
    let syncState: SyncState
    let workdayStartHour: Int
    let workdayEndHour: Int
    /// Optional reference to the shared DeleteUndoManager so autotracker
    /// deletes route through the same 5-second undo flow used by the
    /// main popup's TodayView. Wired by AppDelegate when the window
    /// opens; nil in test harnesses that don't need undo.
    weak var deleteUndoManager: DeleteUndoManager?
    /// Optional reference to the SyncEngine so mutations can push to Moco immediately.
    /// Wired by AppDelegate when the window opens; nil in test harnesses.
    weak var syncEngine: SyncEngine?
    /// Called after entries are created/modified locally. Used to refresh the Today panel.
    var onEntryChanged: (() async -> Void)?
    /// Called when the user taps the refresh button. Triggers a full sync cycle.
    var onRefresh: (() async -> Void)?
    /// Whether a manual refresh is in progress.
    private(set) var isRefreshing: Bool = false

    // MARK: - Sync Passthrough

    /// Mirror of `syncState.lastSyncedAt` that forces the autotracker view
    /// to re-evaluate when the shared SyncState changes. Reading through
    /// an explicit computed property on this @Observable viewmodel ensures
    /// SwiftUI's observation tracker picks it up.
    ///
    /// Prefers the shared `SyncState.lastSyncedAt` (set by `SyncEngine.sync`
    /// on successful pull+push) and falls back to a local timestamp updated
    /// on every manual refresh — mirrors `TodayViewModel.lastSyncedAt` so
    /// the toolbar label stays accurate even before the first successful
    /// sync (e.g. during auth setup).
    var lastSyncedAt: Date? {
        syncState.lastSyncedAt ?? _lastSyncedAt
    }
    private var _lastSyncedAt: Date?

    var isSyncing: Bool {
        syncState.isSyncing
    }

    // MARK: - Published State

    var selectedDate: Date = Calendar.current.startOfDay(for: Date())
    private(set) var shadowEntries: [ShadowEntry] = []
    private(set) var appRecords: [AppRecord] = []
    /* internal for test */ var appUsageBlocks: [AppUsageBlock] = []
    private(set) var positionedEntries: [ShadowEntry] = []
    private(set) var unpositionedEntries: [ShadowEntry] = []
    private(set) var isLoading: Bool = false

    // MARK: - Selection State

    var selectedAppBlockIds: Set<String> = []
    /// The currently selected booked entry (by server id OR localId). `nil`
    /// when no entry is selected. Used by the UI to highlight the entry and
    /// any app usage blocks that overlap its time range (and vice versa).
    var selectedEntryKey: String? = nil

    // MARK: - Drag Creation State

    /// State describing an in-progress creation drag from app usage to entry column.
    struct DragCreationState {
        let sourceBlockIds: [String]
        let appName: String
        /// Bundle id of the first source block. Used as the origin link
        /// when an entry is created from this drag. Empty for drags that
        /// originated from empty timeline area.
        let appBundleId: String
        var startMinutes: Int
        var durationMinutes: Int
        var isOverlapping: Bool
    }

    var dragCreationState: DragCreationState?

    // MARK: - Init

    init(shadowEntryStore: ShadowEntryStore, autotracker: Autotracker, syncState: SyncState, workdayStartHour: Int = 8, workdayEndHour: Int = 17) {
        self.shadowEntryStore = shadowEntryStore
        self.autotracker = autotracker
        self.syncState = syncState
        self.workdayStartHour = workdayStartHour
        self.workdayEndHour = workdayEndHour
    }

    // MARK: - Data Loading

    func loadData() async {
        isLoading = true
        defer { isLoading = false }

        let dateString = TimelineGeometry.dateString(from: selectedDate)

        do {
            let entries = try await shadowEntryStore.entries(forDate: dateString)
            let filtered = entries.filter { $0.syncStatus != .pendingDelete }
            shadowEntries = filtered
            positionedEntries = filtered.filter { $0.startTime != nil }
            unpositionedEntries = filtered.filter { $0.startTime == nil }
        } catch {
            Self.logger.error("Failed to load shadow entries for \(dateString): \(error)")
            shadowEntries = []
            positionedEntries = []
            unpositionedEntries = []
        }

        let records = autotracker.records(for: selectedDate)
        appRecords = records
        appUsageBlocks = AppUsageBlock.merge(records)

        Self.logger.info("Loaded \(self.shadowEntries.count) entries, \(self.appUsageBlocks.count) usage blocks for \(dateString)")

        // Evaluate rules against loaded data
        let isTimerRunning = shadowEntries.contains { $0.timerStartedAt != nil }
        await autotracker.evaluate(for: selectedDate, existingEntries: shadowEntries, timerRunning: isTimerRunning)
    }

    // MARK: - Autotracker Passthrough

    var suggestions: [Suggestion] { autotracker.suggestions }

    func approveSuggestion(_ suggestion: Suggestion) async {
        await autotracker.approveSuggestion(suggestion)
        await loadData()
    }

    func declineSuggestion(_ suggestion: Suggestion) {
        autotracker.declineSuggestion(suggestion)
    }

    func approveAllSuggestions() async {
        await autotracker.approveAllSuggestions()
        await loadData()
    }

    // MARK: - Refresh

    func refreshData() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        await onRefresh?()
        await loadData()
        // Stamp the local fallback so the toolbar label keeps ticking
        // even when the upstream sync didn't succeed (e.g. offline).
        _lastSyncedAt = Date()
    }

    // MARK: - Date Navigation

    func selectPreviousDay() {
        let candidate = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate)!
        // Don't navigate past the autotracker retention window — there's
        // no data there anyway.
        let earliest = Calendar.current.startOfDay(for: autotracker.earliestRetainedDate)
        if candidate >= earliest {
            selectedDate = candidate
        }
    }

    /// True when the user can still navigate one day further into the past
    /// without crossing the retention boundary. Used to disable the left
    /// arrow button.
    var canSelectPreviousDay: Bool {
        let candidate = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate)!
        let earliest = Calendar.current.startOfDay(for: autotracker.earliestRetainedDate)
        return candidate >= earliest
    }

    func selectNextDay() {
        guard !isToday else { return }
        selectedDate = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate)!
    }

    func selectToday() {
        selectedDate = Calendar.current.startOfDay(for: Date())
    }

    func selectDate(_ date: Date) {
        selectedDate = Calendar.current.startOfDay(for: date)
    }

    var isToday: Bool {
        Calendar.current.isDateInToday(selectedDate)
    }

    // MARK: - Entry Mutation (Gestures)

    /// Move an entry to a new start time. Locked entries are rejected.
    func moveEntry(_ entry: ShadowEntry, toStartTime newStartTime: String) async {
        guard !entry.isReadOnly else { return }
        var updated = entry
        updated.startTime = newStartTime
        updated.localUpdatedAt = ISO8601DateFormatter().string(from: Date())
        do {
            if entry.id != nil {
                updated.syncStatus = .dirty
                try await shadowEntryStore.update(updated)
            } else if entry.localId != nil, entry.syncStatus == .pendingCreate {
                updated.syncStatus = .pendingCreate
                try await shadowEntryStore.updateByLocalId(updated)
            } else {
                return
            }
            Self.logger.info("Moved entry \(entry.id ?? 0) to \(newStartTime)")
            await loadData()
            await onEntryChanged?()
        } catch {
            Self.logger.error("Failed to move entry \(entry.id ?? 0): \(error)")
        }
    }

    /// Full entry update used by the edit sheet: project, task, description,
    /// date, start time, and duration all in one shot. Locked entries are
    /// rejected. `startTime` may be nil to unassign.
    func updateEntryFully(
        _ entry: ShadowEntry,
        projectId: Int,
        taskId: Int,
        projectName: String,
        taskName: String,
        customerName: String,
        description: String,
        date: String,
        startTime: String?,
        durationSeconds: Int
    ) async {
        guard !entry.isReadOnly else { return }
        var updated = entry
        updated.projectId = projectId
        updated.taskId = taskId
        updated.projectName = projectName
        updated.taskName = taskName
        updated.customerName = customerName
        updated.description = description
        updated.date = date
        updated.startTime = startTime
        updated.seconds = durationSeconds
        updated.hours = Double(durationSeconds) / 3600.0
        updated.localUpdatedAt = ISO8601DateFormatter().string(from: Date())
        do {
            if entry.id != nil {
                updated.syncStatus = .dirty
                try await shadowEntryStore.update(updated)
            } else if entry.localId != nil, entry.syncStatus == .pendingCreate {
                updated.syncStatus = .pendingCreate
                try await shadowEntryStore.updateByLocalId(updated)
            } else {
                return
            }
            Self.logger.info("Updated entry \(entry.id ?? 0): project=\(projectId) task=\(taskId) startTime=\(startTime ?? "nil") duration=\(durationSeconds)s")
            await loadData()
            await onEntryChanged?()
        } catch {
            Self.logger.error("Failed to update entry \(entry.id ?? 0): \(error)")
        }
    }

    /// Resize an entry by changing start time and/or duration. Locked entries are rejected.
    func resizeEntry(_ entry: ShadowEntry, newStartTime: String, newDurationSeconds: Int) async {
        guard !entry.isReadOnly else { return }
        var updated = entry
        updated.startTime = newStartTime
        updated.seconds = newDurationSeconds
        updated.hours = Double(newDurationSeconds) / 3600.0
        updated.localUpdatedAt = ISO8601DateFormatter().string(from: Date())
        do {
            if entry.id != nil {
                updated.syncStatus = .dirty
                try await shadowEntryStore.update(updated)
            } else if entry.localId != nil, entry.syncStatus == .pendingCreate {
                updated.syncStatus = .pendingCreate
                try await shadowEntryStore.updateByLocalId(updated)
            } else {
                return
            }
            Self.logger.info("Resized entry \(entry.id ?? 0) to \(newStartTime), \(newDurationSeconds)s")
            await loadData()
            await onEntryChanged?()
        } catch {
            Self.logger.error("Failed to resize entry \(entry.id ?? 0): \(error)")
        }
    }

    /// Delete an entry. Synced entries are marked pendingDelete for the sync engine
    /// to remove from Moco; local-only entries are deleted immediately.
    func deleteEntry(_ entry: ShadowEntry) async {
        guard !entry.isReadOnly else { return }

        // Prefer the shared DeleteUndoManager — it wraps the delete in
        // a 5-second undo window, marks the shadow row pendingDelete
        // (which this view's loadData filters out), and broadcasts the
        // change back so TodayView stays in sync. Falls back to the
        // direct store path for local-only rows (no server id yet) or
        // when no manager is wired in (tests).
        if let manager = deleteUndoManager, let serverId = entry.id {
            await manager.deleteActivity(activityId: serverId)
            // Local state is already updated via the manager's
            // onStoreChanged callback — no further work needed here.
            return
        }

        do {
            if let localId = entry.localId, entry.id == nil {
                // Local-only entry — remove directly
                try await shadowEntryStore.deleteByLocalId(localId)
            } else if entry.id != nil {
                var updated = entry
                updated.syncStatus = .pendingDelete
                updated.localUpdatedAt = ISO8601DateFormatter().string(from: Date())
                try await shadowEntryStore.update(updated)
            }
            Self.logger.info("Deleted entry \(entry.id ?? 0)")
            await loadData()
            await onEntryChanged?()
        } catch {
            Self.logger.error("Failed to delete entry \(entry.id ?? 0): \(error)")
        }
    }

    // MARK: - App Block Selection

    /// Toggle or replace block selection. Shift-click toggles within the set;
    /// plain click replaces the set (or clears if the block was the only selection).
    func toggleAppBlockSelection(id: String, shiftHeld: Bool) {
        if shiftHeld {
            if selectedAppBlockIds.contains(id) {
                selectedAppBlockIds.remove(id)
            } else {
                selectedAppBlockIds.insert(id)
            }
        } else {
            if selectedAppBlockIds == [id] {
                selectedAppBlockIds.removeAll()
            } else {
                selectedAppBlockIds = [id]
            }
        }
        // App-block selection is single-sourced with entry selection —
        // selecting an app block clears any selected entry.
        if !selectedAppBlockIds.isEmpty {
            selectedEntryKey = nil
        }
        Self.logger.debug("Selection changed: \(self.selectedAppBlockIds.count) blocks selected")
    }

    func clearAppBlockSelection() {
        selectedAppBlockIds.removeAll()
    }

    // MARK: - Entry Selection

    /// Unique key used to identify a ShadowEntry in selection state.
    /// Nonisolated so struct types (like EntryLayout) can call it from a
    /// synchronous context when computing their Identifiable id.
    nonisolated static func entryKey(for entry: ShadowEntry) -> String {
        if let id = entry.id {
            return "srv:\(id)"
        } else if let local = entry.localId {
            return "loc:\(local)"
        }
        return "x"
    }

    /// Click an entry to select it; click again to deselect. Selecting an
    /// entry also clears any app block selection to keep highlight
    /// semantics single-sourced.
    func toggleEntrySelection(_ entry: ShadowEntry) {
        let key = Self.entryKey(for: entry)
        if selectedEntryKey == key {
            selectedEntryKey = nil
        } else {
            selectedEntryKey = key
            selectedAppBlockIds.removeAll()
        }
    }

    func clearEntrySelection() {
        selectedEntryKey = nil
    }

    /// The currently selected entry, resolved from its key.
    var selectedEntry: ShadowEntry? {
        guard let key = selectedEntryKey else { return nil }
        return shadowEntries.first { Self.entryKey(for: $0) == key }
    }

    /// Returns true when the given entry is selected OR was created from
    /// an app that's currently selected. Origin-based: an entry lights
    /// up only if its `sourceAppBundleId` matches one of the selected
    /// app blocks.
    func isEntryHighlighted(_ entry: ShadowEntry) -> Bool {
        if selectedEntryKey == Self.entryKey(for: entry) { return true }
        guard !selectedAppBlockIds.isEmpty,
              let bundleId = entry.sourceAppBundleId, !bundleId.isEmpty
        else { return false }
        let selectedBundleIds = appUsageBlocks
            .filter { selectedAppBlockIds.contains($0.id) }
            .map(\.appBundleId)
        return selectedBundleIds.contains(bundleId)
    }

    /// Returns true when the given app block is selected OR an entry
    /// originating from this block's app is currently selected.
    func isAppBlockHighlighted(_ block: AppUsageBlock) -> Bool {
        if selectedAppBlockIds.contains(block.id) { return true }
        guard let entry = selectedEntry,
              let bundleId = entry.sourceAppBundleId, !bundleId.isEmpty
        else { return false }
        return bundleId == block.appBundleId
    }

    /// The subset of appUsageBlocks whose ids are in the selection set.
    var selectedAppBlocks: [AppUsageBlock] {
        appUsageBlocks.filter { selectedAppBlockIds.contains($0.id) }
    }

    /// Combined time range of selected blocks as minutes-since-midnight.
    /// Returns nil when nothing is selected.
    var combinedTimeRange: (startMinutes: Int, durationMinutes: Int)? {
        let blocks = selectedAppBlocks
        guard !blocks.isEmpty else { return nil }

        let calendar = Calendar.current
        var minMinutes = Int.max
        var maxMinutes = Int.min

        for block in blocks {
            let startComps = calendar.dateComponents([.hour, .minute], from: block.startTime)
            let endComps = calendar.dateComponents([.hour, .minute], from: block.endTime)
            let startMin = (startComps.hour ?? 0) * 60 + (startComps.minute ?? 0)
            let endMin = (endComps.hour ?? 0) * 60 + (endComps.minute ?? 0)
            minMinutes = min(minMinutes, startMin)
            maxMinutes = max(maxMinutes, endMin)
        }

        return (startMinutes: minMinutes, durationMinutes: maxMinutes - minMinutes)
    }

    // MARK: - Drag Creation Lifecycle

    /// Begin a creation drag from an app usage block. If the block is part of
    /// the current multi-selection, uses the combined range; otherwise uses
    /// the single block's time range.
    func startDragCreation(blockId: String) {
        let ids: [String]
        let blocks: [AppUsageBlock]

        if selectedAppBlockIds.contains(blockId), selectedAppBlockIds.count > 1 {
            ids = Array(selectedAppBlockIds)
            blocks = selectedAppBlocks
        } else {
            ids = [blockId]
            blocks = appUsageBlocks.filter { $0.id == blockId }
        }

        guard !blocks.isEmpty else { return }

        let calendar = Calendar.current
        var minMinutes = Int.max
        var maxMinutes = Int.min
        for block in blocks {
            let sc = calendar.dateComponents([.hour, .minute], from: block.startTime)
            let ec = calendar.dateComponents([.hour, .minute], from: block.endTime)
            let s = (sc.hour ?? 0) * 60 + (sc.minute ?? 0)
            let e = (ec.hour ?? 0) * 60 + (ec.minute ?? 0)
            minMinutes = min(minMinutes, s)
            maxMinutes = max(maxMinutes, e)
        }
        let duration = max(maxMinutes - minMinutes, TimelineLayout.snapMinutes)
        let appName = blocks.first?.appName ?? ""
        let bundleId = blocks.first?.appBundleId ?? ""

        let overlaps = !overlappingEntries(startMinutes: minMinutes, durationMinutes: duration).isEmpty
        dragCreationState = DragCreationState(
            sourceBlockIds: ids,
            appName: appName,
            appBundleId: bundleId,
            startMinutes: minMinutes,
            durationMinutes: duration,
            isOverlapping: overlaps
        )
        Self.logger.debug("Drag creation started: \(ids.count) blocks, \(duration)min")
    }

    /// Update the ghost block position during drag based on the cursor's y in
    /// the entry column coordinate space.
    func updateDragCreation(targetY: CGFloat) {
        guard dragCreationState != nil else { return }
        let rawMinutes = Double(targetY) / Double(TimelineLayout.pixelsPerMinute)
        let snapped = TimelineGeometry.snapToGrid(minutes: rawMinutes, gridMinutes: TimelineLayout.snapMinutes)
        let duration = dragCreationState!.durationMinutes
        let overlaps = !overlappingEntries(startMinutes: snapped, durationMinutes: duration).isEmpty
        dragCreationState?.startMinutes = snapped
        dragCreationState?.isOverlapping = overlaps
    }

    /// End the creation drag, returning the final state for sheet presentation.
    /// Returns nil if no drag was in progress.
    func endDragCreation() -> (startMinutes: Int, durationMinutes: Int, appName: String, sourceBundleId: String?)? {
        guard let state = dragCreationState else { return nil }
        dragCreationState = nil
        Self.logger.debug("Drag creation ended: \(state.startMinutes)min, \(state.durationMinutes)min duration")
        let bundle: String? = state.appBundleId.isEmpty ? nil : state.appBundleId
        return (startMinutes: state.startMinutes, durationMinutes: state.durationMinutes, appName: state.appName, sourceBundleId: bundle)
    }

    /// Cancel drag creation without producing a result.
    func cancelDragCreation() {
        dragCreationState = nil
    }

    /// Begin a drag-to-create on empty entry-column space. No source block —
    /// `sourceBlockIds` is empty so the view layer can distinguish this flow
    /// from the app-block drag if needed. Starts with a 5-minute ghost
    /// anchored at the clicked minute, which `extendEmptyAreaDrag` grows as
    /// the user drags down.
    func beginEmptyAreaDrag(atMinutes startMinutes: Int) {
        let snapped = TimelineGeometry.snapToGrid(
            minutes: Double(startMinutes),
            gridMinutes: TimelineLayout.snapMinutes
        )
        let duration = TimelineLayout.snapMinutes
        let overlaps = !overlappingEntries(
            startMinutes: snapped,
            durationMinutes: duration
        ).isEmpty
        dragCreationState = DragCreationState(
            sourceBlockIds: [],
            appName: "",
            appBundleId: "",
            startMinutes: snapped,
            durationMinutes: duration,
            isOverlapping: overlaps
        )
    }

    /// Extend an empty-area drag to `endMinutes`. Grows from the anchor
    /// downward — dragging upward past the anchor is clamped to the minimum
    /// snap interval (keeps the UX predictable).
    func extendEmptyAreaDrag(toMinutes endMinutes: Int) {
        guard let state = dragCreationState, state.sourceBlockIds.isEmpty else { return }
        let snapped = TimelineGeometry.snapToGrid(
            minutes: Double(endMinutes),
            gridMinutes: TimelineLayout.snapMinutes
        )
        let newEnd = max(state.startMinutes + TimelineLayout.snapMinutes, snapped)
        let newDuration = newEnd - state.startMinutes
        let overlaps = !overlappingEntries(
            startMinutes: state.startMinutes,
            durationMinutes: newDuration
        ).isEmpty
        dragCreationState?.durationMinutes = newDuration
        dragCreationState?.isOverlapping = overlaps
    }

    // MARK: - Entry Creation

    /// Create a new ShadowEntry from timeline drag-to-create. Inserts with
    /// syncStatus .pendingCreate and reloads data so it appears immediately.
    /// `sourceAppBundleId` records the recorded-activity origin so the
    /// timeline can show the new entry as linked to that app block.
    func createEntry(
        date: String,
        startTime: String,
        durationSeconds: Int,
        projectId: Int,
        taskId: Int,
        projectName: String,
        taskName: String,
        customerName: String,
        description: String,
        sourceAppBundleId: String? = nil
    ) async {
        let now = ISO8601DateFormatter().string(from: Date())

        // Try to inherit user fields from an existing entry on the same date
        let existingEntries = shadowEntries
        let userEntry = existingEntries.first

        let entry = ShadowEntry(
            id: nil,
            localId: UUID().uuidString,
            date: date,
            hours: Double(durationSeconds) / 3600.0,
            seconds: durationSeconds,
            workedSeconds: durationSeconds,
            description: description,
            billed: false,
            billable: true,
            tag: "",
            projectId: projectId,
            projectName: projectName,
            projectBillable: true,
            taskId: taskId,
            taskName: taskName,
            taskBillable: true,
            customerId: 0,
            customerName: customerName,
            userId: userEntry?.userId ?? 0,
            userFirstname: userEntry?.userFirstname ?? "",
            userLastname: userEntry?.userLastname ?? "",
            hourlyRate: userEntry?.hourlyRate ?? 0,
            timerStartedAt: nil,
            startTime: startTime,
            locked: false,
            createdAt: now,
            updatedAt: now,
            syncStatus: .pendingCreate,
            localUpdatedAt: now,
            serverUpdatedAt: now,
            conflictFlag: false,
            sourceAppBundleId: sourceAppBundleId,
            sourceRuleId: nil
        )

        do {
            try await shadowEntryStore.insert(entry)
            Self.logger.info("Entry created via timeline drag: \(startTime), \(durationSeconds)s, project \(projectId)")
            await loadData()
            await onEntryChanged?()
            // Push to Moco immediately so the local-only row gets a server ID
            if let engine = syncEngine {
                let dateStr = TimelineGeometry.dateString(from: selectedDate)
                await engine.sync(dates: [dateStr])
                await loadData()
            }
        } catch {
            Self.logger.error("Failed to create entry: \(error)")
        }
    }

    // MARK: - Stats

    /// Total tracked hours for the selected date (excluding pending deletes).
    var totalHours: Double { shadowEntries.totalHours }

    /// Billable percentage (0–100) for the selected date.
    var billablePercentage: Double { shadowEntries.billablePercentage }

    // MARK: - App Block Linkage

    /// Returns the display name of the app this entry was created from,
    /// resolved via the stored `sourceAppBundleId`. Returns nil for
    /// manually-typed entries.
    func linkedAppName(for entry: ShadowEntry) -> String? {
        guard let bundleId = entry.sourceAppBundleId, !bundleId.isEmpty else {
            return nil
        }
        return appUsageBlocks.first(where: { $0.appBundleId == bundleId })?.appName
    }

    /// Returns true if this entry was created FROM a recorded activity
    /// block (via right-click "Create entry from this block", drag-create
    /// from a block, or a matching TrackingRule). Origin-based — two
    /// entries simply standing next to each other in time are NOT linked.
    func isLinkedToAppBlock(_ entry: ShadowEntry) -> Bool {
        guard let bundleId = entry.sourceAppBundleId, !bundleId.isEmpty else {
            return false
        }
        // Only show the link badge when the originating app block is
        // still visible on the current day — otherwise the indicator is
        // meaningless for the user.
        return appUsageBlocks.contains { $0.appBundleId == bundleId }
    }

    // MARK: - Overlap Layout

    /// Layout descriptor for a single positioned entry. `columnIndex` is
    /// 0-based and `columnCount` is the total number of columns used by
    /// this entry's overlap cluster. A non-overlapping entry has
    /// `columnIndex == 0` and `columnCount == 1`.
    struct EntryLayout: Identifiable {
        let entry: ShadowEntry
        let columnIndex: Int
        let columnCount: Int
        var id: String { TimelineViewModel.entryKey(for: entry) }
    }

    /// Calendar-style column assignment for positioned entries. Groups
    /// transitively-overlapping entries into clusters and lays each
    /// cluster out into the smallest number of columns so that no two
    /// entries in the same column overlap in time. Entries in the same
    /// cluster share the same `columnCount` so their rendered widths line
    /// up.
    var positionedEntryLayouts: [EntryLayout] {
        struct Timed {
            let entry: ShadowEntry
            let start: Int
            let end: Int
        }

        let timed: [Timed] = positionedEntries.compactMap { entry in
            guard let ts = entry.startTime,
                  let start = TimelineGeometry.minutesSinceMidnight(from: ts)
            else { return nil }
            let end = start + max(entry.seconds / 60, 1)
            return Timed(entry: entry, start: start, end: end)
        }.sorted { lhs, rhs in
            if lhs.start != rhs.start { return lhs.start < rhs.start }
            return lhs.end > rhs.end
        }

        var result: [EntryLayout] = []
        var cluster: [Timed] = []
        var clusterEnd = Int.min

        func flushCluster() {
            guard !cluster.isEmpty else { return }
            var columnEnds: [Int] = []
            var assignments: [Int] = []
            for item in cluster {
                var placed = false
                for (i, end) in columnEnds.enumerated() where item.start >= end {
                    columnEnds[i] = item.end
                    assignments.append(i)
                    placed = true
                    break
                }
                if !placed {
                    assignments.append(columnEnds.count)
                    columnEnds.append(item.end)
                }
            }
            let count = max(columnEnds.count, 1)
            for (i, item) in cluster.enumerated() {
                result.append(EntryLayout(
                    entry: item.entry,
                    columnIndex: assignments[i],
                    columnCount: count
                ))
            }
            cluster.removeAll(keepingCapacity: true)
            clusterEnd = Int.min
        }

        for item in timed {
            if item.start >= clusterEnd {
                flushCluster()
            }
            cluster.append(item)
            clusterEnd = max(clusterEnd, item.end)
        }
        flushCluster()

        return result
    }

    // MARK: - Overlap Detection

    /// Returns positioned entries that overlap the proposed time range.
    /// Uses half-open interval comparison: two ranges overlap when
    /// `proposedStart < existingEnd && existingStart < proposedEnd`.
    func overlappingEntries(startMinutes: Int, durationMinutes: Int) -> [ShadowEntry] {
        let proposedEnd = startMinutes + durationMinutes
        return positionedEntries.filter { entry in
            guard let timeStr = entry.startTime,
                  let existingStart = TimelineGeometry.minutesSinceMidnight(from: timeStr) else {
                return false
            }
            let existingEnd = existingStart + (entry.seconds / 60)
            return startMinutes < existingEnd && existingStart < proposedEnd
        }
    }
}
