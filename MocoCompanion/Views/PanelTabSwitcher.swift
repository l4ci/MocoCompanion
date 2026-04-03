import SwiftUI

/// Shared inline tab switcher: pill-segmented [TRACK | LOG]
/// Used in both QuickEntryView and PanelContentView.
struct PanelTabSwitcher: View {
    @Binding var activeTab: PanelContentView.PanelTab
    @Environment(\.theme) private var theme
    @Environment(\.entryFontSizeBoost) private var fontBoost
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 2) {
            ForEach(PanelContentView.PanelTab.allCases, id: \.self) { tab in
                Button {
                    animateAccessibly(reduceMotion) {
                        activeTab = tab
                    }
                } label: {
                    Text(tab.label)
                        .font(.system(size: 12 + fontBoost, weight: activeTab == tab ? .semibold : .medium))
                        .foregroundStyle(activeTab == tab ? theme.textPrimary : theme.textTertiary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(activeTab == tab ? theme.tabPillActive : .clear)
                                .shadow(color: activeTab == tab ? .black.opacity(0.06) : .clear, radius: 1, y: 0.5)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(tab.label) tab")
                .accessibilityAddTraits(activeTab == tab ? .isSelected : [])
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(theme.tabPillBackground)
        )
    }
}
