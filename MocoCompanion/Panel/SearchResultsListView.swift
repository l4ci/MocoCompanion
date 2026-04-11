import SwiftUI

/// Scrollable list of search results, favorites, and recents.
struct SearchResultsListView: View {
    let items: [(entry: SearchEntry, section: QuickEntryStateMachine.ResultSection, description: String?)]
    @Binding var selectedIndex: Int
    @Binding var hoveredIndex: Int?

    var favoritesManager: FavoritesManager
    var budgetService: BudgetService?
    var onSelectCurrent: () -> Void
    let showingShortcuts: Bool

    @Environment(\.theme) private var theme
    @Environment(\.entryFontSizeBoost) private var fontBoost
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Row wrapper with a stable identity. Identity is derived from the
    /// (section, projectId, taskId) triple so favoriting or reordering
    /// rows doesn't force SwiftUI to rebuild every row below the change.
    private struct Row: Identifiable, Hashable {
        let id: String
        let index: Int
        let entry: SearchEntry
        let section: QuickEntryStateMachine.ResultSection
        let description: String?
        let isFirstInSection: Bool

        static func == (lhs: Row, rhs: Row) -> Bool { lhs.id == rhs.id }
        func hash(into hasher: inout Hasher) { hasher.combine(id) }
    }

    private var rows: [Row] {
        items.enumerated().map { (idx, item) in
            let prevSection = idx == 0 ? nil : items[idx - 1].section
            return Row(
                id: "\(item.section)-\(item.entry.projectId)-\(item.entry.taskId)",
                index: idx,
                entry: item.entry,
                section: item.section,
                description: item.description,
                isFirstInSection: prevSection != item.section
            )
        }
    }

    var body: some View {
        let maxResultsHeight: CGFloat = 365
        let rows = self.rows

        VStack(spacing: 0) {
            theme.divider.frame(height: 1)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(rows) { row in
                            if row.isFirstInSection {
                                sectionHeader(for: row.section)
                            }
                            resultRow(entry: row.entry, index: row.index, section: row.section, recentDescription: row.description)
                                .id(row.id)
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                }
                .frame(maxHeight: maxResultsHeight)
                .onChange(of: selectedIndex) { _, newIndex in
                    guard newIndex >= 0, newIndex < rows.count else { return }
                    let targetId = rows[newIndex].id
                    animateAccessibly(reduceMotion, .easeOut(duration: Theme.Motion.fast)) {
                        proxy.scrollTo(targetId, anchor: .center)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func sectionHeader(for section: QuickEntryStateMachine.ResultSection) -> some View {
        let title: String? = switch section {
        case .favorite: String(localized: "search.favorites")
        case .recent: String(localized: "search.recents")
        case .suggestion, .search: nil
        }
        if let title {
            HStack {
                Text(title)
                    .font(.system(size: 12 + fontBoost, weight: .semibold))
                    .foregroundStyle(theme.textTertiary)
                    .textCase(.uppercase)
                    .tracking(0.3)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 2)
        }
    }

    private func resultRow(entry: SearchEntry, index: Int, section: QuickEntryStateMachine.ResultSection, recentDescription: String?) -> some View {
        let isSelected = index == selectedIndex
        let isHovered = hoveredIndex == index
        let isFav = favoritesManager.isFavorite(projectId: entry.projectId, taskId: entry.taskId)
        let badge = budgetService?.status(projectId: entry.projectId, taskId: entry.taskId).effectiveBadge ?? .none

        return EntryRow(
            projectName: entry.projectName,
            customerName: entry.customerName,
            taskName: entry.taskName,
            description: recentDescription,
            isSelected: isSelected,
            isHovered: isHovered,
            shortcutIndex: index,
            isFavorite: isFav,
            onToggleFavorite: { favoritesManager.toggle(entry) },
            budgetBadge: badge
        )
        .onHover { hover in
            if hover {
                hoveredIndex = index
            } else {
                hoveredIndex = nil
            }
        }
        .onTapGesture {
            selectedIndex = index
            onSelectCurrent()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.customerName), \(entry.projectName), \(entry.taskName)")
        .accessibilityHint(index < 5 ? String(localized: "a11y.shortcutSelect \(index + 1)") : String(localized: "a11y.tapToSelect"))
    }
}
