import SwiftUI

/// Deterministic color assignment for projects. Each projectId maps to a stable
/// color from a curated palette, so the same project always gets the same color
/// across sessions and views.
enum ProjectColorPalette {
    /// Muted, accessible colors that work in both light and dark mode.
    /// Chosen for distinguishability without being garish.
    private static let colors: [Color] = [
        Color(hue: 0.60, saturation: 0.55, brightness: 0.75),  // steel blue
        Color(hue: 0.85, saturation: 0.45, brightness: 0.70),  // muted purple
        Color(hue: 0.45, saturation: 0.50, brightness: 0.65),  // teal
        Color(hue: 0.08, saturation: 0.55, brightness: 0.80),  // warm orange
        Color(hue: 0.55, saturation: 0.40, brightness: 0.70),  // slate cyan
        Color(hue: 0.95, saturation: 0.45, brightness: 0.75),  // rose
        Color(hue: 0.35, saturation: 0.50, brightness: 0.60),  // olive green
        Color(hue: 0.75, saturation: 0.40, brightness: 0.70),  // lavender
        Color(hue: 0.15, saturation: 0.55, brightness: 0.75),  // amber
        Color(hue: 0.50, saturation: 0.45, brightness: 0.65),  // ocean
        Color(hue: 0.00, saturation: 0.45, brightness: 0.75),  // coral red
        Color(hue: 0.30, saturation: 0.45, brightness: 0.65),  // sage
    ]

    /// Returns a stable color for a given project ID.
    static func color(for projectId: Int) -> Color {
        colors[abs(projectId) % colors.count]
    }
}
