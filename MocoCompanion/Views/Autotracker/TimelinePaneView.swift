import AppKit
import SwiftUI

/// Dual-pane timeline layout: time axis + app usage blocks on left, Moco entry blocks on right.
/// Synchronized scrolling via a single ScrollView wrapping both panes.
struct TimelinePaneView: View {
    let positionedEntries: [ShadowEntry]
    let unpositionedEntries: [ShadowEntry]
    let appUsageBlocks: [AppUsageBlock]
    let selectedDate: Date
    let isToday: Bool
    let viewModel: TimelineViewModel
    let projectCatalog: ProjectCatalog
    var descriptionRequired: Bool = false
    @Environment(\.theme) private var theme
    @State private var pendingCreation: (startMinutes: Int, durationMinutes: Int, appName: String, sourceBundleId: String?)?
    /// Set alongside `pendingCreation` when the creation sheet is
    /// triggered by a calendar event (double-click or context menu). Task
    /// 16's sheet rework will read this to stamp the new entry's
    /// `sourceCalendarEventId` so the cross-highlight kicks in immediately.
    @State private var pendingCreationCalendarEventId: String?
    @State private var ruleEditorConfig: RuleEditorConfig?
    @State private var editingEntry: EditingEntryWrapper?
    @State private var entryPendingDelete: ShadowEntry?
    @FocusState private var isPaneFocused: Bool

    /// Identifiable wrapper so SwiftUI's `.sheet(item:)` can present the edit
    /// sheet for a `ShadowEntry` (whose `id` is optional and can't conform).
    struct EditingEntryWrapper: Identifiable {
        let entry: ShadowEntry
        var id: String { "\(entry.id ?? 0)-\(entry.localId ?? "")" }
    }
    /// Tracks the entry column's origin in global coordinate space for drag target conversion.
    @State private var entryColumnGlobalOrigin: CGFloat = 0
    /// Tracks the entry column's laid-out width (used to place
    /// overlapping entries into side-by-side fractional columns).
    @State private var entryColumnWidth: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            // Batch approve suggestions
            if !viewModel.suggestions.isEmpty {
                batchApproveBar
                Divider()
            }

            // Aboveline region — column-aligned HStack that mirrors the
            // scroll content's column widths. All-day calendar events
            // sit above the calendar column; unassigned Moco entries
            // sit above the entry column. Collapses when both lists
            // are empty.
            let hasAnyAboveline = !viewModel.allDayEvents.isEmpty || !unpositionedEntries.isEmpty
            if hasAnyAboveline {
                abovelineRegion
                Divider()
            }

            // (Column header row removed — the divider between panes
            // and the icon-led content inside each column carry enough
            // meaning on their own. The toolbar's refresh button sits in
            // the window chrome, so no extra header row is needed here.)

            // Main timeline scroll area. Always rendered so the entry
            // column remains a valid drop target even on empty days; the
            // empty-state messages overlay the ScrollView instead of
            // replacing it.
            ZStack(alignment: .top) {
                scrollContent

                if positionedEntries.isEmpty && appUsageBlocks.isEmpty && unpositionedEntries.isEmpty {
                    Text("No activity for this day")
                        .font(.system(size: Theme.FontSize.body))
                        .foregroundStyle(theme.textTertiary)
                        .padding(12)
                        .background(theme.surface.opacity(0.85), in: Capsule())
                        .padding(.top, 60)
                        .allowsHitTesting(false)
                } else if positionedEntries.isEmpty && appUsageBlocks.isEmpty {
                    Text("No timed entries for this day")
                        .font(.system(size: Theme.FontSize.body))
                        .foregroundStyle(theme.textTertiary)
                        .padding(12)
                        .background(theme.surface.opacity(0.85), in: Capsule())
                        .padding(.top, 60)
                        .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .focusable()
        .focusEffectDisabled()
        .focused($isPaneFocused)
        .onAppear { isPaneFocused = true }
        .onKeyPress(keys: [.delete, .deleteForward]) { _ in
            guard let entry = viewModel.selectedEntry else { return .ignored }
            entryPendingDelete = entry
            return .handled
        }
        .confirmationDialog(
            "Delete this entry?",
            isPresented: Binding(
                get: { entryPendingDelete != nil && viewModel.selectedEntry != nil },
                set: { if !$0 { entryPendingDelete = nil } }
            )
        ) {
            Button("Delete", role: .destructive) {
                if let entry = entryPendingDelete {
                    entryPendingDelete = nil
                    Task { await viewModel.deleteEntry(entry) }
                }
            }
            .keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) { }
                .keyboardShortcut(.cancelAction)
        } message: {
            Text("You can undo this for 5 seconds.")
        }
        .sheet(item: $ruleEditorConfig) { config in
            RuleEditorSheet(
                existingRule: nil,
                prefillBundleId: config.prefillBundleId,
                prefillAppName: config.prefillAppName,
                autotracker: viewModel.autotracker,
                projectCatalog: projectCatalog,
                    onSave: {
                        Task { await viewModel.loadData() }
                    }
                )
        }
        .sheet(item: $editingEntry) { wrapper in
            TimelineEntryEditSheet(
                entry: wrapper.entry,
                fallbackDate: selectedDate,
                projectCatalog: projectCatalog,
                linkedAppName: viewModel.linkedAppName(for: wrapper.entry),
                descriptionRequired: descriptionRequired,
                onSave: { edited in
                    Task {
                        await viewModel.updateEntryFully(
                            wrapper.entry,
                            projectId: edited.projectId,
                            taskId: edited.taskId,
                            projectName: edited.projectName,
                            taskName: edited.taskName,
                            customerName: edited.customerName,
                            description: edited.description,
                            date: edited.date,
                            startTime: edited.startTime,
                            durationSeconds: edited.durationMinutes * 60
                        )
                        editingEntry = nil
                    }
                },
                onDelete: wrapper.entry.isReadOnly ? nil : {
                    let entry = wrapper.entry
                    editingEntry = nil
                    Task { await viewModel.deleteEntry(entry) }
                },
                onCancel: { editingEntry = nil }
            )
        }
        .sheet(isPresented: showCreationSheet) {
            if let creation = pendingCreation {
                let dateStr = TimelineGeometry.dateString(from: selectedDate)
                let startTimeStr = TimelineGeometry.timeString(fromMinutes: creation.startMinutes)
                TimelineEntryCreationSheet(
                    date: dateStr,
                    startTime: startTimeStr,
                    durationMinutes: creation.durationMinutes,
                    suggestedDescription: creation.appName,
                    projectCatalog: projectCatalog,
                    descriptionRequired: descriptionRequired,
                    onSubmit: { projectId, taskId, projectName, taskName, customerName, description in
                        let calendarEventId = pendingCreationCalendarEventId
                        Task {
                            await viewModel.createEntry(
                                date: dateStr,
                                startTime: startTimeStr,
                                durationSeconds: creation.durationMinutes * 60,
                                projectId: projectId,
                                taskId: taskId,
                                projectName: projectName,
                                taskName: taskName,
                                customerName: customerName,
                                description: description,
                                sourceAppBundleId: creation.sourceBundleId,
                                sourceCalendarEventId: calendarEventId
                            )
                        }
                        pendingCreation = nil
                        pendingCreationCalendarEventId = nil
                    },
                    onCancel: {
                        pendingCreation = nil
                        pendingCreationCalendarEventId = nil
                    }
                )
            }
        }
    }

    private var showCreationSheet: Binding<Bool> {
        Binding(
            get: { pendingCreation != nil },
            set: {
                if !$0 {
                    pendingCreation = nil
                    pendingCreationCalendarEventId = nil
                }
            }
        )
    }

    // MARK: - Empty-Area Drag Gesture

    private var emptyAreaDragGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                let startMinute = Int(Double(value.startLocation.y) / Double(TimelineLayout.pixelsPerMinute))
                let currentMinute = Int(Double(value.location.y) / Double(TimelineLayout.pixelsPerMinute))
                if viewModel.dragCreationState == nil {
                    viewModel.beginEmptyAreaDrag(atMinutes: startMinute)
                }
                viewModel.extendEmptyAreaDrag(toMinutes: currentMinute)
            }
            .onEnded { _ in
                guard let drag = viewModel.dragCreationState,
                      drag.sourceBlockIds.isEmpty,
                      !drag.isOverlapping
                else {
                    viewModel.cancelDragCreation()
                    return
                }
                let startMinutes = drag.startMinutes
                let durationMinutes = drag.durationMinutes
                viewModel.cancelDragCreation()
                pendingCreation = (
                    startMinutes: startMinutes,
                    durationMinutes: durationMinutes,
                    appName: "",
                    sourceBundleId: nil
                )
            }
    }

    // MARK: - Aboveline Region

    /// Column-aligned HStack that mirrors the scroll content's column
    /// structure so all-day calendar events sit directly above the
    /// calendar column and unassigned Moco entries sit directly above
    /// the entry column.
    private var abovelineRegion: some View {
        HStack(alignment: .top, spacing: 0) {
            // Time axis spacer
            Color.clear.frame(width: TimelineLayout.timeAxisWidth)

            // App column — reserved for future use; empty for now.
            if viewModel.settings?.appRecordingEnabled == true {
                Color.clear.frame(width: TimelineLayout.appUsagePaneWidth)
                theme.divider.frame(width: 1)
            }

            // Calendar column — all-day events, draggable.
            if viewModel.settings?.calendarEnabled == true {
                allDayCalendarColumn
                    .frame(width: TimelineLayout.calendarPaneWidth, alignment: .topLeading)
                theme.divider.frame(width: 1)
            }

            // Entry column — unassigned Moco entries.
            unassignedEntriesColumn
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .padding(.vertical, 8)
    }

    private var allDayCalendarColumn: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(viewModel.allDayEvents) { event in
                AllDayCalendarEventRow(event: event)
                    .draggable("cal:\(event.calendarItemIdentifier)") {
                        Text(event.title)
                            .font(.system(size: Theme.FontSize.caption, weight: .medium))
                            .padding(6)
                            .background(theme.surface, in: Capsule())
                    }
            }
        }
        .padding(.horizontal, 4)
    }

    private var unassignedEntriesColumn: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(unpositionedEntries, id: \.id) { entry in
                HStack(spacing: 6) {
                    Text(entry.projectName)
                        .font(.system(size: Theme.FontSize.caption, weight: .medium))
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(1)

                    Text(entry.taskName)
                        .font(.system(size: Theme.FontSize.caption))
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    Text(Self.formatDuration(entry.seconds))
                        .font(.system(size: Theme.FontSize.caption, design: .monospaced))
                        .foregroundStyle(theme.textTertiary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
                .help("Drag onto the timeline to set a start time, or right-click to edit")
                .contextMenu {
                    if !entry.isReadOnly {
                        Button("Edit entry…") {
                            editingEntry = EditingEntryWrapper(entry: entry)
                        }
                        Divider()
                        Button(role: .destructive) {
                            entryPendingDelete = entry
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
                .confirmationDialog(
                    "Delete this entry?",
                    isPresented: Binding(
                        get: { entryPendingDelete != nil },
                        set: { if !$0 { entryPendingDelete = nil } }
                    )
                ) {
                    Button("Delete", role: .destructive) {
                        if let entry = entryPendingDelete {
                            entryPendingDelete = nil
                            Task { await viewModel.deleteEntry(entry) }
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    Button("Cancel", role: .cancel) { }
                        .keyboardShortcut(.cancelAction)
                } message: {
                    Text("You can undo this for 5 seconds.")
                }
                // Make the row draggable so the user can drop it onto the
                // timeline to assign a start time. We pass the entry id as
                // a plain Int payload; the drop handler looks it up.
                .draggable(String(entry.id ?? 0)) {
                    // Drag preview: a simple compact label.
                    HStack(spacing: 4) {
                        Text(entry.projectName)
                            .font(.system(size: Theme.FontSize.caption, weight: .medium))
                        Text(entry.taskName)
                            .font(.system(size: Theme.FontSize.caption))
                    }
                    .padding(6)
                    .background(theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
                }
            }
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Batch Approve

    private var batchApproveBar: some View {
        HStack {
            Spacer()
            Button {
                Task { await viewModel.approveAllSuggestions() }
            } label: {
                Text("Approve all (\(viewModel.suggestions.count))")
                    .font(.system(size: Theme.FontSize.caption, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.12), in: Capsule())
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Scrollable Timeline

    /// Just the vertically-scrolling time canvas. Column headers live at
    /// the body level and are NOT part of this view.
    private var scrollContent: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                ZStack(alignment: .topLeading) {
                    // Grid background
                    TimeAxisGridBackground(
                        workdayStartHour: viewModel.workdayStartHour,
                        workdayEndHour: viewModel.workdayEndHour
                    )

                    // Panes. Columns render conditionally based on the
                    // user's settings toggles. The time axis is always
                    // first; the entry column always fills the
                    // remainder; optional app-usage and calendar columns
                    // slot between them, each followed by a divider.
                    HStack(alignment: .top, spacing: 0) {
                        // Time axis
                        TimeAxisView()

                        // App usage column (optional)
                        if viewModel.settings?.appRecordingEnabled == true {
                            appUsageColumn
                                .frame(width: TimelineLayout.appUsagePaneWidth)
                            theme.divider
                                .frame(width: 1, height: TimelineLayout.totalHeight)
                        }

                        // Calendar column (optional)
                        if viewModel.settings?.calendarEnabled == true {
                            calendarColumn
                            theme.divider
                                .frame(width: 1, height: TimelineLayout.totalHeight)
                        }

                        // Entry column
                        entryColumn
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }

                    // Now line overlay
                    if isToday {
                        NowLineView()
                    }

                    // Scroll anchor. Uses `.position` (layout placement) not
                    // `.offset` (visual-only) so ScrollViewReader.scrollTo
                    // actually targets the anchor's laid-out y coordinate.
                    Color.clear
                        .frame(width: 1, height: 1)
                        .position(x: 0.5, y: scrollAnchorY)
                        .id("scrollAnchor")
                }
                .frame(height: TimelineLayout.totalHeight)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear {
                // Defer so the ScrollView has completed its initial layout
                // pass; otherwise scrollTo runs before the anchor has a frame.
                DispatchQueue.main.async {
                    proxy.scrollTo("scrollAnchor", anchor: .center)
                }
            }
            .onChange(of: selectedDate) {
                DispatchQueue.main.async {
                    proxy.scrollTo("scrollAnchor", anchor: .center)
                }
            }
        }
    }

    /// Y position for the scroll anchor: now-line on today, 8:00 AM otherwise.
    private var scrollAnchorY: CGFloat {
        if isToday {
            let components = Calendar.current.dateComponents([.hour, .minute], from: Date())
            let minutes = CGFloat((components.hour ?? 0) * 60 + (components.minute ?? 0))
            return minutes * TimelineLayout.pixelsPerMinute
        }
        return 8 * 60 * TimelineLayout.pixelsPerMinute // 8:00 AM
    }

    // MARK: - App Usage Column

    private var appUsageColumn: some View {
        ZStack(alignment: .top) {
            ZStack(alignment: .topLeading) {
                ForEach(appUsageBlocks) { block in
                    AppUsageBlockView(
                        block: block,
                        isSelected: viewModel.isAppBlockHighlighted(block),
                        onSelect: { shiftHeld in
                            viewModel.toggleAppBlockSelection(id: block.id, shiftHeld: shiftHeld)
                        },
                        onCreateRule: { bundleId, appName in
                            ruleEditorConfig = RuleEditorConfig(prefillBundleId: bundleId, prefillAppName: appName)
                        },
                        onCreateEntry: { block in
                            let comps = Calendar.current.dateComponents([.hour, .minute], from: block.startTime)
                            let startMinutes = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
                            let durationMinutes = max(Int(block.durationSeconds) / 60, TimelineLayout.snapMinutes)
                            pendingCreation = (startMinutes: startMinutes, durationMinutes: durationMinutes, appName: block.appName, sourceBundleId: block.appBundleId)
                        },
                        onDragStarted: {
                            viewModel.startDragCreation(blockId: block.id)
                        },
                        onDragUpdated: { globalY in
                            let localY = globalY - entryColumnGlobalOrigin
                            viewModel.updateDragCreation(targetY: localY)
                        },
                        onDragEnded: {
                            pendingCreation = viewModel.endDragCreation()
                        }
                    )
                    .offset(y: yOffset(for: block.startTime))
                }
            }

            if let state = accessibilityPlaceholderState {
                AccessibilityColumnPlaceholderView(
                    state: state,
                    onOpenSettings: openSystemSettingsForAccessibility,
                    onRequestAccess: { _ = AccessibilityPermission.requestAccess() }
                )
                .padding(.top, 40)
            }
        }
        .frame(height: TimelineLayout.totalHeight, alignment: .topLeading)
    }

    private var accessibilityPlaceholderState: AccessibilityColumnPlaceholder? {
        guard viewModel.settings?.windowTitleTrackingEnabled == true else { return nil }
        if AccessibilityPermission.isTrusted { return nil }
        return .needsPermission
    }

    private func openSystemSettingsForAccessibility() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Calendar Column

    /// Renders timed calendar events from the view model's
    /// `calendarEventLayouts` using the same cluster/column layout as
    /// the entry column. All-day events are excluded (they belong in the
    /// aboveline region, not on the timeline).
    private var calendarColumn: some View {
        ZStack(alignment: .top) {
            ZStack(alignment: .topLeading) {
                ForEach(viewModel.calendarEventLayouts) { layout in
                    let availableWidth = TimelineLayout.calendarPaneWidth - 8 // 4pt inset per side
                    let columnWidth = layout.columnCount > 0
                        ? availableWidth / CGFloat(layout.columnCount)
                        : availableWidth
                    let gap: CGFloat = layout.columnCount > 1 ? 2 : 0
                    CalendarEventBlockView(
                        event: layout.event,
                        isSelected: false, // no first-class selection for calendar blocks yet
                        isLinked: viewModel.isEventLinkedToEntry(layout.event),
                        onCreateEntry: {
                            openCreationSheetForEvent(layout.event)
                        },
                        onCreateRule: {
                            openRuleEditorForEvent(layout.event)
                        },
                        onOpenInCalendar: {
                            openInCalendarApp(layout.event)
                        }
                    )
                    .frame(width: max(columnWidth - gap, 14), alignment: .topLeading)
                    .offset(
                        x: 4 + columnWidth * CGFloat(layout.columnIndex),
                        y: yOffset(for: layout.event.startDate)
                    )
                }
            }

            if let state = calendarPlaceholderState {
                CalendarColumnPlaceholderView(
                    state: state,
                    onOpenSettings: openSystemSettingsForCalendar,
                    onRequestAccess: {
                        Task { _ = await viewModel.calendarService?.requestAccessIfNeeded() }
                    }
                )
                .padding(.top, 40)
            }
        }
        .frame(
            width: TimelineLayout.calendarPaneWidth,
            height: TimelineLayout.totalHeight,
            alignment: .topLeading
        )
    }

    private var calendarPlaceholderState: CalendarColumnPlaceholder? {
        guard let svc = viewModel.calendarService else { return nil }
        if svc.authorizationStatus == .notDetermined { return .needsPermission }
        if !svc.hasReadAccess { return .denied }
        if viewModel.settings?.selectedCalendarId == nil { return .noCalendarSelected }
        if viewModel.calendarEvents.isEmpty { return .noEvents }
        return nil
    }

    private func openSystemSettingsForCalendar() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Calendar Event Actions

    /// Double-click / context-menu "Create entry from event" →
    /// pre-fills the creation sheet with the event's start/duration and
    /// title, and stashes the calendar event id so the sheet rework in
    /// Task 16 can stamp `sourceCalendarEventId` on the new row.
    private func openCreationSheetForEvent(_ event: CalendarEvent) {
        guard let startMinutes = event.startMinutes else { return }
        pendingCreation = (
            startMinutes: startMinutes,
            durationMinutes: max(event.durationMinutes, TimelineLayout.snapMinutes),
            appName: event.title,
            sourceBundleId: nil
        )
        pendingCreationCalendarEventId = event.calendarItemIdentifier
    }

    /// Context-menu "Create rule from event" → opens the rule editor
    /// pre-filled as a calendar rule with the event's title as the
    /// match pattern. The prefill fields are wired here; Task 16 will
    /// make the sheet honor them in its populate step.
    private func openRuleEditorForEvent(_ event: CalendarEvent) {
        ruleEditorConfig = RuleEditorConfig(
            prefillRuleType: .calendar,
            prefillEventTitle: event.title
        )
    }

    /// Context-menu "Open in Calendar" → hands off to Calendar.app
    /// using the `ical://ekevent/<id>` URL scheme.
    private func openInCalendarApp(_ event: CalendarEvent) {
        if let url = URL(string: "ical://ekevent/\(event.calendarItemIdentifier)") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Entry Column

    private var entryColumn: some View {
        ZStack(alignment: .topLeading) {
            // Background drag-to-create layer. Rendered first so entry
            // blocks and suggestion blocks layer on top and take gesture
            // priority when the user drags on them directly. Dragging in
            // empty space between blocks hits this layer and begins a
            // drag-to-create.
            Color.clear
                .contentShape(Rectangle())
                .frame(height: TimelineLayout.totalHeight)
                .gesture(emptyAreaDragGesture)

            ForEach(viewModel.positionedEntryLayouts) { layout in
                let entry = layout.entry
                let availableWidth = max(entryColumnWidth - 8, 0) // 4pt inset per side
                let columnWidth = layout.columnCount > 0
                    ? availableWidth / CGFloat(layout.columnCount)
                    : availableWidth
                let gap: CGFloat = layout.columnCount > 1 ? 2 : 0
                let entryKey = TimelineViewModel.entryKey(for: entry)
                let isPreviewing = viewModel.gesturePreviewState?.entryKey == entryKey
                EntryBlockView(
                    entry: entry,
                    viewModel: viewModel,
                    projectCatalog: projectCatalog,
                    isHighlighted: viewModel.isEntryHighlighted(entry),
                    onEdit: { e in editingEntry = EditingEntryWrapper(entry: e) },
                    onDelete: { e in Task { await viewModel.deleteEntry(e) } },
                    onSelect: { viewModel.toggleEntrySelection(entry) }
                )
                    .frame(width: max(columnWidth - gap, 14), alignment: .topLeading)
                    .offset(
                        x: 4 + columnWidth * CGFloat(layout.columnIndex),
                        y: yOffsetFromTimeString(entry.startTime)
                    )
                    // While a drag-move or edge-resize gesture is live
                    // on this entry, the ghost block below carries the
                    // preview and this original block is hidden. The
                    // ghost disappears only AFTER the VM update completes
                    // and the entry's own position/size match the target,
                    // so the transition from "ghost visible, original
                    // hidden" to "ghost gone, original visible at new
                    // position" is a pixel-identical swap — no flicker.
                    .opacity(isPreviewing ? 0 : 1)
            }

            // Suggestion blocks
            ForEach(viewModel.suggestions) { suggestion in
                SuggestionBlockView(suggestion: suggestion, viewModel: viewModel)
                    .padding(.horizontal, 4)
                    .offset(y: yOffsetFromTimeString(suggestion.startTime))
            }

            // Ghost block during creation drag
            if let drag = viewModel.dragCreationState {
                ghostBlock(for: drag)
            }

            // Ghost block for in-flight drag-move / resize on an
            // existing entry. Mirrors the drag-create ghost pattern
            // (dragCreationState) — draws a preview at the gesture
            // target without disturbing the real entry's layout state.
            if let preview = viewModel.gesturePreviewState {
                gesturePreviewBlock(for: preview)
            }
        }
        .frame(height: TimelineLayout.totalHeight, alignment: .topLeading)
        .dropDestination(for: String.self) { items, location in
            // Drop payload is either:
            //   - "<entryId>" — an existing ShadowEntry id, moved to the
            //     snapped target time via the view model.
            //   - "cal:<calendarItemIdentifier>" — an all-day calendar
            //     event from the aboveline region, which opens the
            //     creation sheet pre-filled with the event's title and
            //     a 1-hour duration at the snapped target time.
            guard let idString = items.first else { return false }
            let rawMinutes = Double(location.y) / Double(TimelineLayout.pixelsPerMinute)
            let snapped = TimelineGeometry.snapToGrid(
                minutes: rawMinutes,
                gridMinutes: TimelineLayout.snapMinutes
            )
            let timeStr = TimelineGeometry.timeString(fromMinutes: snapped)

            if idString.hasPrefix("cal:") {
                let calId = String(idString.dropFirst(4))
                guard let event = viewModel.allDayEvents.first(where: { $0.calendarItemIdentifier == calId }) else {
                    return false
                }
                let payload = viewModel.allDayEventDropPayload(event, atStartTime: timeStr)
                pendingCreation = (
                    startMinutes: payload.startMinutes,
                    durationMinutes: payload.durationMinutes,
                    appName: payload.appName,
                    sourceBundleId: payload.sourceBundleId
                )
                pendingCreationCalendarEventId = payload.calendarEventId
                return true
            }

            guard let id = Int(idString),
                  let entry = viewModel.shadowEntries.first(where: { $0.id == id })
            else { return false }
            Task { await viewModel.moveEntry(entry, toStartTime: timeStr) }
            return true
        }
        .background(
            GeometryReader { geo in
                Color.clear
                    .preference(
                        key: EntryColumnOriginKey.self,
                        value: geo.frame(in: .global).minY
                    )
                    .preference(
                        key: EntryColumnWidthKey.self,
                        value: geo.size.width
                    )
            }
        )
        .onPreferenceChange(EntryColumnOriginKey.self) { value in
            entryColumnGlobalOrigin = value
        }
        .onPreferenceChange(EntryColumnWidthKey.self) { value in
            entryColumnWidth = value
        }
    }

    // MARK: - Ghost Block

    private func ghostBlock(for drag: TimelineViewModel.DragCreationState) -> some View {
        let yPos = CGFloat(drag.startMinutes) * TimelineLayout.pixelsPerMinute
        let height = max(CGFloat(drag.durationMinutes) * TimelineLayout.pixelsPerMinute, 12)
        let tint: Color = drag.isOverlapping ? .orange : .accentColor
        let startLabel = TimelineGeometry.timeString(fromMinutes: drag.startMinutes)
        let endLabel = TimelineGeometry.timeString(fromMinutes: drag.startMinutes + drag.durationMinutes)

        return VStack(alignment: .leading, spacing: 2) {
            Text("\(startLabel) – \(endLabel)")
                .font(.system(size: Theme.FontSize.caption, design: .monospaced))
                .foregroundStyle(tint)
            Text(drag.appName)
                .font(.system(size: Theme.FontSize.caption))
                .foregroundStyle(tint.opacity(0.8))
                .lineLimit(1)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: height)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                .strokeBorder(tint.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
        )
        .offset(y: yPos)
        .padding(.horizontal, 4)
        .allowsHitTesting(false)
        .animation(.easeOut(duration: 0.08), value: drag.startMinutes)
    }

    // MARK: - Gesture Preview Block

    /// Live preview for an in-flight drag-move / edge-resize. Drawn on
    /// top of the hidden original so the user sees the target
    /// position/size without touching the original view's layout
    /// state. The ghost disappears (and the original reappears) only
    /// after the VM mutation completes and the original's entry data
    /// matches the target — so the swap is pixel-identical.
    private func gesturePreviewBlock(for preview: TimelineViewModel.GesturePreviewState) -> some View {
        let yPos = CGFloat(preview.startMinutes) * TimelineLayout.pixelsPerMinute
        let height = max(CGFloat(preview.durationMinutes) * TimelineLayout.pixelsPerMinute, 12)
        let availableWidth = max(entryColumnWidth - 8, 0)
        let columnWidth = preview.columnCount > 0
            ? availableWidth / CGFloat(preview.columnCount)
            : availableWidth
        let gap: CGFloat = preview.columnCount > 1 ? 2 : 0
        let startLabel = TimelineGeometry.timeString(fromMinutes: preview.startMinutes)
        let endLabel = TimelineGeometry.timeString(fromMinutes: preview.startMinutes + preview.durationMinutes)
        let tint: Color = .accentColor

        return VStack(alignment: .leading, spacing: 2) {
            Text("\(startLabel) – \(endLabel)")
                .font(.system(size: Theme.FontSize.caption, design: .monospaced))
                .foregroundStyle(tint)
                .lineLimit(1)
            Text(preview.durationLabel)
                .font(.system(size: Theme.FontSize.caption))
                .foregroundStyle(tint.opacity(0.8))
                .lineLimit(1)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .frame(width: max(columnWidth - gap, 14), height: height, alignment: .topLeading)
        .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                .strokeBorder(tint.opacity(0.55), style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
        )
        .offset(
            x: 4 + columnWidth * CGFloat(preview.columnIndex),
            y: yPos
        )
        .allowsHitTesting(false)
        .animation(.easeOut(duration: 0.08), value: preview.startMinutes)
        .animation(.easeOut(duration: 0.08), value: preview.durationMinutes)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "clock")
                .font(.system(size: Theme.FontSize.largeTitle))
                .foregroundStyle(theme.textTertiary)
            Text("No activity for this day")
                .font(.system(size: Theme.FontSize.body))
                .foregroundStyle(theme.textSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Positioning Helpers

    private func yOffset(for date: Date) -> CGFloat {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        let minutes = CGFloat((components.hour ?? 0) * 60 + (components.minute ?? 0))
        return minutes * TimelineLayout.pixelsPerMinute
    }

    /// Parse "HH:mm" startTime string to a y offset.
    private func yOffsetFromTimeString(_ timeString: String?) -> CGFloat {
        guard let ts = timeString, ts.count >= 5 else { return 0 }
        let parts = ts.prefix(5).split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]) else { return 0 }
        return CGFloat(hour * 60 + minute) * TimelineLayout.pixelsPerMinute
    }

    private static func formatDuration(_ totalSeconds: Int) -> String {
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        if hours > 0 {
            return String(format: "%dh %02dm", hours, minutes)
        }
        return String(format: "%dm", minutes)
    }
}

// MARK: - Preference Key

/// Configuration for presenting the rule editor sheet with optional pre-fill values.
struct RuleEditorConfig: Identifiable {
    let id = UUID()
    var prefillBundleId: String?
    var prefillAppName: String?
    /// Forces the rule editor into a specific rule type (app vs
    /// calendar) when opening from a source that already knows which
    /// one applies — e.g. the calendar-column context menu. Task 16
    /// will make the sheet honor this value.
    var prefillRuleType: RuleType?
    /// Event title to seed the calendar rule's match pattern when the
    /// editor is opened from a calendar event.
    var prefillEventTitle: String?
}

/// Tracks the entry column's global Y origin for drag coordinate conversion.
private struct EntryColumnOriginKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// Tracks the entry column's laid-out width so overlapping entries can
/// be split into side-by-side columns of equal fractional width.
private struct EntryColumnWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
