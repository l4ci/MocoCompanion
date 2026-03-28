import SwiftUI

/// Stats footer for the Today tab showing total hours, billable %, and entry count.
struct TodayStatsFooter: View {
    let totalHours: Double
    let billablePercentage: Double
    let entryCount: Int

    @Environment(\.theme) private var theme
    @Environment(\.entryFontSizeBoost) private var fontBoost

    var body: some View {
        VStack(spacing: 0) {
            theme.divider.frame(height: 1)

            HStack(spacing: 8) {
                statCard(label: String(localized: "stats.total"), value: String(format: "%.1fh", totalHours))
                statCard(label: String(localized: "stats.billable"), value: String(format: "%.0f%%", billablePercentage))
                statCard(label: String(localized: "stats.entries"), value: "\(entryCount)")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
    }

    private func statCard(label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 12 + fontBoost, weight: .semibold))
                .foregroundStyle(theme.textTertiary)
                .textCase(.uppercase)
                .tracking(0.3)
            Text(value)
                .font(.system(size: 18 + fontBoost, weight: .semibold, design: .rounded))
                .foregroundStyle(theme.textPrimary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(theme.statCardBackground)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}
