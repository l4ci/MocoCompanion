import SwiftUI

/// Notifications settings tab: shows all notification types grouped, with toggles for dismissible ones
/// and visible-but-disabled rows for persistent ones.
struct NotificationsSettingsTab: View {
    var settings: SettingsStore

    var body: some View {
        Form {
            ForEach(NotificationCatalog.SettingsGroup.allCases, id: \.self) { group in
                Section {
                    ForEach(group.types) { type in
                        notificationRow(type)
                    }
                } header: {
                    Text(group.label)
                } footer: {
                    if group == .alerts {
                        Text(String(localized: "notifications.alertsAlwaysOn"))
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func notificationRow(_ type: NotificationCatalog.NotificationType) -> some View {
        HStack(spacing: 10) {
            Image(systemName: type.iconName)
                .font(.system(size: 14))
                .foregroundStyle(iconColor(for: type))
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(type.label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(type.isDismissible ? .primary : .secondary)

                Text(type.settingsDescription)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if type.isDismissible {
                Toggle("", isOn: Binding(
                    get: { settings.isNotificationEnabled(type) },
                    set: { settings.setNotificationEnabled(type, enabled: $0) }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
            } else {
                Text(String(localized: "notifications.alwaysOn"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    private func iconColor(for type: NotificationCatalog.NotificationType) -> Color {
        switch type.style {
        case .success: return .green
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        }
    }
}
