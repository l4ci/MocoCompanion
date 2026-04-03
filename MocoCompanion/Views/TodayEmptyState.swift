import SwiftUI

/// Empty state shown in the Log tab when no activities exist for the selected day.
/// Uses warm, contextual illustrations instead of generic icons to give the panel personality
/// in the moments between productivity.
struct TodayEmptyState: View {
    var isYesterday: Bool = false

    @Environment(\.theme) private var theme
    @Environment(\.entryFontSizeBoost) private var fontBoost

    private var illustration: String {
        isYesterday ? "tray" : "cup.and.heat.waves"
    }

    private var heading: String {
        isYesterday
            ? String(localized: "yesterday.noEntries")
            : String(localized: "today.noEntries")
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: illustration)
                .font(.system(size: 28 + fontBoost, weight: .light))
                .foregroundStyle(theme.textTertiary.opacity(0.7))
                .frame(height: 36)

            Text(heading)
                .font(.system(size: 15 + fontBoost, weight: .medium))
                .foregroundStyle(theme.textSecondary)

            if !isYesterday {
                Text(String(localized: "today.pressTab"))
                    .font(.system(size: 13 + fontBoost))
                    .foregroundStyle(theme.textTertiary)
                    .padding(.horizontal, 32)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isYesterday ? String(localized: "a11y.noEntriesYesterday") : String(localized: "a11y.noEntriesToday"))
    }
}
