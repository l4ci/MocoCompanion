import SwiftUI

/// Compact offline indicator shown at the top of the panel when network is unavailable.
struct OfflineBannerView: View {
    var queuedCount: Int = 0

    @Environment(\.theme) private var theme
    @Environment(\.entryFontSizeBoost) private var fontBoost

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "icloud.slash")
                .font(.system(size: 13 + fontBoost, weight: .medium))
                .foregroundStyle(.orange)

            Text(queuedCount > 0
                 ? String(localized: "offline.withQueue \(queuedCount)")
                 : String(localized: "offline.banner"))
                .font(.system(size: 12 + fontBoost))
                .foregroundStyle(theme.textSecondary)

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Color.orange.opacity(0.08))
    }
}
