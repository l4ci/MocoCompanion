import SwiftUI

/// About tab in settings — app icon, version, author, license, and repository link.
struct AboutSettingsTab: View {
    @Environment(\.theme) private var theme

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // App icon
            Image("AppIconImage")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)

            Spacer().frame(height: 16)

            // App name
            Text("MocoCompanion")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(theme.textPrimary)

            // Version
            Text("Version \(appVersion)")
                .font(.system(size: 13))
                .foregroundStyle(theme.textSecondary)
                .padding(.top, 2)

            Spacer().frame(height: 24)

            // Info rows
            VStack(spacing: 12) {
                infoRow(
                    label: String(localized: "about.author"),
                    value: "Volker Otto"
                )

                infoRow(
                    label: String(localized: "about.license"),
                    value: "MIT License"
                )
            }
            .frame(maxWidth: 300)

            Spacer().frame(height: 20)

            // Repository link
            if let repoURL = URL(string: "https://github.com/l4ci/MocoCompanion") {
                Link(destination: repoURL) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left.forwardslash.chevron.right")
                            .font(.system(size: 12))
                        Text(String(localized: "about.repository"))
                            .font(.system(size: 13, weight: .medium))
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            }

            Spacer().frame(height: 16)

            // Disclaimer
            Text(String(localized: "about.disclaimer"))
                .font(.system(size: 11))
                .foregroundStyle(theme.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(theme.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.textPrimary)
        }
    }
}
