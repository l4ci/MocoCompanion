import SwiftUI

/// A compact undo toast shown at the bottom of the panel after deleting an entry.
/// Auto-dismisses after the 5-second grace period. Tap "Undo" to restore.
struct UndoToastView: View {
    let projectName: String
    var onUndo: () -> Void

    @Environment(\.theme) private var theme
    @Environment(\.entryFontSizeBoost) private var fontBoost
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var appeared = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "trash")
                .font(.system(size: 12 + fontBoost))
                .foregroundStyle(.red.opacity(0.8))

            Text(String(localized: "undo.deleted \(projectName)"))
                .font(.system(size: 13 + fontBoost))
                .foregroundStyle(theme.textSecondary)
                .lineLimit(1)

            Spacer()

            Button {
                onUndo()
            } label: {
                Text(String(localized: "undo.action"))
                    .font(.system(size: 13 + fontBoost, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "a11y.undoDelete"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(theme.surface)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 8)
        .onAppear {
            animateAccessibly(reduceMotion, .easeOut(duration: 0.2)) {
                appeared = true
            }
        }
    }
}
