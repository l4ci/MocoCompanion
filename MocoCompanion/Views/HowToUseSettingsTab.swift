import SwiftUI

/// How to Use settings tab: global shortcut configuration and usage instructions.
struct HowToUseSettingsTab: View {
    @Bindable var settings: SettingsStore
    var onShortcutChanged: ((UInt32, UInt32) -> Void)?

    var body: some View {
        Form {
            Section {
                HStack {
                    Text(String(localized: "settings.currentShortcut"))
                    Spacer()
                    Text(currentShortcutDisplay)
                        .font(.system(.body, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                }

                ShortcutRecorderView(
                    keyCode: $settings.customShortcutKeyCode,
                    modifiers: $settings.customShortcutModifiers,
                    onShortcutChanged: onShortcutChanged
                )
                .frame(height: 28)
            } header: {
                Text(String(localized: "settings.globalShortcut"))
            }

            Section {
                VStack(alignment: .leading, spacing: 6) {
                    instructionRow(String(localized: "howto.openPanel"))
                    instructionRow(String(localized: "howto.typeToSearch"))
                    instructionRow(String(localized: "howto.cmdSelect"))
                    instructionRow(String(localized: "howto.arrowNav"))
                    instructionRow(String(localized: "howto.emptyToggle"))
                    instructionRow(String(localized: "howto.tagging"))
                    instructionRow(String(localized: "howto.tabAutocomplete"))
                }
            } header: {
                Text(String(localized: "howto.searchSection"))
            }

            Section {
                VStack(alignment: .leading, spacing: 6) {
                    instructionRow(String(localized: "howto.tabSwitch"))
                    instructionRow(String(localized: "howto.todayArrowNav"))
                    instructionRow(String(localized: "howto.enterContinue"))
                    instructionRow(String(localized: "howto.editDesc"))
                    instructionRow(String(localized: "howto.deleteEntry"))
                }
            } header: {
                Text(String(localized: "howto.todaySection"))
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Helpers

    private func instructionRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("•")
                .foregroundStyle(.secondary)
            Text(text)
                .font(.callout)
        }
    }

    private var currentShortcutDisplay: String {
        if settings.hasCustomShortcut {
            let combo = KeyCombo(
                carbonKeyCode: settings.customShortcutKeyCode,
                carbonModifiers: settings.customShortcutModifiers
            )
            let desc = combo.description
            return desc.isEmpty ? "None" : desc
        }
        return "⌘⌃⌥M"
    }
}
