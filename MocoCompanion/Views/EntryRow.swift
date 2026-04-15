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
                    .foregroundStyle(isSelected ? theme.selectedTextSecondary : isHovered ? theme.textSecondary : theme.textTertiary)
                    .frame(width: 28, alignment: .center)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(isSelected ? theme.selectedSurface : theme.surface)
                    )
            }

            // Status dot
            if isRunning {
                Circle()
                    .fill(isSelected ? theme.selectedTextPrimary : .green)
                    .frame(width: 7, height: 7)
                    .shadow(color: (isSelected ? Color.clear : .green).opacity(0.4), radius: 3)
            } else if isPaused {
                Circle()
                    .fill(isSelected ? theme.selectedTextPrimary : .orange)
                    .frame(width: 7, height: 7)
            }

            // Content
            VStack(alignment: .leading, spacing: 4) {
                // Line 1: Customer › Project + star
                HStack(spacing: 0) {
                    if let customerName, !customerName.isEmpty {
                        Text(customerName)
                            .foregroundStyle(isSelected ? theme.selectedTextPrimary : theme.textPrimary)
                        Text(" › ")
                            .foregroundStyle(isSelected ? theme.selectedTextTertiary : theme.textTertiary)
                    }
                    Text(projectName)
                        .foregroundStyle(isSelected ? theme.selectedTextPrimary : theme.textPrimary)

                    if let isFavorite, let onToggleFavorite {
                        Button {
                            onToggleFavorite()
                        } label: {
                            Image(systemName: isFavorite ? "star.fill" : "star")
                                .foregroundStyle(isFavorite ? Color.yellow : (isHighlighted ? theme.selectedTextTertiary : theme.textTertiary.opacity(0.4)))
                                .font(.system(size: captionSize))
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, 4)
                        .help(isFavorite ? String(localized: "a11y.removeFavorite") : String(localized: "a11y.addFavorite"))
                    }
                }
                .font(.system(size: bodySize))
                .lineLimit(1)

                // Line 2: Task + budget badge + description
                HStack(spacing: 6) {
                    Text(taskName)
                        .font(.system(size: bodySize))
                        .fontWeight(.semibold)
                        .foregroundStyle(isSelected ? theme.selectedTextPrimary : theme.textPrimary)

                    if let badgeColor = budgetBadge.color {
                        Circle()
                            .fill(badgeColor)
                            .frame(width: 7, height: 7)
                            .help(budgetBadge.tooltip)
                    }

                    if let desc = description, !desc.isEmpty {
                        Text("· \(desc)")
                            .font(.system(size: bodySize))
                            .foregroundStyle(isSelected ? theme.selectedTextTertiary : theme.textTertiary)
                    }
                }
                .lineLimit(1)

                // Line 3: Hints (shown when selected or hovered).
                // Always reserve space to prevent layout oscillation —
                // hover toggling the hints would change row height,
                // which can push the cursor out, triggering an infinite
                // hover/unhover loop that hangs the main thread.
                if !hints.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(hints, id: \.self) { hint in
                            Text(hint)
                                .font(.system(size: captionSize, weight: .medium))
                        }
                    }
                    .foregroundStyle(isSelected ? theme.selectedTextTertiary : theme.textTertiary)
                    .padding(.top, 2)
                    .opacity(isSelected || isHovered ? 1 : 0)
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
        .accessibilityLabel(accessibilityDescription)
    }

    /// Rich VoiceOver label: includes project/task, timer state, and description.
    private var accessibilityDescription: String {
        var parts: [String] = []
        if let customerName, !customerName.isEmpty {
            parts.append(customerName)
        }
        parts.append(projectName)
        parts.append(taskName)
        if isRunning {
            parts.append(String(localized: "a11y.timerRunning"))
        } else if isPaused {
            parts.append(String(localized: "a11y.timerPaused"))
        }
        if let desc = description, !desc.isEmpty {
            parts.append(desc)
        }
        return parts.joined(separator: ", ")
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
        case .projectWarning: return String(localized: "budget.projectWarning.tooltip")
        case .projectCritical: return String(localized: "budget.projectCritical.tooltip")
        case .taskCritical: return String(localized: "budget.taskCritical.tooltip")
        }
    }
}
