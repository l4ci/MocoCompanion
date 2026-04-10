import SwiftUI

/// Renders a single Moco entry block on the timeline.
/// Displays project name, task name, description, lock state, and running timer state.
/// Supports drag-move and edge-resize gestures with 5-minute snap grid.
struct EntryBlockView: View {
    let entry: ShadowEntry
    let viewModel: TimelineViewModel
    var onEdit: ((ShadowEntry) -> Void)? = nil
    @Environment(\.theme) private var theme

    // MARK: - Gesture State

    @State private var dragOffset: CGFloat = 0
    @State private var isDragging: Bool = false
    @State private var topResizeOffset: CGFloat = 0
    @State private var isResizingTop: Bool = false
    @State private var bottomResizeOffset: CGFloat = 0
    @State private var isResizingBottom: Bool = false

    private var isGestureActive: Bool {
        isDragging || isResizingTop || isResizingBottom
    }

    // MARK: - Computed

    private var isRunning: Bool {
        entry.timerStartedAt != nil
    }

    /// Base height in points based on entry seconds (or elapsed time for running timer).
    private var baseHeight: CGFloat {
        let seconds: CGFloat
        if isRunning, let startedAt = parsedTimerStart {
            seconds = CGFloat(max(Date().timeIntervalSince(startedAt), 60))
        } else {
            seconds = CGFloat(entry.seconds)
        }
        return max(seconds / 60 * TimelineLayout.pixelsPerMinute, 20)
    }

    /// Height adjusted during resize gestures.
    private var displayHeight: CGFloat {
        var h = baseHeight
        if isResizingTop {
            h -= topResizeOffset
        }
        if isResizingBottom {
            h += bottomResizeOffset
        }
        return max(h, TimelineLayout.pixelsPerMinute * CGFloat(TimelineLayout.snapMinutes))
    }

    private var parsedTimerStart: Date? {
        guard let iso = entry.timerStartedAt else { return nil }
        return ISO8601DateFormatter().date(from: iso)
    }

    private var background: Color {
        if isRunning { return theme.runningTint }
        return theme.surface
    }

    private var originalMinutes: Int {
        TimelineGeometry.minutesSinceMidnight(from: entry.startTime ?? "00:00") ?? 0
    }

    // MARK: - Edge Handle Size

    private static let edgeHandleHeight: CGFloat = 8

    // MARK: - Body

    var body: some View {
        let content = ZStack(alignment: .topLeading) {
            // Main block content
            HStack(spacing: 0) {
                // Left accent bar
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.accentColor)
                    .frame(width: 3)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(entry.projectName)
                            .font(.system(size: Theme.FontSize.footnote, weight: .semibold))
                            .foregroundStyle(theme.textPrimary)
                            .lineLimit(1)

                        if entry.locked {
                            Image(systemName: "lock.fill")
                                .font(.system(size: Theme.FontSize.caption))
                                .foregroundStyle(theme.textTertiary)
                        }
                    }

                    Text(entry.taskName)
                        .font(.system(size: Theme.FontSize.caption))
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)

                    if !entry.description.isEmpty {
                        Text(entry.description)
                            .font(.system(size: Theme.FontSize.caption))
                            .foregroundStyle(theme.textTertiary)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)

                Spacer(minLength: 0)
            }
            .frame(height: displayHeight)
            .background(background, in: RoundedRectangle(cornerRadius: TimelineLayout.blockCornerRadius, style: .continuous))
            .opacity(entry.locked ? 0.7 : isDragging ? 0.85 : 1.0)
            .shadow(color: .black.opacity(isGestureActive ? 0.2 : 0), radius: isGestureActive ? 4 : 0)

            // Edge resize handles (only for unlocked, non-running entries)
            if !entry.locked && !isRunning {
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
        .offset(y: dragOffset + (isResizingTop ? topResizeOffset : 0))
        .gesture(entry.locked || isRunning ? nil : dragMoveGesture)
        .contextMenu {
            if !entry.locked {
                Button("Edit entry…") {
                    onEdit?(entry)
                }
            }
        }
        // When the underlying entry's time/duration changes (after a move
        // or resize completes), reset the visual offsets. This avoids the
        // snap-back flicker: we keep the dragged offset until the new
        // entry data arrives, then the base y-position shifts and the
        // offset clears on the same frame.
        .onChange(of: entry.startTime) { _, _ in
            dragOffset = 0
            topResizeOffset = 0
            isDragging = false
            isResizingTop = false
        }
        .onChange(of: entry.seconds) { _, _ in
            topResizeOffset = 0
            bottomResizeOffset = 0
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
                dragOffset = value.translation.height
                isDragging = true
            }
            .onEnded { value in
                let deltaMinutes = Double(value.translation.height) / Double(TimelineLayout.pixelsPerMinute)
                let newMinutes = TimelineGeometry.snapToGrid(minutes: Double(originalMinutes) + deltaMinutes)
                let newTime = TimelineGeometry.timeString(fromMinutes: newMinutes)
                // Snap the visual offset to the final grid position so the
                // block sits exactly where it will land once the update
                // commits. `.onChange(of: entry.startTime)` clears this
                // offset when the new entry data arrives — same frame as
                // the base y-position updates — so there's no snap-back.
                dragOffset = CGFloat(newMinutes - originalMinutes) * TimelineLayout.pixelsPerMinute
                Task {
                    await viewModel.moveEntry(entry, toStartTime: newTime)
                }
            }
    }

    // MARK: - Top Edge Resize Gesture

    private var topResizeGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                topResizeOffset = value.translation.height
                isResizingTop = true
            }
            .onEnded { value in
                let deltaMinutes = Double(value.translation.height) / Double(TimelineLayout.pixelsPerMinute)
                let newStartMinutes = TimelineGeometry.snapToGrid(minutes: Double(originalMinutes) + deltaMinutes)
                let originalDurationMinutes = entry.seconds / 60
                let movedBy = newStartMinutes - originalMinutes
                let newDurationMinutes = max(originalDurationMinutes - movedBy, TimelineLayout.snapMinutes)
                let newTime = TimelineGeometry.timeString(fromMinutes: newStartMinutes)
                let newDurationSeconds = newDurationMinutes * 60
                // Snap offset to final grid position so the block stays
                // visually where it will land. Cleared by `.onChange` when
                // the data arrives.
                topResizeOffset = CGFloat(movedBy) * TimelineLayout.pixelsPerMinute
                Task {
                    await viewModel.resizeEntry(entry, newStartTime: newTime, newDurationSeconds: newDurationSeconds)
                }
            }
    }

    // MARK: - Bottom Edge Resize Gesture

    private var bottomResizeGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                bottomResizeOffset = value.translation.height
                isResizingBottom = true
            }
            .onEnded { value in
                let deltaMinutes = Double(value.translation.height) / Double(TimelineLayout.pixelsPerMinute)
                let originalDurationMinutes = entry.seconds / 60
                let newDurationMinutes = max(originalDurationMinutes + Int(round(deltaMinutes / Double(TimelineLayout.snapMinutes))) * TimelineLayout.snapMinutes, TimelineLayout.snapMinutes)
                let newDurationSeconds = newDurationMinutes * 60
                // Snap visual offset to the final grid height so the block
                // stays at its committed size until the new entry data
                // arrives (cleared by `.onChange(of: entry.seconds)`).
                bottomResizeOffset = CGFloat(newDurationMinutes - originalDurationMinutes) * TimelineLayout.pixelsPerMinute
                Task {
                    await viewModel.resizeEntry(entry, newStartTime: entry.startTime ?? "00:00", newDurationSeconds: newDurationSeconds)
                }
            }
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
