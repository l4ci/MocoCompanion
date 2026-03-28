import SwiftUI

/// Shared row component used in both Search and Today views.
/// Provides consistent layout, selection styling, and keyboard shortcut badges.
struct EntryRow<Duration: View>: View {
    let projectName: String
    let customerName: String?
    let taskName: String
    let description: String?
    let isSelected: Bool
    let isHovered: Bool

    // Optional features
    var isRunning = false
    var isPaused = false
    var shortcutIndex: Int = -1  // -1 = no badge, 0+ = ⌘(n+1)
    var isFavorite: Bool? = nil
    var onToggleFavorite: (() -> Void)? = nil
    var hints: [String] = []
    var budgetBadge: BudgetBadge = .none

    @ViewBuilder var duration: Duration

    @Environment(\.theme) private var theme
    @Environment(\.entryFontSizeBoost) private var fontBoost

    /// Base font size for entry content (2pt larger than original + user boost).
    private var bodySize: CGFloat { 15 + fontBoost }
    /// Font size for shortcut badges and hints (scales proportionally).
    private var captionSize: CGFloat { 12 + fontBoost }

    /// Whether the row is visually highlighted (selected or hovered).
    private var isHighlighted: Bool { isSelected || isHovered }

    private var rowBackground: Color {
        if isSelected { return theme.selection }
        if isRunning && !isSelected {
            return isHovered ? theme.runningHover : theme.runningTint
        }
        if isPaused && !isSelected {
            return isHovered ? theme.pausedHover : theme.pausedTint
        }
        if isHovered { return theme.hover }
        return .clear
    }

    var body: some View {
        HStack(spacing: 10) {
            // Shortcut badge ⌘1–⌘9 (only when shortcutIndex >= 0)
            if shortcutIndex >= 0 && shortcutIndex < 6 {
                Text("⌘\(shortcutIndex + 1)")
                    .font(.system(size: captionSize, weight: .medium, design: .rounded))
                    .foregroundStyle(isSelected ? .white.opacity(0.65) : isHovered ? theme.textSecondary : theme.textTertiary)
                    .frame(width: 28, alignment: .center)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(isSelected ? Color.white.opacity(0.12) : theme.surface)
                    )
            }

            // Status dot
            if isRunning {
                Circle()
                    .fill(isSelected ? .white : .green)
                    .frame(width: 7, height: 7)
                    .shadow(color: (isSelected ? Color.clear : .green).opacity(0.4), radius: 3)
            } else if isPaused {
                Circle()
                    .fill(isSelected ? .white : .orange)
                    .frame(width: 7, height: 7)
            }

            // Content
            VStack(alignment: .leading, spacing: 4) {
                // Line 1: Customer › Project + star
                HStack(spacing: 0) {
                    if let customerName, !customerName.isEmpty {
                        Text(customerName)
                            .foregroundStyle(isSelected ? .white : theme.textPrimary)
                        Text(" › ")
                            .foregroundStyle(isSelected ? .white.opacity(0.5) : theme.textTertiary)
                    }
                    Text(projectName)
                        .foregroundStyle(isSelected ? .white : theme.textPrimary)

                    if let isFavorite, let onToggleFavorite {
                        Button {
                            onToggleFavorite()
                        } label: {
                            Image(systemName: isFavorite ? "star.fill" : "star")
                                .foregroundStyle(isFavorite ? Color.yellow : (isHighlighted ? Color.white.opacity(0.35) : theme.textTertiary.opacity(0.4)))
                                .font(.system(size: captionSize))
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, 4)
                        .help(isFavorite ? "Remove from favorites" : "Add to favorites")
                    }
                }
                .font(.system(size: bodySize))
                .lineLimit(1)

                // Line 2: Task + budget badge + description
                HStack(spacing: 6) {
                    Text(taskName)
                        .font(.system(size: bodySize))
                        .fontWeight(.semibold)
                        .foregroundStyle(isSelected ? .white : theme.textPrimary)

                    if let badgeColor = budgetBadge.color {
                        Circle()
                            .fill(badgeColor)
                            .frame(width: 7, height: 7)
                            .help(budgetBadge.tooltip)
                    }

                    if let desc = description, !desc.isEmpty {
                        Text("· \(desc)")
                            .font(.system(size: bodySize))
                            .foregroundStyle(isSelected ? .white.opacity(0.55) : theme.textTertiary)
                    }
                }
                .lineLimit(1)

                // Line 3: Hints (shown when selected or hovered)
                if !hints.isEmpty && (isSelected || isHovered) {
                    HStack(spacing: 8) {
                        ForEach(hints, id: \.self) { hint in
                            Text(hint)
                                .font(.system(size: captionSize, weight: .medium))
                        }
                    }
                    .foregroundStyle(isSelected ? .white.opacity(0.4) : theme.textTertiary)
                    .padding(.top, 2)
                }
            }

            Spacer(minLength: 4)

            // Right side: duration
            duration
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(rowBackground)
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(customerName ?? "") \(projectName), \(taskName)")
    }
}

// MARK: - Convenience (no duration)

extension EntryRow where Duration == EmptyView {
    init(
        projectName: String,
        customerName: String?,
        taskName: String,
        description: String?,
        isSelected: Bool,
        isHovered: Bool,
        isRunning: Bool = false,
        isPaused: Bool = false,
        shortcutIndex: Int = -1,
        isFavorite: Bool? = nil,
        onToggleFavorite: (() -> Void)? = nil,
        hints: [String] = [],
        budgetBadge: BudgetBadge = .none
    ) {
        self.projectName = projectName
        self.customerName = customerName
        self.taskName = taskName
        self.description = description
        self.isSelected = isSelected
        self.isHovered = isHovered
        self.isRunning = isRunning
        self.isPaused = isPaused
        self.shortcutIndex = shortcutIndex
        self.isFavorite = isFavorite
        self.onToggleFavorite = onToggleFavorite
        self.hints = hints
        self.budgetBadge = budgetBadge
        self.duration = EmptyView()
    }
}

// MARK: - BudgetBadge UI

extension BudgetBadge {
    /// The color for the badge indicator, or nil when no badge should be shown.
    var color: Color? {
        switch self {
        case .none: return nil
        case .projectWarning: return .yellow
        case .projectCritical: return .orange
        case .taskCritical: return .red
        }
    }

    /// Tooltip describing the budget condition.
    var tooltip: String {
        switch self {
        case .none: return ""
        case .projectWarning: return "Project budget over 50% consumed"
        case .projectCritical: return "Project budget over 90% consumed"
        case .taskCritical: return "Task has less than 1 hour remaining"
        }
    }
}
