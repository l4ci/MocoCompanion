import Foundation
import os

// MARK: - Timeline ViewModel

/// Drives the Autotracker timeline window: loads shadow entries and app records
/// for a selected date, merges app records into usage blocks, and segregates
/// entries by positioning status.
@Observable @MainActor final class TimelineViewModel {
    private static let logger = Logger(category: "TimelineViewModel")
    private static let isoFormatter = ISO8601DateFormatter()

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
    /// Optional reference to the SettingsStore so `loadData` can honor the
    /// `calendarEnabled` toggle and `selectedCalendarId` without threading
    /// them through every call. Wired by AppDelegate; nil in test harnesses.
    weak var settings: SettingsStore?
    /// Optional reference to the shared CalendarService. Weak because
    /// AppState owns both the view model and the service — we don't want
    /// a retain cycle if the VM ever outlives the window. Nil in test
    /// harnesses that don't exercise calendar fetches.
    weak var calendarService: CalendarService?
    /// Optional reference to PlanningStore for absence data. Wired by
    /// AppDelegate; nil in test harnesses.
    weak var planningStore: PlanningStore?
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

    // MARK: - Date Metadata

    /// Whether the selected date falls on a weekend (Saturday or Sunday).
    var isWeekend: Bool {
        Calendar.current.isDateInWeekend(selectedDate)
    }

    /// Absence (vacation, sick day, holiday, etc.) for the selected date, if any.
    var absence: MocoSchedule? {
        planningStore?.absence(for: TimelineGeometry.dateString(from: selectedDate))
    }

    // MARK: - Published State

    var selectedDate: Date = Calendar.current.startOfDay(for: Date.now)
    private(set) var shadowEntries: [ShadowEntry] = []
    private(set) var appRecords: [AppRecord] = []
    /* internal for test */ var appUsageBlocks: [AppUsageBlock] = []
    private(set) var timeSlots: [TimeSlot] = []
    private(set) var positionedEntries: [ShadowEntry] = []
    private(set) var unpositionedEntries: [ShadowEntry] = []
    private(set) var calendarEvents: [CalendarEvent] = []
    private(set) var isLoading: Bool = false

    // MARK: - Calendar Event Layouts

    /// Layout descriptor for a single timed calendar event. Parallels
    /// `EntryLayout` for the entry column. `columnIndex` is 0-based and
    /// `columnCount` is the total number of columns used by this event's
    /// overlap cluster.
    struct CalendarEventLayout: Identifiable {
        let event: CalendarEvent
        let columnIndex: Int
        let columnCount: Int
        var id: String { event.id }
    }

    /// Timed events laid out with cluster/column assignment. All-day
    /// events are excluded — they're surfaced via `allDayEvents` for
    /// the aboveline region instead.
    private(set) var calendarEventLayouts: [CalendarEventLayout] = []

    /// All-day events for the current day. Rendered in the aboveline
    /// region of the calendar column (not positioned on the timeline).
    private(set) var allDayEvents: [CalendarEvent] = []

    private func recomputeCalendarLayouts() {
        let timed: [(event: CalendarEvent, start: Int, end: Int)] = calendarEvents.compactMap { ev in
            guard !ev.isAllDay, let start = ev.startMinutes else { return nil }
            let end = start + max(ev.durationMinutes, 1)
            return (ev, start, end)
        }
        let assignments = ClusterColumns.assign(timed.map { ($0.start, $0.end) })
        calendarEventLayouts = zip(timed, assignments).map { item, a in
            CalendarEventLayout(event: item.event, columnIndex: a.columnIndex, columnCount: a.columnCount)
        }
        allDayEvents = calendarEvents.filter { $0.isAllDay }
    }

    // MARK: - Selection State

    var selectedAppBlockIds: Set<String> = []
    /// The currently selected booked entry (by server id OR localId). `nil`
    /// when no entry is selected. Used by the UI to highlight the entry and
    /// any app usage blocks that overlap its time range (and vice versa).
    var selectedEntryKey: String? = nil

    /// The currently selected calendar event, keyed by
    /// `calendarItemIdentifier`. Nil when no event is selected. Selecting
    /// a calendar event clears app-block and entry selection so the
    /// highlight single-sources match app-block selection semantics.
    var selectedCalendarEventId: String? = nil

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

    /// Anchor minute for an empty-area drag-to-create. Set on
    /// `beginEmptyAreaDrag` and used by `extendEmptyAreaDrag` so the
    /// block can grow in either direction from this fixed point.
    private var dragCreationAnchorMinutes: Int?

    // MARK: - Gesture Preview (move + resize)

    /// Live preview for an in-flight drag-move or edge-resize gesture.
    /// While active, the EntryBlockView whose key matches the preview's
    /// `entryKey` hides itself and the timeline draws a ghost block at
    /// the preview coordinates instead.
    var gesturePreview: TimelineGesturePreview = .init()

    /// Convenience accessor kept for views that read individual preview
    /// fields directly — returns the active state or `nil` when idle.
    var gesturePreviewState: TimelineGesturePreview.ActiveState? {
        gesturePreview.activeState
    }

    /// Begin a gesture preview for the given entry. Captures the entry's
    /// current column slot so the ghost lines up with its real position
    /// inside an overlap cluster.
    func beginGesturePreview(for entry: ShadowEntry, startMinutes: Int, durationMinutes: Int) {
        let key = Self.entryKey(for: entry)
        let layout = positionedEntryLayouts.first { $0.id == key }
        gesturePreview.begin(
            entryKey: key,
            startMinutes: startMinutes,
            durationMinutes: durationMinutes,
            columnIndex: layout?.columnIndex ?? 0,
            columnCount: layout?.columnCount ?? 1
        )
    }

    func updateGesturePreview(startMinutes: Int, durationMinutes: Int) {
        gesturePreview.update(startMinutes: startMinutes, durationMinutes: durationMinutes)
    }

    func clearGesturePreview() {
        gesturePreview.clear()
    }

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
            let filtered = entries.filter { $0.sync.status != .pendingDelete }
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
        timeSlots = TimeSlot.aggregate(records)

        // Calendar events — only fetched when the feature is enabled and
        // a calendar is picked. `requestAccessIfNeeded` is idempotent and
        // cheap when access is already established.
        if settings?.calendarEnabled == true, let svc = calendarService {
            _ = await svc.requestAccessIfNeeded()
            if svc.hasReadAccess, let calId = settings?.selectedCalendarId {
                calendarEvents = svc.fetchEvents(for: selectedDate, selectedCalendarId: calId)
            } else {
                calendarEvents = []
            }
        } else {
            calendarEvents = []
        }
        recomputeCalendarLayouts()

        Self.logger.info("Loaded \(self.shadowEntries.count) entries, \(self.timeSlots.count) time slots, \(self.calendarEvents.count) calendar events for \(dateString)")

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
        _lastSyncedAt = Date.now
    }

    // MARK: - Date Navigation

    func selectPreviousDay() {
        guard let candidate = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) else { return }
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
        guard let candidate = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) else { return false }
        let earliest = Calendar.current.startOfDay(for: autotracker.earliestRetainedDate)
        return candidate >= earliest
    }

    func selectNextDay() {
        guard !isToday else { return }
        guard let next = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) else { return }
        selectedDate = next
    }

    func selectToday() {
        selectedDate = Calendar.current.startOfDay(for: Date.now)
    }

    func selectDate(_ date: Date) {
        selectedDate = Calendar.current.startOfDay(for: date)
    }

    var isToday: Bool {
        Calendar.current.isDateInToday(selectedDate)
    }

    // MARK: - Entry Mutation (Gestures)

    /// Persist a mutated entry to the store, reload data, and push to Moco.
    /// Handles both synced entries (mark dirty) and local-only pendingCreate entries.
    private func persistMutation(_ original: ShadowEntry, _ updated: ShadowEntry, label: String) async throws {
        if original.id != nil {
            var entry = updated
            entry.sync.status = .dirty
            try await shadowEntryStore.update(entry)
        } else if original.localId != nil, original.sync.status == .pendingCreate {
            var entry = updated
            entry.sync.status = .pendingCreate
            try await shadowEntryStore.updateByLocalId(entry)
        } else {
            return
        }
        Self.logger.info("\(label)")
        await loadData()
        await onEntryChanged?()
        await syncEngine?.sync(dates: [updated.date])
        await loadData()
    }

    /// Move an entry to a new start time. Locked entries are rejected.
    func moveEntry(_ entry: ShadowEntry, toStartTime newStartTime: String) async {
        guard !entry.isReadOnly else { return }
        var updated = entry
        updated.startTime = newStartTime
        updated.sync.localUpdatedAt = Self.isoFormatter.string(from: Date.now)
        do {
            try await persistMutation(entry, updated, label: "Moved entry \(entry.id ?? 0) to \(newStartTime)")
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
        updated.sync.localUpdatedAt = Self.isoFormatter.string(from: Date.now)
        do {
            try await persistMutation(entry, updated, label: "Updated entry \(entry.id ?? 0): project=\(projectId) task=\(taskId) startTime=\(startTime ?? "nil") duration=\(durationSeconds)s")
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
        updated.sync.localUpdatedAt = Self.isoFormatter.string(from: Date.now)
        do {
            try await persistMutation(entry, updated, label: "Resized entry \(entry.id ?? 0) to \(newStartTime), \(newDurationSeconds)s")
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
                updated.sync.status = .pendingDelete
                updated.sync.localUpdatedAt = Self.isoFormatter.string(from: Date.now)
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
        // App-block selection is single-sourced with entry and
        // calendar-event selection — selecting an app block clears any
        // other active selection so the accent highlight means one thing.
        if !selectedAppBlockIds.isEmpty {
            selectedEntryKey = nil
            selectedCalendarEventId = nil
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
            selectedCalendarEventId = nil
        }
    }

    // MARK: - Calendar Event Selection

    /// Toggle selection for a calendar event. Clicking a selected event
    /// deselects it; clicking any other event replaces the selection.
    /// Selection clears app-block and entry selection to keep the
    /// accent highlight single-sourced across the three columns.
    func toggleCalendarEventSelection(_ event: CalendarEvent) {
        let id = event.calendarItemIdentifier
        if selectedCalendarEventId == id {
            selectedCalendarEventId = nil
        } else {
            selectedCalendarEventId = id
            selectedAppBlockIds.removeAll()
            selectedEntryKey = nil
        }
    }

    /// True when the event is the user's active selection OR is the
    /// source of the currently selected entry. Drives the accent border
    /// on calendar blocks during cross-column highlighting.
    func isCalendarEventHighlighted(_ event: CalendarEvent) -> Bool {
        if selectedCalendarEventId == event.calendarItemIdentifier { return true }
        if let entry = selectedEntry,
           let sid = entry.origin.calendarEventId,
           sid == event.calendarItemIdentifier {
            return true
        }
        return false
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
        // Cross-highlight from a selected calendar event: entries
        // created from that event light up so the user can see which
        // tracked work the meeting produced.
        if let eventId = selectedCalendarEventId,
           entry.origin.calendarEventId == eventId {
            return true
        }
        guard !selectedAppBlockIds.isEmpty,
              let bundleId = entry.origin.appBundleId, !bundleId.isEmpty
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
              let bundleId = entry.origin.appBundleId, !bundleId.isEmpty
        else { return false }
        return bundleId == block.appBundleId
    }

    /// Returns true when the given time slot is selected OR an entry
    /// originating from this slot's dominant app is currently selected.
    func isTimeSlotHighlighted(_ slot: TimeSlot) -> Bool {
        if selectedAppBlockIds.contains(slot.id) { return true }
        guard let entry = selectedEntry,
              let bundleId = entry.origin.appBundleId, !bundleId.isEmpty
        else { return false }
        return bundleId == slot.dominantBundleId
    }

    /// The subset of appUsageBlocks whose ids are in the selection set.
    var selectedAppBlocks: [AppUsageBlock] {
        appUsageBlocks.filter { selectedAppBlockIds.contains($0.id) }
    }

    /// The subset of timeSlots whose ids are in the selection set.
    var selectedTimeSlots: [TimeSlot] {
        timeSlots.filter { selectedAppBlockIds.contains($0.id) }
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
        // Try time slots first, fall back to legacy app usage blocks.
        if let slot = timeSlots.first(where: { $0.id == blockId }) {
            startDragCreation(slot: slot)
            return
        }

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

    /// Begin a creation drag from a time slot.
    func startDragCreation(slot: TimeSlot) {
        let ids: [String]
        let slots: [TimeSlot]

        if selectedAppBlockIds.contains(slot.id), selectedAppBlockIds.count > 1 {
            ids = Array(selectedAppBlockIds)
            slots = selectedTimeSlots
        } else {
            ids = [slot.id]
            slots = [slot]
        }

        guard !slots.isEmpty else { return }

        let minMin = slots.map(\.startMinutes).min() ?? slot.startMinutes
        let maxMin = slots.map(\.endMinutes).max() ?? slot.endMinutes
        let duration = max(maxMin - minMin, TimelineLayout.snapMinutes)

        let overlaps = !overlappingEntries(startMinutes: minMin, durationMinutes: duration).isEmpty
        dragCreationState = DragCreationState(
            sourceBlockIds: ids,
            appName: slot.dominantAppName,
            appBundleId: slot.dominantBundleId,
            startMinutes: minMin,
            durationMinutes: duration,
            isOverlapping: overlaps
        )
        Self.logger.debug("Drag creation started from time slot: \(ids.count) slots, \(duration)min")
    }

    /// Update the ghost block position during drag based on the cursor's y in
    /// the entry column coordinate space.
    func updateDragCreation(targetY: CGFloat) {
        guard let state = dragCreationState else { return }
        let rawMinutes = Double(targetY) / Double(TimelineLayout.pixelsPerMinute)
        let snapped = TimelineGeometry.snapToGrid(minutes: rawMinutes, gridMinutes: TimelineLayout.snapMinutes)
        let duration = state.durationMinutes
        let overlaps = !overlappingEntries(startMinutes: snapped, durationMinutes: duration).isEmpty
        dragCreationState?.startMinutes = snapped
        dragCreationState?.isOverlapping = overlaps
    }

    /// End the creation drag, returning the final state for sheet presentation.
    /// Returns nil if no drag was in progress.
    func endDragCreation() -> (startMinutes: Int, durationMinutes: Int, appName: String, sourceBundleId: String?)? {
        guard let state = dragCreationState else { return nil }
        dragCreationState = nil
        dragCreationAnchorMinutes = nil
        Self.logger.debug("Drag creation ended: \(state.startMinutes)min, \(state.durationMinutes)min duration")
        let bundle: String? = state.appBundleId.isEmpty ? nil : state.appBundleId
        return (startMinutes: state.startMinutes, durationMinutes: state.durationMinutes, appName: state.appName, sourceBundleId: bundle)
    }

    /// Cancel drag creation without producing a result.
    func cancelDragCreation() {
        dragCreationState = nil
        dragCreationAnchorMinutes = nil
    }

    /// Begin a drag-to-create on empty entry-column space. No source block —
    /// `sourceBlockIds` is empty so the view layer can distinguish this flow
    /// from the app-block drag if needed. The drag supports both directions:
    /// the anchor minute is stored in `dragCreationAnchorMinutes`, and
    /// `extendEmptyAreaDrag` computes the block as `[min(anchor, current),
    /// max(anchor, current)]` so dragging upward from the anchor produces
    /// a block that ends at the anchor and starts at the drag location.
    func beginEmptyAreaDrag(atMinutes startMinutes: Int) {
        let snapped = TimelineGeometry.snapToGrid(
            minutes: Double(startMinutes),
            gridMinutes: TimelineLayout.snapMinutes
        )
        dragCreationAnchorMinutes = snapped
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

    /// Extend an empty-area drag to `endMinutes`. The block spans
    /// `[min(anchor, end), max(anchor, end)]` with a floor of one snap
    /// interval — so dragging up OR down from the anchor produces a
    /// correctly-sized block.
    func extendEmptyAreaDrag(toMinutes endMinutes: Int) {
        guard let state = dragCreationState, state.sourceBlockIds.isEmpty else { return }
        guard let anchor = dragCreationAnchorMinutes else { return }
        _ = state
        let snapped = TimelineGeometry.snapToGrid(
            minutes: Double(endMinutes),
            gridMinutes: TimelineLayout.snapMinutes
        )
        let lower = min(anchor, snapped)
        let upper = max(anchor, snapped)
        let newStart = lower
        let newDuration = max(upper - lower, TimelineLayout.snapMinutes)
        let overlaps = !overlappingEntries(
            startMinutes: newStart,
            durationMinutes: newDuration
        ).isEmpty
        dragCreationState?.startMinutes = newStart
        dragCreationState?.durationMinutes = newDuration
        dragCreationState?.isOverlapping = overlaps
    }

    // MARK: - Entry Creation

    /// Computes the `pendingCreation` payload for a dropped all-day
    /// calendar event. Returns the start minutes, a fixed 1-hour
    /// duration, the event title as the sheet's suggested description,
    /// and the event's calendar identifier so the caller can set it on
    /// the `PendingCreation.calendarEventId` field — `createEntry` then
    /// stamps it as `sourceCalendarEventId` on save.
    func allDayEventDropPayload(
        _ event: CalendarEvent,
        atStartTime startTime: String
    ) -> (startMinutes: Int, durationMinutes: Int, appName: String, sourceBundleId: String?, calendarEventId: String) {
        let minutes = TimelineGeometry.minutesSinceMidnight(from: startTime) ?? 0
        return (minutes, 60, event.title, nil, event.calendarItemIdentifier)
    }

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
        sourceAppBundleId: String? = nil,
        sourceCalendarEventId: String? = nil
    ) async {
        let now = Self.isoFormatter.string(from: Date.now)

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
            sync: ShadowEntry.SyncMeta(
                status: .pendingCreate,
                localUpdatedAt: now,
                serverUpdatedAt: now,
                conflictFlag: false
            ),
            origin: ShadowEntry.Origin(
                appBundleId: sourceAppBundleId,
                ruleId: nil,
                calendarEventId: sourceCalendarEventId
            )
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
        guard let bundleId = entry.origin.appBundleId, !bundleId.isEmpty else {
            return nil
        }
        return appUsageBlocks.first(where: { $0.appBundleId == bundleId })?.appName
    }

    /// Returns true if this entry was created FROM a recorded activity
    /// block (via right-click "Create entry from this block", drag-create
    /// from a block, or a matching TrackingRule). Origin-based — two
    /// entries simply standing next to each other in time are NOT linked.
    func isLinkedToAppBlock(_ entry: ShadowEntry) -> Bool {
        guard let bundleId = entry.origin.appBundleId, !bundleId.isEmpty else {
            return false
        }
        // Only show the link badge when the originating app block is
        // still visible on the current day — otherwise the indicator is
        // meaningless for the user.
        return appUsageBlocks.contains { $0.appBundleId == bundleId }
    }

    // MARK: - Calendar Event Linkage

    /// True when there is a ShadowEntry on the current day whose
    /// `origin.calendarEventId` matches this event. Drives the
    /// cross-highlight between the entry column and the calendar
    /// column.
    func isEventLinkedToEntry(_ event: CalendarEvent) -> Bool {
        shadowEntries.contains { $0.origin.calendarEventId == event.calendarItemIdentifier }
    }

    /// Reverse lookup for the entry column — true when an entry has a
    /// source calendar event that exists in today's fetched events.
    /// Used by EntryBlockView to render an alternate highlight when the
    /// event is visible to the right of it.
    func isEntryLinkedToCalendarEvent(_ entry: ShadowEntry) -> Bool {
        guard let eid = entry.origin.calendarEventId else { return false }
        return calendarEvents.contains { $0.calendarItemIdentifier == eid }
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
        let timed: [(entry: ShadowEntry, start: Int, end: Int)] = positionedEntries.compactMap { entry in
            guard let ts = entry.startTime,
                  let start = TimelineGeometry.minutesSinceMidnight(from: ts)
            else { return nil }
            let end = start + max(entry.seconds / 60, 1)
            return (entry, start, end)
        }
        let assignments = ClusterColumns.assign(timed.map { ($0.start, $0.end) })
        return zip(timed, assignments).map { item, a in
            EntryLayout(entry: item.entry, columnIndex: a.columnIndex, columnCount: a.columnCount)
        }
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
