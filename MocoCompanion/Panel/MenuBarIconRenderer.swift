import AppKit

/// Pure icon compositing — stateless, testable, no controller dependency.
/// Renders an SF Symbol with a colored indicator dot at the bottom-right.
enum MenuBarIconRenderer {

    /// Composites an SF Symbol with a small colored indicator dot at the bottom-right.
    /// - Parameters:
    ///   - symbolName: SF Symbol name (e.g. "timer")
    ///   - dotColor: Color for the indicator dot
    ///   - isDarkMenubar: Whether the menubar has a dark appearance (white icon) or light (black icon)
    ///   - accessibilityDescription: VoiceOver description for the icon
    static func makeIconWithDot(symbolName: String, dotColor: NSColor, isDarkMenubar: Bool, accessibilityDescription: String) -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        guard let templateSymbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: accessibilityDescription)?
            .withSymbolConfiguration(config) else {
            return NSImage(systemSymbolName: symbolName, accessibilityDescription: accessibilityDescription) ?? NSImage()
        }

        let symbolSize = templateSymbol.size
        let canvasSize = NSSize(width: symbolSize.width + 4, height: symbolSize.height)
        let symbolTint: NSColor = isDarkMenubar ? .white : .black

        let image = NSImage(size: canvasSize, flipped: false) { rect in
            guard let tintedSymbol = templateSymbol.copy() as? NSImage else { return false }
            tintedSymbol.lockFocus()
            symbolTint.set()
            NSRect(origin: .zero, size: symbolSize).fill(using: .sourceAtop)
            tintedSymbol.unlockFocus()

            tintedSymbol.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1.0)

            // Indicator dot at bottom-right
            let dotSize: CGFloat = 5
            let dotX = rect.width - dotSize - 0.5
            let dotY: CGFloat = 1
            let dotRect = NSRect(x: dotX, y: dotY, width: dotSize, height: dotSize)
            dotColor.setFill()
            NSBezierPath(ovalIn: dotRect).fill()

            return true
        }
        image.isTemplate = false
        return image
    }
}
