import SwiftUI

/// Renders a suggestion block in the timeline with dashed outline and hover approve/decline buttons.
struct SuggestionBlockView: View {
    let suggestion: Suggestion
    let viewModel: TimelineViewModel
    @Environment(\.theme) private var theme
    @Environment(\.entryFontSizeBoost) private var fontBoost
    @State private var isHovered = false

    private var height: CGFloat {
        max(CGFloat(suggestion.durationSeconds) / 60.0 * TimelineLayout.pixelsPerMinute, 20)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Content
            VStack(alignment: .leading, spacing: 1) {
                Text(suggestion.projectName)
                    .font(.system(size: Theme.FontSize.caption + fontBoost, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)

                Text(suggestion.taskName)
                    .font(.system(size: Theme.FontSize.caption + fontBoost))
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(1)

                Text(suggestion.appName)
                    .font(.system(size: Theme.FontSize.caption + fontBoost))
                    .foregroundStyle(theme.textTertiary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: height)
            .background(
                Color.accentColor.opacity(0.08),
                in: RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                    .strokeBorder(
                        Color.accentColor.opacity(0.4),
                        style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                    )
            }

            // Hover action buttons
            HStack(spacing: 4) {
                Button("Approve", systemImage: "checkmark.circle.fill") {
                    Task { await viewModel.approveSuggestion(suggestion) }
                }
                .labelStyle(.iconOnly)
                .font(.system(size: Theme.FontSize.callout + fontBoost))
                .foregroundStyle(.green)
                .buttonStyle(.plain)

                Button("Decline", systemImage: "xmark.circle.fill") {
                    viewModel.declineSuggestion(suggestion)
                }
                .labelStyle(.iconOnly)
                .font(.system(size: Theme.FontSize.callout + fontBoost))
                .foregroundStyle(.red)
                .buttonStyle(.plain)
            }
            .padding(4)
            .opacity(isHovered ? 1 : 0)
            .animation(.easeInOut(duration: Theme.Motion.fast), value: isHovered)
        }
        .onHover { isHovered = $0 }
        .allowsHitTesting(true)
    }
}
