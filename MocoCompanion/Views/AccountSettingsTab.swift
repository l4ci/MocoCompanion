import SwiftUI

/// Account settings tab: subdomain, API key, connection status, and data reset.
struct AccountSettingsTab: View {
    @Bindable var settings: SettingsStore
    var appState: AppState?
    @State private var showingResetConfirmation = false

    var body: some View {
        Form {
            Section {
                TextField(String(localized: "settings.subdomain"), text: $settings.subdomain)
                    .textFieldStyle(.roundedBorder)
                    .help("Your Moco subdomain, e.g. 'mycompany' for mycompany.mocoapp.com")

                if !settings.subdomain.isEmpty && !MocoClient.isValidSubdomain(settings.subdomain) {
                    Text(String(localized: "setup.invalidSubdomain"))
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                SecureField(String(localized: "settings.apiKey"), text: $settings.apiKey)
                    .textFieldStyle(.roundedBorder)
                    .help("Your personal Moco API key from Profile → Integrations")
            } header: {
                Text(String(localized: "settings.mocoAccount"))
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "settings.credentialsNote"))
                    Text(String(localized: "settings.apiKeyHint"))
                        .foregroundStyle(.secondary)
                }
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

            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "settings.resetTitle"))
                            .font(.body)
                        Text(String(localized: "settings.resetDescription"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button(role: .destructive) {
                        showingResetConfirmation = true
                    } label: {
                        Text(String(localized: "settings.resetButton"))
                    }
                    .controlSize(.small)
                }
            } header: {
                Text(String(localized: "settings.dangerZone"))
            }
        }
        .formStyle(.grouped)
        .alert(String(localized: "settings.resetConfirmTitle"), isPresented: $showingResetConfirmation) {
            Button(String(localized: "settings.resetConfirmButton"), role: .destructive) {
                settings.resetAllData()
            }
            Button(String(localized: "settings.resetCancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "settings.resetConfirmMessage"))
        }
    }
}
