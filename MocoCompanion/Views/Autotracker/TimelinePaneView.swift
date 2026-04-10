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
    @Environment(\.theme) private var theme
    @State private var pendingCreation: (startMinutes: Int, durationMinutes: Int, appName: String)?
    @State private var ruleEditorConfig: RuleEditorConfig?
    /// Tracks the entry column's origin in global coordinate space for drag target conversion.
    @State private var entryColumnGlobalOrigin: CGFloat = 0

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

            // Main timeline
            if positionedEntries.isEmpty && appUsageBlocks.isEmpty && unpositionedEntries.isEmpty {
                emptyState
            } else if positionedEntries.isEmpty && appUsageBlocks.isEmpty {
                // Only unpositioned entries exist — show a subtle note in the scroll area
                Spacer()
                Text("No timed entries for this day")
                    .font(.system(size: Theme.FontSize.body))
                    .foregroundStyle(theme.textTertiary)
                Spacer()
            } else {
                scrollableTimeline
            }
        }
        .sheet(item: $ruleEditorConfig) { config in
            if let ruleStore = viewModel.ruleStore {
                RuleEditorSheet(
                    existingRule: nil,
                    prefillBundleId: config.prefillBundleId,
                    prefillAppName: config.prefillAppName,
                    ruleStore: ruleStore,
                    projectCatalog: projectCatalog,
                    onSave: {
                        Task { await viewModel.loadData() }
                    }
                )
            }
        }
        .sheet(isPresented: showCreationSheet) {
            if let creation = pendingCreation {
                let dateStr = TimelineViewModel.dateString(from: selectedDate)
                let startTimeStr = TimelineViewModel.timeString(fromMinutes: creation.startMinutes)
                TimelineEntryCreationSheet(
                    date: dateStr,
                    startTime: startTimeStr,
                    durationMinutes: creation.durationMinutes,
                    suggestedDescription: creation.appName,
                    projectCatalog: projectCatalog,
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
                                description: description
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

    private var scrollableTimeline: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                ZStack(alignment: .topLeading) {
                    // Grid background
                    TimeAxisGridBackground()

                    // Panes
                    HStack(alignment: .top, spacing: 0) {
                        // Time axis
                        TimeAxisView()

                        // App usage column
                        appUsageColumn
                            .frame(width: TimelineLayout.appUsagePaneWidth)

                        // Entry column
                        entryColumn
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }

                    // Now line overlay
                    if isToday {
                        NowLineView()
                    }

                    // Scroll anchor
                    Color.clear
                        .frame(width: 1, height: 1)
                        .id("scrollAnchor")
                        .offset(y: scrollAnchorY)
                }
                .frame(height: TimelineLayout.totalHeight)
            }
            .onAppear {
                proxy.scrollTo("scrollAnchor", anchor: .center)
            }
            .onChange(of: selectedDate) {
                proxy.scrollTo("scrollAnchor", anchor: .center)
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
        ZStack(alignment: .topLeading) {
            ForEach(appUsageBlocks) { block in
                AppUsageBlockView(
                    block: block,
                    isSelected: viewModel.selectedAppBlockIds.contains(block.id),
                    onSelect: { shiftHeld in
                        viewModel.toggleAppBlockSelection(id: block.id, shiftHeld: shiftHeld)
                    },
                    onCreateRule: { bundleId, appName in
                        ruleEditorConfig = RuleEditorConfig(prefillBundleId: bundleId, prefillAppName: appName)
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
            ForEach(positionedEntries, id: \.id) { entry in
                EntryBlockView(entry: entry, viewModel: viewModel)
                    .padding(.horizontal, 4)
                    .offset(y: yOffsetFromTimeString(entry.startTime))
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
        .background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: EntryColumnOriginKey.self,
                    value: geo.frame(in: .global).minY
                )
            }
        )
        .onPreferenceChange(EntryColumnOriginKey.self) { value in
            entryColumnGlobalOrigin = value
        }
    }

    // MARK: - Ghost Block

    private func ghostBlock(for drag: TimelineViewModel.DragCreationState) -> some View {
        let yPos = CGFloat(drag.startMinutes) * TimelineLayout.pixelsPerMinute
        let height = max(CGFloat(drag.durationMinutes) * TimelineLayout.pixelsPerMinute, 12)
        let tint: Color = drag.isOverlapping ? .orange : .accentColor
        let startLabel = TimelineViewModel.timeString(fromMinutes: drag.startMinutes)
        let endLabel = TimelineViewModel.timeString(fromMinutes: drag.startMinutes + drag.durationMinutes)

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
