import AppKit
import Carbon
import SwiftUI

/// A SwiftUI wrapper around a custom NSView that captures keyboard shortcuts.
/// Displays the current shortcut and allows the user to record a new key combination.
struct ShortcutRecorderView: NSViewRepresentable {
    @Binding var keyCode: UInt32
    @Binding var modifiers: UInt32
    var onShortcutChanged: ((UInt32, UInt32) -> Void)?

    func makeNSView(context: Context) -> ShortcutRecorderNSView {
        let view = ShortcutRecorderNSView()
        view.keyCode = keyCode
        view.modifiers = modifiers
        view.onShortcutChanged = { newCode, newMods in
            keyCode = newCode
            modifiers = newMods
            onShortcutChanged?(newCode, newMods)
        }
        return view
    }

    func updateNSView(_ nsView: ShortcutRecorderNSView, context: Context) {
        nsView.keyCode = keyCode
        nsView.modifiers = modifiers
        nsView.updateDisplayIfNeeded()
    }
}

/// Custom NSView that captures key-down events to record a shortcut.
/// Click to enter recording mode, press a key combo to set, Escape to cancel.
final class ShortcutRecorderNSView: NSView {
    var keyCode: UInt32 = 0
    var modifiers: UInt32 = 0
    var onShortcutChanged: ((UInt32, UInt32) -> Void)?

    private var isRecording = false
    private let label = NSTextField(labelWithString: "")
    private let recordButton = NSButton(title: "Record", target: nil, action: nil)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        label.font = .systemFont(ofSize: 13)
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false

        recordButton.bezelStyle = .rounded
        recordButton.target = self
        recordButton.action = #selector(toggleRecording)
        recordButton.translatesAutoresizingMaskIntoConstraints = false

        addSubview(label)
        addSubview(recordButton)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),

            recordButton.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 8),
            recordButton.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -4),
            recordButton.centerYAnchor.constraint(equalTo: centerYAnchor),

            heightAnchor.constraint(greaterThanOrEqualToConstant: 24),
        ])

        updateDisplay()
    }

    func updateDisplayIfNeeded() {
        if !isRecording {
            updateDisplay()
        }
    }

    private func updateDisplay() {
        if keyCode == 0 && modifiers == 0 {
            label.stringValue = "⌘⌥⌃⇧M (default)"
        } else {
            let combo = KeyCombo(carbonKeyCode: keyCode, carbonModifiers: modifiers)
            label.stringValue = combo.description.isEmpty ? "None" : combo.description
        }
        recordButton.title = isRecording ? "Cancel" : "Record"
    }

    @objc private func toggleRecording() {
        isRecording.toggle()
        if isRecording {
            label.stringValue = "Press shortcut…"
            window?.makeFirstResponder(self)
        } else {
            updateDisplay()
        }
    }

    // MARK: - Key Capture

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }

        // Escape cancels recording
        if event.keyCode == UInt16(kVK_Escape) {
            isRecording = false
            updateDisplay()
            return
        }

        // Require at least one modifier (Cmd, Ctrl, Option)
        let requiredModifiers: NSEvent.ModifierFlags = [.command, .control, .option]
        guard !event.modifierFlags.intersection(requiredModifiers).isEmpty else {
            return
        }

        let carbonMods = event.modifierFlags.intersection([.command, .control, .option, .shift]).carbonFlags
        let carbonKey = UInt32(event.keyCode)

        keyCode = carbonKey
        modifiers = carbonMods
        isRecording = false

        updateDisplay()
        onShortcutChanged?(carbonKey, carbonMods)
    }

    // Prevent the system beep on key events while recording
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if isRecording { return true }
        return super.performKeyEquivalent(with: event)
    }
}
