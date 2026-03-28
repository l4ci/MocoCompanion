import SwiftUI

/// Centralized adaptive color system for the app.
/// Provides all semantic colors from one place, resolving light/dark variants.
/// Use via `@Environment(\.theme)` after injecting with `.withTheme(colorScheme:)` at root.
struct Theme {
    let colorScheme: ColorScheme

    private var isDark: Bool { colorScheme == .dark }

    // MARK: - Backgrounds

    /// Panel background — very slight blue tint for warmth.
    var panelBackground: Color {
        isDark
            ? Color(red: 0.11, green: 0.11, blue: 0.13)
            : Color(red: 0.975, green: 0.975, blue: 0.985)
    }

    /// Subtle surface tint for cards, badges, and inset areas.
    var surface: Color {
        isDark
            ? Color.white.opacity(0.06)
            : Color.black.opacity(0.035)
    }

    /// Elevated surface — slightly brighter than surface, for stat cards and highlights.
    var surfaceElevated: Color {
        isDark
            ? Color.white.opacity(0.08)
            : Color.black.opacity(0.025)
    }

    // MARK: - Dividers & Separators

    /// Thin divider lines.
    var divider: Color {
        isDark
            ? Color.white.opacity(0.1)
            : Color.black.opacity(0.08)
    }

    // MARK: - Interactive States

    /// Selected item background.
    var selection: Color {
        Color.accentColor
    }

    /// Hover highlight.
    var hover: Color {
        isDark
            ? Color.white.opacity(0.07)
            : Color.black.opacity(0.04)
    }

    /// Running timer tint.
    var runningTint: Color {
        isDark
            ? Color.green.opacity(0.12)
            : Color.green.opacity(0.07)
    }

    /// Running timer hover — slightly stronger green.
    var runningHover: Color {
        isDark
            ? Color.green.opacity(0.20)
            : Color.green.opacity(0.13)
    }

    /// Paused timer tint.
    var pausedTint: Color {
        isDark
            ? Color.orange.opacity(0.10)
            : Color.orange.opacity(0.06)
    }

    /// Paused timer hover — slightly stronger orange.
    var pausedHover: Color {
        isDark
            ? Color.orange.opacity(0.18)
            : Color.orange.opacity(0.11)
    }

    // MARK: - Text Hierarchy

    /// Primary label — highest contrast.
    var textPrimary: Color {
        isDark ? .white : Color(red: 0.10, green: 0.11, blue: 0.14)
    }

    /// Secondary label — supporting text. Meets WCAG AA 4.5:1 contrast.
    var textSecondary: Color {
        isDark
            ? Color.white.opacity(0.65)
            : Color.black.opacity(0.55)
    }

    /// Tertiary label — hints, metadata, keyboard shortcuts. Meets WCAG 3:1 for large text.
    var textTertiary: Color {
        isDark
            ? Color.white.opacity(0.45)
            : Color.black.opacity(0.45)
    }

    // MARK: - Component Specific

    /// Search field background (subtle inset).
    var searchFieldBackground: Color {
        isDark
            ? Color.white.opacity(0.06)
            : Color.black.opacity(0.04)
    }

    /// Tab switcher pill background.
    var tabPillBackground: Color {
        isDark
            ? Color.white.opacity(0.08)
            : Color.black.opacity(0.06)
    }

    /// Active tab pill.
    var tabPillActive: Color {
        isDark
            ? Color.white.opacity(0.18)
            : Color.white
    }

    /// Stat card background.
    var statCardBackground: Color {
        isDark
            ? Color.white.opacity(0.05)
            : Color.black.opacity(0.025)
    }

    // MARK: - Design System Constants

    /// Type scale: 7 sizes covering all UI needs.
    /// caption=10, footnote=11, subhead=12, body=13, callout=14, title=18, largeTitle=22
    enum FontSize {
        static let caption: CGFloat = 10
        static let footnote: CGFloat = 11
        static let subhead: CGFloat = 12
        static let body: CGFloat = 13
        static let callout: CGFloat = 14
        static let title: CGFloat = 18
        static let largeTitle: CGFloat = 22
    }

    /// Corner radius scale: 3 values.
    enum Radius {
        static let small: CGFloat = 4    // badges, tags, pills
        static let medium: CGFloat = 8   // cards, rows, inputs
        static let large: CGFloat = 14   // panels, sheets
    }

    /// Animation durations.
    enum Motion {
        static let fast: Double = 0.12      // exit, micro-feedback
        static let standard: Double = 0.18  // state transitions, enter
        static let slow: Double = 0.30      // complex transitions
    }

    // MARK: - Utilities

    /// Resolve a `ColorScheme?` from the user's appearance setting.
    static func colorScheme(from setting: String) -> ColorScheme? {
        switch setting {
        case "light": .light
        case "dark": .dark
        default: nil
        }
    }
}

// MARK: - SwiftUI Environment

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = Theme(colorScheme: .light)
}

/// Extra font-size boost for entry rows (0–5 points).
private struct EntryFontSizeBoostKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }

    var entryFontSizeBoost: CGFloat {
        get { self[EntryFontSizeBoostKey.self] }
        set { self[EntryFontSizeBoostKey.self] = newValue }
    }
}

extension View {
    /// Inject the theme based on the current color scheme.
    func withTheme(colorScheme: ColorScheme) -> some View {
        self.environment(\.theme, Theme(colorScheme: colorScheme))
    }
}
