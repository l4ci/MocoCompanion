import SwiftUI

/// A compact first-use hint shown once at the top of the panel on first open.
/// Teaches the core keyboard shortcuts in a single dismissable row.
/// Dismissed on any keypress, click, or explicit close — never shown again.
struct FirstUseHintView: View {
    @Binding var isVisible: Bool

    @Environment(\.theme) private var theme
    @Environment(\.entryFontSizeBoost) private var fontBoost
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var captionSize: CGFloat { 12 + fontBoost }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "keyboard")
                .font(.system(size: 14 + fontBoost, weight: .light))
                .foregroundStyle(theme.plannedIndicator)

            Text(String(localized: "onboard.keyboardHint"))
                .font(.system(size: captionSize))
                .foregroundStyle(theme.textSecondary)

            Spacer(minLength: 4)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10 + fontBoost, weight: .medium))
                    .foregroundStyle(theme.textTertiary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "a11y.dismissWarning"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(theme.surface)
    }

    private func dismiss() {
        animateAccessibly(reduceMotion, .easeOut(duration: Theme.Motion.fast)) {
            isVisible = false
        }
    }
}
