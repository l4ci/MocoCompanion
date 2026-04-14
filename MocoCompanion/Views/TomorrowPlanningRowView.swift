import SwiftUI

// MARK: - Tomorrow Planning Row

/// A single planning entry row for the tomorrow tab.
/// Extracted to a struct so it can track its own hover state.
struct TomorrowPlanningRowView: View {
    let entry: MocoPlanningEntry
    var isSelected: Bool = false
    var onStartEntry: ((SearchEntry) -> Void)? = nil
    var onHover: ((_ hovering: Bool) -> Void)? = nil

    @State private var isHovered = false

    @Environment(\.theme) private var theme
    @Environment(\.entryFontSizeBoost) private var fontBoost

    private var bodySize: CGFloat { 14 + fontBoost }
    private var captionSize: CGFloat { 12 + fontBoost }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: captionSize))
                .foregroundStyle(isSelected ? theme.selectedTextTertiary : theme.plannedIndicator)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 0) {
                    if let customer = entry.project?.customerName, !customer.isEmpty {
                        Text(customer)
                            .foregroundStyle(isSelected ? theme.selectedTextSecondary : theme.textSecondary)
                        Text(" › ")
                            .foregroundStyle(isSelected ? theme.selectedTextTertiary : theme.textTertiary)
                    }
                    Text(entry.project?.name ?? "—")
                        .foregroundStyle(isSelected ? theme.selectedTextPrimary : theme.textPrimary)
                }
                .font(.system(size: bodySize))
                .lineLimit(1)

                Text(entry.task?.name ?? "—")
                    .font(.system(size: bodySize))
                    .fontWeight(.semibold)
                    .foregroundStyle(isSelected ? theme.selectedTextSecondary : theme.textSecondary)
                    .lineLimit(1)

                if isHovered {
                    HStack(spacing: 8) {
                        Text(String(localized: "hint.enterStart"))
                            .font(.system(size: captionSize, weight: .medium))
                    }
                    .foregroundStyle(theme.textTertiary)
                    .padding(.top, 2)
                }
            }

            Spacer()

            Text("\(entry.hoursPerDay.formatted(.number.precision(.fractionLength(0))))h")
                .font(.system(size: captionSize, weight: .medium, design: .monospaced))
                .foregroundStyle(isSelected ? theme.selectedTextTertiary : theme.plannedIndicatorSubtle)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.accentColor : isHovered ? theme.hover : theme.surface)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
            onHover?(hovering)
        }
        .onTapGesture {
            guard let project = entry.project, let task = entry.task else { return }
            let searchEntry = SearchEntry(
                projectId: project.id,
                taskId: task.id,
                customerName: project.customerName ?? "",
                projectName: project.name,
                taskName: task.name
            )
            onStartEntry?(searchEntry)
        }
    }
}
