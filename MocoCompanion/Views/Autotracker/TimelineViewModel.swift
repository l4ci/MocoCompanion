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

    // MARK: - Drag Creation State

    /// State describing an in-progress creation drag from app usage to entry column.
    struct DragCreationState {
        let sourceBlockIds: [String]
        let appName: String
        var startMinutes: Int
        var durationMinutes: Int
        var isOverlapping: Bool
    }

    var dragCreationState: DragCreationState?

    // MARK: - Init

    init(shadowEntryStore: ShadowEntryStore, autotracker: Autotracker, syncState: SyncState) {
        self.shadowEntryStore = shadowEntryStore
        self.autotracker = autotracker
        self.syncState = syncState
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
        guard !entry.locked, entry.id != nil else { return }
        var updated = entry
        updated.startTime = newStartTime
        updated.syncStatus = .dirty
        updated.localUpdatedAt = ISO8601DateFormatter().string(from: Date())
        do {
            try await shadowEntryStore.update(updated)
            Self.logger.info("Moved entry \(entry.id ?? 0) to \(newStartTime)")
            await loadData()
        } catch {
            Self.logger.error("Failed to move entry \(entry.id ?? 0): \(error)")
        }
    }

    /// Update an entry's project, task, and description. Locked entries are rejected.
    /// Used by the edit sheet when re-assigning an auto-created entry.
    func updateEntryContent(
        _ entry: ShadowEntry,
        projectId: Int,
        taskId: Int,
        projectName: String,
        taskName: String,
        customerName: String,
        description: String
    ) async {
        guard !entry.locked, entry.id != nil || entry.localId != nil else { return }
        var updated = entry
        updated.projectId = projectId
        updated.taskId = taskId
        updated.projectName = projectName
        updated.taskName = taskName
        updated.customerName = customerName
        updated.description = description
        updated.syncStatus = .dirty
        updated.localUpdatedAt = ISO8601DateFormatter().string(from: Date())
        do {
            try await shadowEntryStore.update(updated)
            Self.logger.info("Updated entry \(entry.id ?? 0) content: project=\(projectId) task=\(taskId)")
            await loadData()
        } catch {
            Self.logger.error("Failed to update entry \(entry.id ?? 0): \(error)")
        }
    }

    /// Resize an entry by changing start time and/or duration. Locked entries are rejected.
    func resizeEntry(_ entry: ShadowEntry, newStartTime: String, newDurationSeconds: Int) async {
        guard !entry.locked, entry.id != nil else { return }
        var updated = entry
        updated.startTime = newStartTime
        updated.seconds = newDurationSeconds
        updated.hours = Double(newDurationSeconds) / 3600.0
        updated.syncStatus = .dirty
        updated.localUpdatedAt = ISO8601DateFormatter().string(from: Date())
        do {
            try await shadowEntryStore.update(updated)
            Self.logger.info("Resized entry \(entry.id ?? 0) to \(newStartTime), \(newDurationSeconds)s")
            await loadData()
        } catch {
            Self.logger.error("Failed to resize entry \(entry.id ?? 0): \(error)")
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
        Self.logger.debug("Selection changed: \(self.selectedAppBlockIds.count) blocks selected")
    }

    func clearAppBlockSelection() {
        selectedAppBlockIds.removeAll()
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

        let overlaps = !overlappingEntries(startMinutes: minMinutes, durationMinutes: duration).isEmpty
        dragCreationState = DragCreationState(
            sourceBlockIds: ids,
            appName: appName,
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
    func endDragCreation() -> (startMinutes: Int, durationMinutes: Int, appName: String)? {
        guard let state = dragCreationState else { return nil }
        dragCreationState = nil
        Self.logger.debug("Drag creation ended: \(state.startMinutes)min, \(state.durationMinutes)min duration")
        return (startMinutes: state.startMinutes, durationMinutes: state.durationMinutes, appName: state.appName)
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
    func createEntry(
        date: String,
        startTime: String,
        durationSeconds: Int,
        projectId: Int,
        taskId: Int,
        projectName: String,
        taskName: String,
        customerName: String,
        description: String
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
            conflictFlag: false
        )

        do {
            try await shadowEntryStore.insert(entry)
            Self.logger.info("Entry created via timeline drag: \(startTime), \(durationSeconds)s, project \(projectId)")
            await loadData()
        } catch {
            Self.logger.error("Failed to create entry: \(error)")
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
