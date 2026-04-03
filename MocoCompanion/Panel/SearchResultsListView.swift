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

    var body: some View {
        let maxResultsHeight: CGFloat = 365

        VStack(spacing: 0) {
            theme.divider.frame(height: 1)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                            if index == 0 || items[index].section != items[index - 1].section {
                                sectionHeader(for: item.section)
                            }
                            resultRow(entry: item.entry, index: index, section: item.section, recentDescription: item.description)
                                .id(index)
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                }
                .frame(maxHeight: maxResultsHeight)
                .onChange(of: selectedIndex) { _, newIndex in
                    guard newIndex >= 0 else { return }
                    animateAccessibly(reduceMotion, .easeOut(duration: Theme.Motion.fast)) {
                        proxy.scrollTo(newIndex, anchor: .center)
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
        .accessibilityHint("Command \(index + 1) to select")
    }
}
