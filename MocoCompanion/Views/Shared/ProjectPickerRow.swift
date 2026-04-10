import SwiftUI

/// Reusable row for the project/task picker used across creation, edit, and rule sheets.
struct ProjectPickerRow: View {
    let entry: SearchEntry
    let isSelected: Bool
    let onTap: () -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.customerName)
                    .font(.system(size: Theme.FontSize.caption))
                    .foregroundStyle(theme.textTertiary)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(entry.projectName)
                        .font(.system(size: Theme.FontSize.callout, weight: .medium))
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(1)
                    Text("\u{203A}")
                        .foregroundStyle(theme.textTertiary)
                    Text(entry.taskName)
                        .font(.system(size: Theme.FontSize.callout))
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.accentColor)
                    .font(.system(size: Theme.FontSize.callout))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            isSelected ? Color.accentColor.opacity(0.1) : Color.clear,
            in: RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
        )
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }
}
