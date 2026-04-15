import AppKit
import SwiftUI

/// Renders a single 30-minute time slot on the timeline.
/// Fixed height derived from `TimeSlot.slotDurationMinutes`; positioned by
/// the parent via offset.
struct TimeSlotView: View {
    let slot: TimeSlot
    let isSelected: Bool
    var rulesEnabled: Bool = true
    var columnWidth: CGFloat = TimelineLayout.appUsagePaneWidth
    var onSelect: (_ shiftHeld: Bool) -> Void = { _ in }
    var onCreateRule: ((_ bundleId: String, _ appName: String) -> Void)?
    var onCreateEntry: ((TimeSlot) -> Void)?
    var onDragStarted: () -> Void = {}
    var onDragUpdated: (_ targetY: CGFloat) -> Void = { _ in }
    var onDragEnded: () -> Void = {}
    @Environment(\.theme) private var theme
    @Environment(\.entryFontSizeBoost) private var fontBoost
    @State private var isDragging: Bool = false
    @State private var appIcon: NSImage?
    @State private var showPopover: Bool = false
    @State private var isHovered: Bool = false

    private var height: CGFloat {
        CGFloat(TimeSlot.slotDurationMinutes) * TimelineLayout.pixelsPerMinute
    }

    private func resolveAppIcon() {
        guard appIcon == nil else { return }
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: slot.dominantBundleId)
        if let url {
            appIcon = NSWorkspace.shared.icon(forFile: url.path)
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left color accent bar
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.accentColor.opacity(0.6))
                .frame(width: 3)

            // App icon
            if let appIcon {
                Image(nsImage: appIcon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 16, height: 16)
                    .padding(.leading, 5)
            }

            VStack(alignment: .leading, spacing: 1) {
                // Dominant app name + duration
                HStack(spacing: 4) {
                    Text(slot.dominantAppName)
                        .font(.system(size: Theme.FontSize.subhead + fontBoost, weight: .medium))
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer(minLength: 0)

                    Text(slot.dominantDurationLabel)
                        .font(.system(size: Theme.FontSize.caption + fontBoost, design: .monospaced))
                        .foregroundStyle(theme.textTertiary)
                }

                // Window title (if available)
                if let title = slot.dominantWindowTitle {
                    Text(title)
                        .font(.system(size: Theme.FontSize.caption + fontBoost))
                        .foregroundStyle(theme.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                // Contributing apps summary
                if !slot.contributingApps.isEmpty {
                    let summary = slot.contributingApps
                        .map { "\($0.appName) \($0.durationLabel)" }
                        .joined(separator: ", ")
                    Text(summary)
                        .font(.system(size: Theme.FontSize.caption + fontBoost))
                        .foregroundStyle(theme.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .padding(.horizontal, 5)

            Spacer(minLength: 0)
        }
        .onAppear { resolveAppIcon() }
        .onChange(of: slot.dominantBundleId) { _, _ in
            appIcon = nil
            resolveAppIcon()
        }
        .frame(width: columnWidth - 8, height: height)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                .stroke(Color.accentColor, lineWidth: 2)
                .opacity(isHovered || isSelected ? 1 : 0)
        }
        .onHover { hovering in
            isHovered = hovering
            if hovering && !isDragging {
                onSelect(false)
                showPopover = true
            } else if !hovering {
                showPopover = false
            }
        }
        .popover(isPresented: $showPopover, arrowEdge: .trailing) {
            hoverPopover
        }
        .opacity(isDragging ? 0.5 : 1.0)
        .gesture(
            DragGesture(minimumDistance: 8, coordinateSpace: .global)
                .onChanged { value in
                    if !isDragging {
                        isDragging = true
                        onDragStarted()
                    }
                    onDragUpdated(value.location.y)
                }
                .onEnded { _ in
                    isDragging = false
                    onDragEnded()
                }
        )
        .onTapGesture(count: 1) {
            onSelect(NSEvent.modifierFlags.contains(.shift))
            if !showPopover { showPopover = true }
        }
        .onTapGesture(count: 2) {
            onCreateEntry?(slot)
        }
        .contextMenu {
            Button(String(localized: "Create entry from this slot\u{2026}")) {
                onCreateEntry?(slot)
            }
            if rulesEnabled {
                Button(String(localized: "Create rule for \"\(slot.dominantAppName)\"\u{2026}")) {
                    onCreateRule?(slot.dominantBundleId, slot.dominantAppName)
                }
            }
        }
    }

    // MARK: - Hover Popover

    private var hoverPopover: some View {
        HStack(spacing: 8) {
            if let appIcon {
                Image(nsImage: appIcon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 24, height: 24)
            } else {
                Image(systemName: "app.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(theme.textTertiary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("\(slot.dominantAppName) \u{2014} \(slot.dominantDurationLabel)")
                    .font(.system(size: Theme.FontSize.body + fontBoost, weight: .medium))
                    .foregroundStyle(theme.textPrimary)
                Text("\(slot.startTimeLabel) \u{2013} \(slot.endTimeLabel)")
                    .font(.system(size: Theme.FontSize.caption + fontBoost, design: .monospaced))
                    .foregroundStyle(theme.textSecondary)
                if let title = slot.dominantWindowTitle {
                    Text(title)
                        .font(.system(size: Theme.FontSize.caption + fontBoost))
                        .foregroundStyle(theme.textSecondary)
                }
                if !slot.contributingApps.isEmpty {
                    ForEach(Array(slot.contributingApps), id: \.bundleId) { contrib in
                        Text("\u{2022} \(contrib.appName): \(contrib.durationLabel)")
                            .font(.system(size: Theme.FontSize.caption + fontBoost))
                            .foregroundStyle(theme.textTertiary)
                    }
                }
            }
        }
        .padding(10)
    }
}
