import SwiftUI

/// Settings window content with Account, How to Use, General, Projects, and Debug tabs.
struct SettingsView: View {
    @Bindable var settings: SettingsStore
    var appState: AppState?
    var onShortcutChanged: ((UInt32, UInt32) -> Void)?

    var body: some View {
        TabView {
            Tab(String(localized: "settings.account"), systemImage: "person.circle") {
                AccountSettingsTab(settings: settings, appState: appState)
            }
            Tab(String(localized: "settings.howToUse"), systemImage: "keyboard") {
                HowToUseSettingsTab(settings: settings, onShortcutChanged: onShortcutChanged)
            }
            Tab(String(localized: "settings.general"), systemImage: "gear") {
                GeneralSettingsTab(settings: settings, appState: appState)
            }
            Tab(String(localized: "settings.favorites"), systemImage: "star") {
                FavoritesSettingsTab(settings: settings, favoritesManager: appState?.favoritesManager)
            }
            Tab(String(localized: "settings.notifications"), systemImage: "bell") {
                NotificationsSettingsTab(settings: settings)
            }
            Tab(String(localized: "settings.projects"), systemImage: "list.bullet") {
                ProjectsSettingsTab(
                    projects: appState?.catalog.projects ?? [],
                    isLoading: appState?.catalog.isLoading ?? false,
                    onRefresh: { await appState?.fetchProjects() }
                )
            }
            Tab(String(localized: "timeline.tab"), systemImage: "clock") {
                AutotrackerSettingsTab(
                    settings: settings,
                    autotracker: appState?.autotracker,
                    projectCatalog: appState?.catalog,
                    appState: appState
                )
            }
            Tab(String(localized: "settings.debug"), systemImage: "ladybug") {
                DebugSettingsTab(settings: settings)
            }
            Tab(String(localized: "settings.about"), systemImage: "info.circle") {
                AboutSettingsTab()
            }
        }
        .frame(width: 780, height: 580)
        .padding()
    }
}
