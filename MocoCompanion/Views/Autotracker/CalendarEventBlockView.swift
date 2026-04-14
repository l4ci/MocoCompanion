import AppKit
import SwiftUI

/// Renders a single calendar event block on the timeline.
/// Positioned by the parent via offset; height derived from duration.
/// Compact layout (inline title + time range) below 44pt height;
/// expanded layout (time range, title, optional location, duration badge) at or above.
struct CalendarEventBlockView: View {
    let event: CalendarEvent
    let isSelected: Bool
    let isLinked: Bool
    var rulesEnabled: Bool = true
    var onSelect: () -> Void = {}
    var onCreateEntry: () -> Void = {}
    var onCreateRule: () -> Void = {}
    var onOpenInCalendar: () -> Void = {}

    @Environment(\.theme) private var theme
    @Environment(\.entryFontSizeBoost) private var fontBoost
    @State private var showPopover: Bool = false
    @State private var isHovered: Bool = false

    private static let compactThreshold: CGFloat = 44

    private static let timeFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        return fmt
    }()

    private var height: CGFloat {
        max(CGFloat(event.durationMinutes) * TimelineLayout.pixelsPerMinute, 20)
    }

    private var isCompact: Bool { height < Self.compactThreshold }

    private var timeRangeLabel: String {
        "\(Self.timeFormatter.string(from: event.startDate)) – \(Self.timeFormatter.string(from: event.endDate))"
    }

    private var durationLabel: String {
        let h = event.durationMinutes / 60
        let m = event.durationMinutes % 60
        if h > 0 && m > 0 { return "\(h)h \(m)min" }
        if h > 0 { return "\(h)h" }
        return "\(m)min"
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left accent bar using the calendar's color
            RoundedRectangle(cornerRadius: 1)
                .fill(event.color)
                .frame(width: 3)

            if isCompact {
                compactContent
            } else {
                expandedContent
            }
        }
        .frame(height: height)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                .stroke(Color.accentColor, lineWidth: 2)
                .opacity(isHovered || isSelected ? 1 : 0)
        }
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                onSelect()
                if isCompact { showPopover = true }
            } else {
                if isCompact { showPopover = false }
            }
        }
        .popover(isPresented: $showPopover, arrowEdge: .trailing) {
            HStack(spacing: 8) {
                Image(systemName: "calendar")
                    .font(.system(size: 20))
                    .foregroundStyle(event.color)
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.title)
                        .font(.system(size: Theme.FontSize.body + fontBoost, weight: .medium))
                        .foregroundStyle(theme.textPrimary)
                    Text("\(timeRangeLabel) • \(durationLabel)")
                        .font(.system(size: Theme.FontSize.caption + fontBoost, design: .monospaced))
                        .foregroundStyle(theme.textSecondary)
                    if let loc = event.location, !loc.isEmpty {
                        Text(loc)
                            .font(.system(size: Theme.FontSize.caption + fontBoost))
                            .foregroundStyle(theme.textTertiary)
                    }
                }
            }
            .padding(10)
        }
        .onTapGesture(count: 1) {
            onSelect()
            if !showPopover { showPopover = true }
        }
        .onTapGesture(count: 2) { onCreateEntry() }
        .contextMenu {
            Button(String(localized: "calendar.contextMenu.createEntry")) { onCreateEntry() }
            if rulesEnabled {
                Button(String(localized: "calendar.contextMenu.createRule")) { onCreateRule() }
            }
            Divider()
            Button(String(localized: "calendar.contextMenu.openInCalendar")) { onOpenInCalendar() }
        }
    }

    // MARK: - Layouts

    @ViewBuilder
    private var compactContent: some View {
        HStack(spacing: 6) {
            Text(compactTitle)
                .font(.system(size: Theme.FontSize.subhead + fontBoost, weight: .medium))
                .foregroundStyle(theme.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            Text(timeRangeLabel)
                .font(.system(size: Theme.FontSize.caption + fontBoost, design: .monospaced))
                .foregroundStyle(theme.textTertiary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(timeRangeLabel)
                .font(.system(size: Theme.FontSize.caption + fontBoost, design: .monospaced))
                .foregroundStyle(theme.textTertiary)
            Text(event.title)
                .font(.system(size: Theme.FontSize.body + fontBoost, weight: .semibold))
                .foregroundStyle(theme.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
            if let loc = event.location, !loc.isEmpty {
                Text(loc)
                    .font(.system(size: Theme.FontSize.subhead + fontBoost))
                    .foregroundStyle(theme.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 0)
            Text(durationLabel)
                .font(.system(size: Theme.FontSize.footnote + fontBoost, design: .rounded).monospacedDigit())
                .foregroundStyle(theme.textTertiary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
    }

    // MARK: - Helpers

    /// Title text for compact mode. Location appended in parens only when non-empty.
    private var compactTitle: String {
        if let loc = event.location, !loc.isEmpty {
            return "\(event.title) (\(loc))"
        }
        return event.title
    }

    private var helpLabel: String {
        "\(event.title)\n\(timeRangeLabel) • \(durationLabel)"
    }
}
