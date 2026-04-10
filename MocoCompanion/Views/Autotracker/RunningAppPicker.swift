import AppKit
import SwiftUI

/// A user-facing app detected via `NSWorkspace.runningApplications`.
struct RunningAppOption: Identifiable, Hashable {
    let id: String       // bundle identifier
    let name: String     // localized display name
}

/// Fetch the currently running user-facing applications (activation
/// policy `.regular`) so the user can pick from a list instead of
/// typing a bundle identifier.
func fetchRunningApps() -> [RunningAppOption] {
    NSWorkspace.shared.runningApplications
        .filter { $0.activationPolicy == .regular }
        .compactMap { app -> RunningAppOption? in
            guard let bundleId = app.bundleIdentifier,
                  let displayName = app.localizedName
            else { return nil }
            return RunningAppOption(id: bundleId, name: displayName)
        }
        .reduce(into: [RunningAppOption]()) { acc, item in
            if !acc.contains(where: { $0.id == item.id }) { acc.append(item) }
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
}

/// Reusable Menu-based picker that lists currently running user-facing apps.
/// Invokes `onPick` with `(bundleId, displayName)` when the user selects an app.
struct RunningAppPicker: View {
    var label: String = "Choose running app…"
    var onPick: (String, String) -> Void

    @Environment(\.theme) private var theme
    @State private var runningApps: [RunningAppOption] = []

    var body: some View {
        Menu {
            if runningApps.isEmpty {
                Text("No running apps detected")
            } else {
                ForEach(runningApps) { app in
                    Button {
                        onPick(app.id, app.name)
                    } label: {
                        Text("\(app.name)  (\(app.id))")
                    }
                }
            }
            Divider()
            Button("Refresh list") {
                runningApps = fetchRunningApps()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "app.dashed")
                    .foregroundStyle(theme.textTertiary)
                Text(label)
                    .foregroundStyle(theme.textTertiary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10))
                    .foregroundStyle(theme.textTertiary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(theme.textTertiary.opacity(0.3), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            runningApps = fetchRunningApps()
        }
    }
}
