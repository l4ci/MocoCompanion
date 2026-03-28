import SwiftUI

/// Shared yesterday warning banner.
/// Compact style used in the quick-entry panel, expanded style in the status popover.
struct YesterdayBannerView: View {
    let warning: YesterdayWarning
    let onDismiss: () -> Void
    var style: Style = .compact

    @Environment(\.entryFontSizeBoost) private var fontBoost

    private var bodySize: CGFloat { 15 + fontBoost }
    private var captionSize: CGFloat { 13 + fontBoost }

    enum Style {
        /// Single-line banner for the quick-entry panel.
        case compact
        /// Two-line banner with rounded background for the popover.
        case expanded
    }

    var body: some View {
        switch style {
        case .compact:
            compactBanner
        case .expanded:
            expandedBanner
        }
    }

    private var compactBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.system(size: bodySize))
            Text(warning.message)
                .font(.system(size: bodySize, weight: .medium))
                .foregroundStyle(.primary)
            Spacer()
            dismissButton
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(warning.message)
    }

    private var expandedBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.system(size: bodySize))

            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "yesterday.hoursIncomplete"))
                    .font(.system(size: bodySize, weight: .medium))
                    .foregroundStyle(.primary)
                Text(warning.message)
                    .font(.system(size: captionSize))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            dismissButton
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.orange.opacity(0.1))
        )
        .padding(.bottom, 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(warning.message)
    }

    private var dismissButton: some View {
        Button {
            onDismiss()
        } label: {
            Image(systemName: "xmark")
                .foregroundStyle(.secondary)
                .font(.system(size: captionSize))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Dismiss yesterday warning")
    }
}
