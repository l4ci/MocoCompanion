import SwiftUI

/// Empty state shown in the Log tab when no activities exist for the selected day.
struct TodayEmptyState: View {
    var isYesterday: Bool = false

    @Environment(\.theme) private var theme
    @Environment(\.entryFontSizeBoost) private var fontBoost

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "clock")
                .font(.system(size: 22 + fontBoost))
                .foregroundStyle(theme.textTertiary)
            Text(isYesterday ? String(localized: "yesterday.noEntries") : String(localized: "today.noEntries"))
                .font(.system(size: 15 + fontBoost, weight: .medium))
                .foregroundStyle(theme.textSecondary)
            if !isYesterday {
                Text(String(localized: "today.pressTab"))
                    .font(.system(size: 13 + fontBoost))
                    .foregroundStyle(theme.textTertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isYesterday ? "No entries yesterday" : "No entries today. Press Tab to search.")
    }
}
