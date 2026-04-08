import SwiftUI

/// Settings window content with Account, How to Use, General, Projects, and Debug tabs.
struct SettingsView: View {
    @Bindable var settings: SettingsStore
    var appState: AppState?
    var onShortcutChanged: ((UInt32, UInt32) -> Void)?

    var body: some View {
        TabView {
            AccountSettingsTab(settings: settings, appState: appState)
                .tabItem { Label(String(localized: "settings.account"), systemImage: "person.circle") }
            HowToUseSettingsTab(settings: settings, onShortcutChanged: onShortcutChanged)
                .tabItem { Label(String(localized: "settings.howToUse"), systemImage: "keyboard") }
            GeneralSettingsTab(settings: settings, appState: appState)
                .tabItem { Label(String(localized: "settings.general"), systemImage: "gear") }
            FavoritesSettingsTab(settings: settings, favoritesManager: appState?.favoritesManager)
                .tabItem { Label(String(localized: "settings.favorites"), systemImage: "star") }
            NotificationsSettingsTab(settings: settings)
                .tabItem { Label(String(localized: "settings.notifications"), systemImage: "bell") }
            ProjectsSettingsTab(
                projects: appState?.catalog.projects ?? [],
                isLoading: appState?.catalog.isLoading ?? false,
                onRefresh: { await appState?.fetchProjects() }
            )
                .tabItem { Label(String(localized: "settings.projects"), systemImage: "list.bullet") }
            DebugSettingsTab(settings: settings)
                .tabItem { Label(String(localized: "settings.debug"), systemImage: "ladybug") }
            AboutSettingsTab()
                .tabItem { Label(String(localized: "settings.about"), systemImage: "info.circle") }
        }
        .frame(width: 780, height: 580)
        .padding()
    }
}
