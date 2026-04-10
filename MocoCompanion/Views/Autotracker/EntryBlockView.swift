import SwiftUI

/// Renders a single Moco entry block on the timeline.
/// Displays project name, task name, description, lock state, and running timer state.
/// Supports drag-move and edge-resize gestures with 5-minute snap grid.
struct EntryBlockView: View {
    let entry: ShadowEntry
    let viewModel: TimelineViewModel
    let projectCatalog: ProjectCatalog
    var isHighlighted: Bool = false
    var onEdit: ((ShadowEntry) -> Void)? = nil
    var onDelete: ((ShadowEntry) -> Void)? = nil
    var onSelect: (() -> Void)? = nil
    @Environment(\.theme) private var theme

    /// Height threshold below which the three-line layout is collapsed
    /// into a single compact row (project — task — description).
    private static let compactThreshold: CGFloat = 44

    private var isCompact: Bool {
        displayHeight < Self.compactThreshold
    }

    /// Full info string used for the hover tooltip — always shown, both
    /// compact and expanded variants.
    private var tooltipLabel: String {
        var lines: [String] = [entry.projectName]
        if !entry.taskName.isEmpty { lines.append(entry.taskName) }
        if !entry.description.isEmpty { lines.append(entry.description) }
        if let start = entry.startTime {
            lines.append("\(start) • \(durationLabel)")
        }
        return lines.joined(separator: "\n")
    }

    /// Human-friendly duration string, e.g. "1h 30min", "45min".
    private var durationLabel: String {
        let totalMinutes = max(entry.seconds / 60, 0)
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        if h > 0 && m > 0 { return "\(h)h \(m)min" }
        if h > 0 { return "\(h)h" }
        return "\(m)min"
    }

    // MARK: - Gesture State

    /// Gesture target state. When non-nil, overrides the values derived
    /// from the `entry` prop. The key design point: these are cleared
    /// ONLY after the underlying entry has caught up to the target, so
    /// the effective (displayed) value is identical before and after
    /// the clear — eliminating the resize/drag flicker that plagued
    /// offset-based approaches.
    @State private var dragTargetMinutes: Int?
    @State private var resizeTargetSeconds: Int?
    @State private var isDragging: Bool = false
    @State private var isResizingTop: Bool = false
    @State private var isResizingBottom: Bool = false
    @State private var showDeleteConfirm: Bool = false

    private var isGestureActive: Bool {
        isDragging || isResizingTop || isResizingBottom
    }

    // MARK: - Computed

    private var isRunning: Bool {
        entry.timerStartedAt != nil
    }

    /// Start minutes for layout — either the gesture target or the
    /// entry's current value if no gesture is in flight.
    private var effectiveStartMinutes: Int {
        dragTargetMinutes ?? entryStartMinutes
    }

    private var entryStartMinutes: Int {
        TimelineGeometry.minutesSinceMidnight(from: entry.startTime ?? "00:00") ?? 0
    }

    /// Duration in seconds — gesture target wins while a resize is live
    /// or pending the VM round-trip.
    private var effectiveSeconds: Int {
        resizeTargetSeconds ?? entry.seconds
    }

    /// Height in points. During a running timer, grows with elapsed
    /// wall-clock seconds; otherwise derived from `effectiveSeconds`.
    private var baseHeight: CGFloat {
        let seconds: CGFloat
        if isRunning, let startedAt = parsedTimerStart {
            seconds = CGFloat(max(Date().timeIntervalSince(startedAt), 60))
        } else {
            seconds = CGFloat(effectiveSeconds)
        }
        return max(seconds / 60 * TimelineLayout.pixelsPerMinute, 20)
    }

    /// Display height — alias for baseHeight now that resize uses
    /// target-based seconds instead of an offset overlay.
    private var displayHeight: CGFloat {
        max(baseHeight, TimelineLayout.pixelsPerMinute * CGFloat(TimelineLayout.snapMinutes))
    }

    /// Visual Y offset applied on top of the parent's `entry.startTime`-
    /// based position. Computed as the delta between the gesture's
    /// intended start and the entry's current start — it decays to zero
    /// automatically as the entry catches up to the target, so the
    /// clear in `onChange` is a no-op visually.
    private var visualYOffset: CGFloat {
        let delta = effectiveStartMinutes - entryStartMinutes
        return CGFloat(delta) * TimelineLayout.pixelsPerMinute
    }

    private var parsedTimerStart: Date? {
        guard let iso = entry.timerStartedAt else { return nil }
        return ISO8601DateFormatter().date(from: iso)
    }

    private var background: Color {
        if isRunning { return theme.runningTint }
        return theme.surface
    }

    /// Project color from Moco catalog, falling back to a stable hash-based palette color.
    private var projectColor: Color {
        projectCatalog.color(for: entry.projectId) ?? ProjectColorPalette.color(for: entry.projectId)
    }

    // MARK: - Text Layouts

    /// Three-line layout used when the entry is tall enough (>= 44pt).
    private var expandedTextContent: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(entry.projectName)
                .font(.system(size: Theme.FontSize.body, weight: .semibold))
                .foregroundStyle(theme.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)

            Text(entry.taskName)
                .font(.system(size: Theme.FontSize.subhead))
                .foregroundStyle(theme.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)

            if !entry.description.isEmpty {
                Text(entry.description)
                    .font(.system(size: Theme.FontSize.subhead))
                    .foregroundStyle(theme.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }

    /// Single-row layout used when the entry is short. Puts project name
    /// first (bold) and appends the task + description inline, separated
    /// by bullets, with a tail ellipsis so it never overflows the row.
    private var compactTextContent: some View {
        HStack(spacing: 6) {
            Text(entry.projectName)
                .font(.system(size: Theme.FontSize.subhead, weight: .semibold))
                .foregroundStyle(theme.textPrimary)
                .lineLimit(1)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)

            Text(inlineSecondaryText)
                .font(.system(size: Theme.FontSize.subhead))
                .foregroundStyle(theme.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    /// Task + description merged into a single string for the compact row.
    private var inlineSecondaryText: String {
        var parts: [String] = []
        if !entry.taskName.isEmpty { parts.append(entry.taskName) }
        if !entry.description.isEmpty { parts.append(entry.description) }
        return parts.joined(separator: " • ")
    }

    // MARK: - Icon Badges

    private var iconBadges: some View {
        EntryStatusIcons(
            syncStatus: entry.syncStatus,
            isLocked: entry.locked,
            isBilled: entry.billed,
            isLinkedToAppBlock: viewModel.isLinkedToAppBlock(entry),
            isFromRule: entry.sourceRuleId != nil
        )
    }

    // MARK: - Edge Handle Size

    private static let edgeHandleHeight: CGFloat = 8

    // MARK: - Body

    var body: some View {
        let content = ZStack(alignment: .topLeading) {
            // Main block content
            HStack(spacing: 0) {
                // Left accent bar — colored per project
                RoundedRectangle(cornerRadius: 1)
                    .fill(projectColor)
                    .frame(width: 3)

                ZStack {
                    // Text content — compact or expanded. Fills the cell,
                    // leaves room on the right for the icons column and on
                    // the bottom for the duration label.
                    Group {
                        if isCompact {
                            compactTextContent
                        } else {
                            expandedTextContent
                        }
                    }
                    .padding(.trailing, 40) // room for icons
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                    // Status icons — always pinned top-right regardless
                    // of entry height.
                    iconBadges
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

                    // Duration badge — bottom-right. Hidden on ultra-
                    // short entries that don't have room for a second
                    // row of text.
                    if !isCompact {
                        Text(durationLabel)
                            .font(.system(size: Theme.FontSize.footnote, design: .rounded).monospacedDigit())
                            .foregroundStyle(theme.textTertiary)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, isCompact ? 3 : 4)
            }
            .frame(height: displayHeight)
            .background(background, in: RoundedRectangle(cornerRadius: TimelineLayout.blockCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: TimelineLayout.blockCornerRadius, style: .continuous)
                    .stroke(Color.accentColor, lineWidth: 2)
                    .opacity(isHighlighted ? 1 : 0)
            )
            .opacity(entry.isReadOnly ? 0.7 : isDragging ? 0.85 : 1.0)
            .shadow(color: .black.opacity(isGestureActive ? 0.2 : 0), radius: isGestureActive ? 4 : 0)

            // Edge resize handles (only for unlocked, non-running entries)
            if !entry.isReadOnly && !isRunning {
                // Top edge handle
                Color.clear
                    .frame(height: Self.edgeHandleHeight)
                    .contentShape(Rectangle())
                    .cursor(.resizeUpDown)
                    .gesture(topResizeGesture)

                // Bottom edge handle
                VStack {
                    Spacer()
                    Color.clear
                        .frame(height: Self.edgeHandleHeight)
                        .contentShape(Rectangle())
                        .cursor(.resizeUpDown)
                        .gesture(bottomResizeGesture)
                }
                .frame(height: displayHeight)
            }
        }
        .help(tooltipLabel)
        .offset(y: visualYOffset)
        // Never animate positional/size changes on this block — the
        // preview-target state uses identity math (visualYOffset reaches
        // zero the instant entry.startTime catches up), so any implicit
        // animation would tween across correct identical values and
        // visibly wobble.
        .animation(nil, value: visualYOffset)
        .animation(nil, value: displayHeight)
        .animation(nil, value: dragTargetMinutes)
        .animation(nil, value: resizeTargetSeconds)
        .gesture(entry.isReadOnly || isRunning ? nil : dragMoveGesture)
        .onTapGesture(count: 1) {
            onSelect?()
        }
        .onTapGesture(count: 2) {
            if !entry.isReadOnly {
                onEdit?(entry)
            }
        }
        .contextMenu {
            if !entry.isReadOnly {
                Button("Edit entry…") {
                    onEdit?(entry)
                }
                Divider()
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .confirmationDialog(
            "Delete this entry?",
            isPresented: $showDeleteConfirm
        ) {
            Button("Delete", role: .destructive) {
                onDelete?(entry)
            }
            .keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) { }
                .keyboardShortcut(.cancelAction)
        } message: {
            Text("You can undo this for 5 seconds.")
        }
        // Clear the gesture targets once the underlying entry has caught
        // up to them. Because `effectiveStartMinutes` and `effectiveSeconds`
        // fall back to the entry when the target matches, the visual is
        // byte-for-byte identical before and after the clear — no flicker.
        .onChange(of: entry.startTime) { _, _ in
            if dragTargetMinutes == entryStartMinutes {
                dragTargetMinutes = nil
            }
            isDragging = false
            isResizingTop = false
        }
        .onChange(of: entry.seconds) { _, _ in
            if resizeTargetSeconds == entry.seconds {
                resizeTargetSeconds = nil
            }
            isResizingTop = false
            isResizingBottom = false
        }

        if isRunning {
            TimelineView(.periodic(from: .now, by: 60)) { _ in
                content
            }
        } else {
            content
        }
    }

    // MARK: - Drag-Move Gesture

    private var dragMoveGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                isDragging = true
                let newMinutes = snappedStartMinutes(gestureDelta: value.translation.height)
                dragTargetMinutes = newMinutes
            }
            .onEnded { value in
                let newMinutes = snappedStartMinutes(gestureDelta: value.translation.height)
                dragTargetMinutes = newMinutes
                let newTime = TimelineGeometry.timeString(fromMinutes: newMinutes)
                Task {
                    await viewModel.moveEntry(entry, toStartTime: newTime)
                }
            }
    }

    // MARK: - Top Edge Resize Gesture

    private var topResizeGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                isResizingTop = true
                let (newStart, newDurationMinutes) = snappedTopResize(gestureDelta: value.translation.height)
                dragTargetMinutes = newStart
                resizeTargetSeconds = newDurationMinutes * 60
            }
            .onEnded { value in
                let (newStart, newDurationMinutes) = snappedTopResize(gestureDelta: value.translation.height)
                dragTargetMinutes = newStart
                resizeTargetSeconds = newDurationMinutes * 60
                let newTime = TimelineGeometry.timeString(fromMinutes: newStart)
                let newDurationSeconds = newDurationMinutes * 60
                Task { @MainActor in
                    await viewModel.resizeEntry(entry, newStartTime: newTime, newDurationSeconds: newDurationSeconds)
                }
            }
    }

    // MARK: - Bottom Edge Resize Gesture

    private var bottomResizeGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                isResizingBottom = true
                let newDurationMinutes = snappedBottomDuration(gestureDelta: value.translation.height)
                resizeTargetSeconds = newDurationMinutes * 60
            }
            .onEnded { value in
                let newDurationMinutes = snappedBottomDuration(gestureDelta: value.translation.height)
                resizeTargetSeconds = newDurationMinutes * 60
                let newDurationSeconds = newDurationMinutes * 60
                Task { @MainActor in
                    await viewModel.resizeEntry(entry, newStartTime: entry.startTime ?? "00:00", newDurationSeconds: newDurationSeconds)
                }
            }
    }

    // MARK: - Snap Helpers

    /// Compute the snapped start minute for a drag-move gesture with the given pixel delta.
    private func snappedStartMinutes(gestureDelta: CGFloat) -> Int {
        let deltaMinutes = Double(gestureDelta) / Double(TimelineLayout.pixelsPerMinute)
        return TimelineGeometry.snapToGrid(
            minutes: Double(entryStartMinutes) + deltaMinutes,
            gridMinutes: TimelineLayout.snapMinutes
        )
    }

    /// Compute the snapped (startMinutes, durationMinutes) pair for a top-edge resize.
    /// The bottom edge stays put, so duration shrinks by the same amount the top moves.
    private func snappedTopResize(gestureDelta: CGFloat) -> (Int, Int) {
        let deltaMinutes = Double(gestureDelta) / Double(TimelineLayout.pixelsPerMinute)
        let newStartMinutes = TimelineGeometry.snapToGrid(
            minutes: Double(entryStartMinutes) + deltaMinutes,
            gridMinutes: TimelineLayout.snapMinutes
        )
        let originalDurationMinutes = entry.seconds / 60
        let movedBy = newStartMinutes - entryStartMinutes
        let newDurationMinutes = max(originalDurationMinutes - movedBy, TimelineLayout.snapMinutes)
        return (newStartMinutes, newDurationMinutes)
    }

    /// Compute the snapped duration in minutes for a bottom-edge resize.
    private func snappedBottomDuration(gestureDelta: CGFloat) -> Int {
        let deltaMinutes = Double(gestureDelta) / Double(TimelineLayout.pixelsPerMinute)
        let originalDurationMinutes = entry.seconds / 60
        return max(
            originalDurationMinutes + Int(round(deltaMinutes / Double(TimelineLayout.snapMinutes))) * TimelineLayout.snapMinutes,
            TimelineLayout.snapMinutes
        )
    }
}

// MARK: - Cursor Helper

private extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        onHover { inside in
            if inside {
                cursor.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}
