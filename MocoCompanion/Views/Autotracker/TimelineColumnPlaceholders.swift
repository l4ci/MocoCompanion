import AppKit
import SwiftUI

/// Empty-state overlay shown in the calendar column when the feature
/// is enabled but not yet producing events. Four states: permission
/// not determined, denied, authorized-but-no-calendar-selected, or
/// no events on the current day.
enum CalendarColumnPlaceholder {
    case needsPermission
    case denied
    case noCalendarSelected
    case noEvents
}

struct CalendarColumnPlaceholderView: View {
    let state: CalendarColumnPlaceholder
    var columnWidth: CGFloat = TimelineLayout.calendarPaneWidth
    var onOpenSettings: () -> Void = {}
    var onRequestAccess: () -> Void = {}
    @Environment(\.theme) private var theme
    @Environment(\.entryFontSizeBoost) private var fontBoost

    var body: some View {
        VStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(title)
                .font(.system(size: Theme.FontSize.footnote + fontBoost, weight: .medium))
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.center)
            if let action {
                Button(action.label, action: action.handler)
                    .buttonStyle(.borderless)
                    .font(.system(size: Theme.FontSize.footnote + fontBoost))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(16)
        .frame(width: columnWidth - 8)
    }

    private var color: Color {
        switch state {
        case .needsPermission: return .orange
        case .denied: return .red
        case .noCalendarSelected, .noEvents: return theme.textTertiary
        }
    }

    private var title: String {
        switch state {
        case .needsPermission: return String(localized: "calendar.placeholder.needsPermission")
        case .denied: return String(localized: "calendar.placeholder.denied")
        case .noCalendarSelected: return String(localized: "calendar.placeholder.noCalendar")
        case .noEvents: return String(localized: "calendar.placeholder.noEvents")
        }
    }

    private var action: (label: String, handler: () -> Void)? {
        switch state {
        case .needsPermission:
            return (String(localized: "calendar.placeholder.grantAccess"), onRequestAccess)
        case .denied:
            return (String(localized: "calendar.placeholder.openSettings"), onOpenSettings)
        case .noCalendarSelected, .noEvents:
            return nil
        }
    }
}

/// Placeholder for the "Track window titles" Accessibility permission
/// — shown as a one-time overlay on the app usage column when the
/// sub-feature is enabled but AX trust hasn't been granted.
enum AccessibilityColumnPlaceholder {
    case needsPermission
    case denied
}

struct AccessibilityColumnPlaceholderView: View {
    let state: AccessibilityColumnPlaceholder
    var columnWidth: CGFloat = TimelineLayout.appUsagePaneWidth
    var onOpenSettings: () -> Void = {}
    var onRequestAccess: () -> Void = {}
    @Environment(\.theme) private var theme
    @Environment(\.entryFontSizeBoost) private var fontBoost

    var body: some View {
        VStack(spacing: 8) {
            Circle()
                .fill(state == .denied ? Color.red : Color.orange)
                .frame(width: 8, height: 8)
            Text(state == .denied
                 ? String(localized: "accessibility.placeholder.denied")
                 : String(localized: "accessibility.placeholder.needsPermission"))
                .font(.system(size: Theme.FontSize.footnote + fontBoost, weight: .medium))
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.center)
            Button(state == .denied
                   ? String(localized: "accessibility.placeholder.openSettings")
                   : String(localized: "accessibility.placeholder.grantAccess"),
                   action: state == .denied ? onOpenSettings : onRequestAccess)
                .buttonStyle(.borderless)
                .font(.system(size: Theme.FontSize.footnote + fontBoost))
                .foregroundStyle(Color.accentColor)
        }
        .padding(16)
        .frame(width: columnWidth - 8)
    }
}
