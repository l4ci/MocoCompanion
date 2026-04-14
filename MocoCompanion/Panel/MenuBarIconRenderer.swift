import AppKit

/// Pure icon compositing — stateless, testable, no controller dependency.
/// Renders an SF Symbol with a colored indicator dot at the bottom-right.
enum MenuBarIconRenderer {

    /// Composites an SF Symbol with a small colored indicator dot at the bottom-right.
    /// The symbol is drawn as a template so macOS automatically matches the
    /// menubar appearance (white on dark, black on light). Only the dot is
    /// drawn in a fixed color.
    static func makeIconWithDot(symbolName: String, dotColor: NSColor, accessibilityDescription: String) -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        guard let templateSymbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: accessibilityDescription)?
            .withSymbolConfiguration(config) else {
            return NSImage(systemSymbolName: symbolName, accessibilityDescription: accessibilityDescription) ?? NSImage()
        }

        let symbolSize = templateSymbol.size
        let canvasSize = NSSize(width: symbolSize.width + 4, height: symbolSize.height)

        let image = NSImage(size: canvasSize, flipped: false) { rect in
            // Draw the symbol as-is (template tinting handled by AppKit)
            templateSymbol.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1.0)

            // Indicator dot at bottom-right (always fixed color)
            let dotSize: CGFloat = 5
            let dotX = rect.width - dotSize - 0.5
            let dotY: CGFloat = 1
            let dotRect = NSRect(x: dotX, y: dotY, width: dotSize, height: dotSize)
            dotColor.setFill()
            NSBezierPath(ovalIn: dotRect).fill()

            return true
        }
        image.isTemplate = true
        return image
    }
}
