import SwiftUI

/// Reusable duration display for an activity.
/// Shows live-updating elapsed time for running activities,
/// static compact hours for stopped ones.
struct ActivityDurationText: View {
    let activity: ShadowEntry
    let isSelected: Bool

    var font: Font? = nil
    var runningColor: Color = .green
    var stoppedOpacity: Double = 0.5

    @Environment(\.entryFontSizeBoost) private var fontBoost
    @Environment(\.theme) private var theme

    /// Resolved font — uses the explicit font if provided, otherwise scales with the entry boost.
    private var resolvedFont: Font {
        font ?? .system(size: 15 + fontBoost, weight: .medium, design: .monospaced)
    }

    var body: some View {
        if activity.isTimerRunning,
           let startedAt = activity.timerStartedAt,
           let startDate = DateUtilities.parseISO8601(startedAt) {
            let baseSecs = Double(activity.seconds)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let liveSecs = baseSecs + context.date.timeIntervalSince(startDate)
                Text(DateUtilities.formatElapsedCompact(liveSecs))
                    .font(resolvedFont)
                    .foregroundStyle(isSelected ? theme.selectedTextPrimary : runningColor)
                    .accessibilityLabel(String(localized: "a11y.timerRunningDuration \(DateUtilities.formatElapsedCompact(liveSecs))"))
            }
        } else {
            Text(DateUtilities.formatHoursCompact(activity.hours))
                .font(resolvedFont)
                .foregroundStyle(isSelected ? theme.selectedTextSecondary : .primary.opacity(stoppedOpacity))
                .accessibilityLabel(String(localized: "a11y.hoursTracked \(DateUtilities.formatHoursCompact(activity.hours))"))
        }
    }
}

/// Large padded elapsed time display (HH:MM:SS) for the status popover timer section.
struct ElapsedTimeText: View {
    let activity: ShadowEntry?

    var body: some View {
        if let activity,
           let startedAt = activity.timerStartedAt,
           let startDate = DateUtilities.parseISO8601(startedAt) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let elapsed = context.date.timeIntervalSince(startDate)
                Text(DateUtilities.formatElapsedPadded(elapsed))
                    .font(.system(size: 18, weight: .medium, design: .monospaced))
                    .foregroundStyle(.primary)
            }
        } else {
            Text("--:--:--")
                .font(.system(size: 18, weight: .medium, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
    }
}
