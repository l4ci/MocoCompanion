import SwiftUI

/// Top-level panel content with TRACK and LOG tabs.
/// Tab switches views when the search field is empty; otherwise Tab does autocomplete/submit.
struct PanelContentView: View {
    @Bindable var appState: AppState
    var favoritesManager: FavoritesManager
    /// Called when the user presses CMD+T inside the panel to open the Autotracker window.
    var onShowAutotracker: (() -> Void)? = nil

    @State var activeTab: PanelTab
    @State private var initialSearchText: String = ""
    /// Pre-selected entry from Today view's planned task — triggers description phase in Track tab.
    @State private var preSelectedEntry: SearchEntry? = nil
    @Environment(\.colorScheme) private var colorScheme

    init(appState: AppState, favoritesManager: FavoritesManager, onShowAutotracker: (() -> Void)? = nil) {
        self.appState = appState
        self.favoritesManager = favoritesManager
        self.onShowAutotracker = onShowAutotracker
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

    /// Effective color scheme — respects the user's appearance setting, falling back to system.
    private var effectiveColorScheme: ColorScheme {
        Theme.colorScheme(from: appState.settings.appearance) ?? colorScheme
    }

    var body: some View {
        PanelContentInner(
            appState: appState,
            favoritesManager: favoritesManager,
            activeTab: $activeTab,
            initialSearchText: $initialSearchText,
            preSelectedEntry: $preSelectedEntry,
            onShowAutotracker: onShowAutotracker
        )
        .frame(width: appState.settings.panelWidth)
        .frame(minHeight: 56)
        .preferredColorScheme(Theme.colorScheme(from: appState.settings.appearance))
        .withTheme(colorScheme: effectiveColorScheme)
        .environment(\.entryFontSizeBoost, CGFloat(appState.settings.entryFontSizeBoost))
    }
}

/// Inner content that reads the theme environment set by PanelContentView.
/// Split out so `.background(theme.panelBackground)` resolves against the correct theme.
private struct PanelContentInner: View {
    @Bindable var appState: AppState
    var favoritesManager: FavoritesManager
    @Binding var activeTab: PanelContentView.PanelTab
    @Binding var initialSearchText: String
    @Binding var preSelectedEntry: SearchEntry?
    var onShowAutotracker: (() -> Void)? = nil

    @Environment(\.theme) private var theme
    @Environment(\.entryFontSizeBoost) private var fontBoost
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// First-use hint visibility — driven by settings, dismissed on interaction.
    @State private var showFirstUseHint: Bool

    private var avatarSize: CGFloat { 38 + fontBoost }

    init(appState: AppState, favoritesManager: FavoritesManager, activeTab: Binding<PanelContentView.PanelTab>, initialSearchText: Binding<String>, preSelectedEntry: Binding<SearchEntry?>, onShowAutotracker: (() -> Void)? = nil) {
        self.appState = appState
        self.favoritesManager = favoritesManager
        self._activeTab = activeTab
        self._initialSearchText = initialSearchText
        self._preSelectedEntry = preSelectedEntry
        self.onShowAutotracker = onShowAutotracker
        self._showFirstUseHint = State(initialValue: !appState.settings.hasSeenFirstUseHint)
    }

    var body: some View {
        VStack(spacing: 0) {
            if !appState.networkMonitor.isOnline {
                OfflineBannerView(queuedCount: appState.entryQueue.count)
            }

            if showFirstUseHint {
                FirstUseHintView(isVisible: $showFirstUseHint)
                theme.divider.frame(height: 1)
            }

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
            dismissFirstUseHint()
            return .ignored
        }
        .background {
            // Hidden CMD+T button — opens Autotracker without closing the panel
            if let onShowAutotracker {
                Button("") { onShowAutotracker() }
                    .keyboardShortcut("t", modifiers: .command)
                    .frame(width: 0, height: 0)
                    .hidden()
            }
        }
    }

    // MARK: - First-Use Hint

    private func dismissFirstUseHint() {
        guard showFirstUseHint else { return }
        animateAccessibly(reduceMotion, .easeOut(duration: Theme.Motion.fast)) {
            showFirstUseHint = false
        }
        appState.settings.hasSeenFirstUseHint = true
    }

    // MARK: - Today Header (replaces search bar)

    private var todayHeader: some View {
        HStack(spacing: 12) {
            // User avatar (cached) or app icon fallback (not logged in)
            userAvatarView

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

    @ViewBuilder
    private var userAvatarView: some View {
        if let nsImage = appState.session.cachedAvatarImage {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: avatarSize, height: avatarSize)
                .clipShape(Circle())
        } else if let profile = appState.session.currentUserProfile {
            // Logged in but no avatar — show initials
            let initial = String(profile.firstname.prefix(1))
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

    private var greetingText: String {
        GreetingHelper.currentGreeting(name: appState.session.currentUserProfile?.firstname, locale: appState.settings.resolvedLocale)
    }

    private var todayDateString: String {
        let f = DateFormatter()
        f.locale = appState.settings.resolvedLocale
        f.dateFormat = "EEEE, d. MMMM"
        return f.string(from: Date())
    }
}
