import AppKit
import SwiftUI

/// The search bar at the top of the quick-entry popup.
/// Contains user avatar, search text field, clear button, and tab switcher.
struct SearchFieldView: View {
    @Binding var searchText: String
    @Binding var selectedIndex: Int
    @Binding var activeTab: PanelContentView.PanelTab

    let isSearchEmpty: Bool
    let hasActiveTimer: Bool
    let hasMinSearchChars: Bool
    let displayItemCount: Int
    var avatarImage: NSImage? = nil
    var userFirstname: String? = nil

    var onSubmit: () -> Void
    var onMoveSelection: (Int) -> Void
    var onSelectByIndex: (Int) -> Void
    var onSelectCurrentResult: () -> Void

    @FocusState.Binding var focusedField: QuickEntryStateMachine.FocusField?
    @Environment(\.theme) private var theme
    @Environment(\.entryFontSizeBoost) private var fontBoost

    private var avatarSize: CGFloat { 38 + fontBoost }

    var body: some View {
        HStack(spacing: 12) {
            // User avatar (cached) or fallback
            if let nsImage = avatarImage {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: avatarSize, height: avatarSize)
                    .clipShape(Circle())
            } else {
                userInitials
            }

            TextField(String(localized: "search.placeholder"), text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 24 + fontBoost, weight: .regular))
                .focused($focusedField, equals: .search)
                .accessibilityLabel(String(localized: "a11y.searchField"))
                .accessibilityHint(String(localized: "a11y.searchHint"))
                .onSubmit { onSubmit() }
                .onChange(of: searchText) {
                    selectedIndex = (isSearchEmpty && hasActiveTimer) ? -1 : 0
                }
                .onKeyPress(.downArrow) {
                    onMoveSelection(1)
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    onMoveSelection(-1)
                    return .handled
                }
                .onKeyPress(.tab) {
                    activeTab = .today
                    return .handled
                }
                .onKeyPress(phases: .down) { press in
                    guard press.modifiers == .command else { return .ignored }
                    switch press.characters {
                    case "1": onSelectByIndex(0); return .handled
                    case "2": onSelectByIndex(1); return .handled
                    case "3": onSelectByIndex(2); return .handled
                    case "4": onSelectByIndex(3); return .handled
                    case "5": onSelectByIndex(4); return .handled
                    default: return .ignored
                    }
                }

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(theme.textTertiary)
                        .font(.system(size: 18 + fontBoost))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "a11y.clearSearch"))
            }

            PanelTabSwitcher(activeTab: $activeTab)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
    }

    private var userInitials: some View {
        Group {
            if let name = userFirstname, !name.isEmpty {
                // Logged in but no avatar — show initials
                let initial = String(name.prefix(1))
                Text(initial)
                    .font(.system(size: 16 + fontBoost, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: avatarSize, height: avatarSize)
                    .background(Circle().fill(Color.accentColor.gradient))
            } else {
                // Not logged in — show app icon
                Image("AppIconImage")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: avatarSize, height: avatarSize)
                    .clipShape(Circle())
            }
        }
    }
}
