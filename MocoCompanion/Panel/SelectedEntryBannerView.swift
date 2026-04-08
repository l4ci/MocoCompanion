import SwiftUI

/// Banner showing the selected project/task with a green checkmark.
/// Displayed after the user picks a search result, before the description phase.
struct SelectedEntryBannerView: View {
    let entry: SearchEntry
    var favoritesManager: FavoritesManager

    @Environment(\.theme) private var theme
    @Environment(\.entryFontSizeBoost) private var fontBoost

    var body: some View {
        let isFav = favoritesManager.isFavorite(projectId: entry.projectId, taskId: entry.taskId)

        VStack(spacing: 0) {
            theme.divider.frame(height: 1)

            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.system(size: 18 + fontBoost))

                VStack(alignment: .leading, spacing: 4) {
                    if !entry.customerName.isEmpty {
                        Text(entry.customerName)
                            .font(.system(size: 13 + fontBoost, weight: .medium))
                            .foregroundStyle(theme.textSecondary)
                            .lineLimit(1)
                    }

                    Text(entry.projectName)
                        .font(.system(size: 15 + fontBoost))
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(1)

                    Text(entry.taskName)
                        .font(.system(size: 15 + fontBoost, weight: .semibold))
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)
                }

                Spacer()

                Button {
                    favoritesManager.toggle(entry)
                } label: {
                    Image(systemName: isFav ? "star.fill" : "star")
                        .foregroundStyle(isFav ? Color.yellow : theme.textTertiary)
                        .font(.system(size: 14 + fontBoost))
                }
                .buttonStyle(.plain)
                .help(isFav ? String(localized: "a11y.removeFavorite") : String(localized: "a11y.addFavorite"))
                .accessibilityLabel(isFav ? String(localized: "a11y.removeFavorite") : String(localized: "a11y.addFavorite"))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(theme.surfaceElevated)
        }
    }
}
