import SwiftUI

/// Row rendered in the aboveline calendar column for all-day events.
/// Draggable; dropping on the timeline creates a 1-hour Moco entry
/// pre-filled with the meeting title.
struct AllDayCalendarEventRow: View {
    let event: CalendarEvent
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 1)
                .fill(event.color)
                .frame(width: 3, height: 14)
            Text(event.title)
                .font(.system(size: Theme.FontSize.caption, weight: .medium))
                .foregroundStyle(theme.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .fixedSize(horizontal: false, vertical: true)
        .background(
            theme.surface,
            in: RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
        )
        .help(event.title)
    }
}
