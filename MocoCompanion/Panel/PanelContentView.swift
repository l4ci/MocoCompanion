import SwiftUI

/// Top-level panel content with TRACK and LOG tabs.
/// Tab switches views when the search field is empty; otherwise Tab does autocomplete/submit.
struct PanelContentView: View {
    @Bindable var appState: AppState
    var favoritesManager: FavoritesManager

    @State var activeTab: PanelTab
    @State private var initialSearchText: String = ""
    /// Pre-selected entry from Today view's planned task — triggers description phase in Track tab.
    @State private var preSelectedEntry: SearchEntry? = nil
    @Environment(\.colorScheme) private var colorScheme

    init(appState: AppState, favoritesManager: FavoritesManager) {
        self.appState = appState
        self.favoritesManager = favoritesManager
        self._activeTab = State(initialValue: appState.settings.defaultTab == "today" ? .today : .search)
    }

    enum PanelTab: CaseIterable {
        case search
        case today

        var label: String {
            switch self {
            case .search: String(localized: "tab.search")
            case .today: String(localized: "tab.today")
            }
        }
    }

    @Environment(\.theme) private var theme

    private var fontBoost: CGFloat { CGFloat(appState.settings.entryFontSizeBoost) }
    private var avatarSize: CGFloat { 38 + fontBoost }

    /// Effective color scheme — respects the user's appearance setting, falling back to system.
    private var effectiveColorScheme: ColorScheme {
        Theme.colorScheme(from: appState.settings.appearance) ?? colorScheme
    }

    var body: some View {
        VStack(spacing: 0) {
            switch activeTab {
            case .search:
                QuickEntryView(
                    appState: appState,
                    favoritesManager: favoritesManager,
                    activeTab: $activeTab,
                    initialSearchText: $initialSearchText,
                    preSelectedEntry: $preSelectedEntry
                )
            case .today:
                todayHeader

                theme.divider.frame(height: 1)

                TodayView(
                    appState: appState,
                    onTabSwitch: { activeTab = .search },
                    onTypeToSearch: { chars in
                        initialSearchText = chars
                        activeTab = .search
                    },
                    onStartEntry: { entry in
                        preSelectedEntry = entry
                        activeTab = .search
                    }
                )
            }
        }
        .frame(width: appState.settings.panelWidth)
        .frame(minHeight: 56)
        .background(theme.panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(theme.divider, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.15), radius: 40, y: 12)
        .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
        .onKeyPress(phases: .down) { _ in
            NSCursor.setHiddenUntilMouseMoves(true)
            return .ignored
        }
        .preferredColorScheme(Theme.colorScheme(from: appState.settings.appearance))
        .withTheme(colorScheme: effectiveColorScheme)
        .environment(\.entryFontSizeBoost, CGFloat(appState.settings.entryFontSizeBoost))
    }

    // MARK: - Today Header (replaces search bar)

    private var todayHeader: some View {
        HStack(spacing: 12) {
            // User avatar or fallback initials
            if let profile = appState.currentUserProfile, let urlStr = profile.avatarUrl, let url = URL(string: urlStr) {
                AsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    userInitials
                }
                .frame(width: avatarSize, height: avatarSize)
                .clipShape(Circle())
            } else {
                userInitials
            }

            VStack(alignment: .leading, spacing: 2) {
                // Greeting
                Text(greetingText)
                    .font(.system(size: 20 + fontBoost, weight: .medium))
                    .foregroundStyle(theme.textPrimary)

                // Date
                Text(todayDateString)
                    .font(.system(size: 14 + fontBoost))
                    .foregroundStyle(theme.textSecondary)
            }

            Spacer()

            PanelTabSwitcher(activeTab: $activeTab)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
    }

    private var userInitials: some View {
        Image("AppIconImage")
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: avatarSize, height: avatarSize)
            .clipShape(Circle())
    }

    private var greetingText: String {
        GreetingHelper.currentGreeting(name: appState.currentUserProfile?.firstname)
    }

    private static let todayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "EEEE, d. MMMM"
        return f
    }()

    private var todayDateString: String {
        Self.todayFormatter.string(from: Date())
    }
}
