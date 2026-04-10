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
    @State private var ruleEditorConfig: RuleEditorConfig?
    @State private var editingEntry: EditingEntryWrapper?
    @State private var entryPendingDelete: ShadowEntry?

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

            // Unassigned entries section
            if !unpositionedEntries.isEmpty {
                unassignedSection
                Divider()
            }

            // Column headers pinned to the top of the pane (directly below
            // the date-nav divider). Kept OUT of any ScrollViewReader so
            // its layout is unambiguous — the headers are siblings of the
            // ScrollView, not children of a nested VStack that can get
            // squeezed when wrapping a flexible ScrollView.
            columnHeaders
            theme.divider.frame(height: 1)

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
                                sourceAppBundleId: creation.sourceBundleId
                            )
                        }
                        pendingCreation = nil
                    },
                    onCancel: {
                        pendingCreation = nil
                    }
                )
            }
        }
    }

    private var showCreationSheet: Binding<Bool> {
        Binding(
            get: { pendingCreation != nil },
            set: { if !$0 { pendingCreation = nil } }
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

    // MARK: - Unassigned Section

    private var unassignedSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Unassigned")
                .font(.system(size: Theme.FontSize.footnote, weight: .semibold))
                .foregroundStyle(theme.textSecondary)

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
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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

                    // Panes
                    HStack(alignment: .top, spacing: 0) {
                        // Time axis
                        TimeAxisView()

                        // App usage column
                        appUsageColumn
                            .frame(width: TimelineLayout.appUsagePaneWidth)

                        // Column divider
                        theme.divider
                            .frame(width: 1, height: TimelineLayout.totalHeight)

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

    // MARK: - Column Headers

    private var columnHeaders: some View {
        HStack(alignment: .center, spacing: 0) {
            // Spacer for time axis
            Color.clear
                .frame(width: TimelineLayout.timeAxisWidth)

            Text("Recorded Activities")
                .font(.system(size: Theme.FontSize.footnote, weight: .semibold))
                .foregroundStyle(theme.textSecondary)
                .frame(width: TimelineLayout.appUsagePaneWidth, alignment: .leading)
                .padding(.leading, 4)

            theme.divider
                .frame(width: 1, height: 16)

            Text("Booked Entries")
                .font(.system(size: Theme.FontSize.footnote, weight: .semibold))
                .foregroundStyle(theme.textSecondary)
                .padding(.leading, 8)

            Spacer(minLength: 0)

            // Sync indicator lives on the right edge of the header row,
            // horizontally aligned with the column labels.
            syncIndicator
                .padding(.trailing, 10)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
    }

    // MARK: - Sync Indicator

    @State private var syncLabelTick = Date()

    private var syncIndicator: some View {
        HStack(spacing: 6) {
            let _ = syncLabelTick
            if let lastSync = viewModel.lastSyncedAt {
                Text(Self.relativeTimeString(since: lastSync))
                    .font(.system(size: Theme.FontSize.footnote))
                    .foregroundStyle(theme.textTertiary)
                    .monospacedDigit()
            } else {
                Text("Not synced")
                    .font(.system(size: Theme.FontSize.footnote))
                    .foregroundStyle(theme.textTertiary)
            }

            Button {
                Task { await viewModel.refreshData() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: Theme.FontSize.subhead, weight: .medium))
                    .foregroundStyle(theme.textTertiary)
                    .rotationEffect(viewModel.isRefreshing || viewModel.isSyncing ? .degrees(360) : .zero)
                    .animation(
                        viewModel.isRefreshing || viewModel.isSyncing
                            ? .linear(duration: 0.8).repeatForever(autoreverses: false)
                            : .default,
                        value: viewModel.isRefreshing || viewModel.isSyncing
                    )
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isRefreshing || viewModel.isSyncing)
            .accessibilityLabel(String(localized: "sync.refresh"))
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                syncLabelTick = Date()
            }
        }
    }

    private static func relativeTimeString(since date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 5 { return String(localized: "sync.now") }
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        return "\(hours)h"
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
        .frame(height: TimelineLayout.totalHeight, alignment: .topLeading)
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
                EntryBlockView(
                    entry: entry,
                    viewModel: viewModel,
                    projectCatalog: projectCatalog,
                    isHighlighted: viewModel.isEntryHighlighted(entry),
                    onEdit: { e in editingEntry = EditingEntryWrapper(entry: e) },
                    onDelete: { e in Task { await viewModel.deleteEntry(e) } },
                    onSelect: { viewModel.toggleEntrySelection(entry) }
                )
                    .frame(width: max(columnWidth - gap, 20), alignment: .topLeading)
                    .offset(
                        x: 4 + columnWidth * CGFloat(layout.columnIndex),
                        y: yOffsetFromTimeString(entry.startTime)
                    )
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
        }
        .frame(height: TimelineLayout.totalHeight, alignment: .topLeading)
        .dropDestination(for: String.self) { items, location in
            // Drop payload is the entry id as a String. Convert the local
            // y into minutes-since-midnight, snap to grid, and ask the view
            // model to move the entry there. Works for any ShadowEntry with
            // a server id (unpositioned entries qualify after their first
            // sync round-trip).
            guard let idString = items.first,
                  let id = Int(idString),
                  let entry = viewModel.shadowEntries.first(where: { $0.id == id })
            else { return false }
            let rawMinutes = Double(location.y) / Double(TimelineLayout.pixelsPerMinute)
            let snapped = TimelineGeometry.snapToGrid(
                minutes: rawMinutes,
                gridMinutes: TimelineLayout.snapMinutes
            )
            let timeStr = TimelineGeometry.timeString(fromMinutes: snapped)
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
