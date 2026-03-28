import SwiftUI

/// Account settings tab: subdomain, API key, and connection status.
struct AccountSettingsTab: View {
    @Bindable var settings: SettingsStore
    var appState: AppState?

    var body: some View {
        Form {
            Section {
                TextField(String(localized: "settings.subdomain"), text: $settings.subdomain)
                    .textFieldStyle(.roundedBorder)
                    .help("Your Moco subdomain, e.g. 'mycompany' for mycompany.mocoapp.com")

                SecureField(String(localized: "settings.apiKey"), text: $settings.apiKey)
                    .textFieldStyle(.roundedBorder)
                    .help("Your personal Moco API key from Profile → Integrations")
            } header: {
                Text(String(localized: "settings.mocoAccount"))
            } footer: {
                Text(String(localized: "settings.credentialsNote"))
            }

            Section {
                HStack(spacing: 6) {
                    Image(systemName: settings.isConfigured ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(settings.isConfigured ? .green : .red)
                    Text(settings.isConfigured ? String(localized: "settings.connected") : String(localized: "settings.notConfigured"))
                        .foregroundStyle(settings.isConfigured ? .primary : .secondary)

                    Spacer()

                    if settings.isConfigured, let appState {
                        Button(String(localized: "settings.refreshProjects")) {
                            Task { await appState.fetchProjects() }
                        }
                        .controlSize(.small)
                    }
                }
            } header: {
                Text(String(localized: "settings.status"))
            }
        }
        .formStyle(.grouped)
    }
}
