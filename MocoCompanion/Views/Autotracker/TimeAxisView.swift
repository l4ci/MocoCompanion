import SwiftUI

/// Layout constants shared across timeline components.
enum TimelineLayout {
    static let pixelsPerMinute: CGFloat = 1.5
    static let timeAxisWidth: CGFloat = 50
    static let appUsagePaneWidth: CGFloat = 200
    static let calendarPaneWidth: CGFloat = 200
    static let blockCornerRadius: CGFloat = Theme.Radius.medium
    /// Coarse snap for timeline gestures (drag-move, edge-resize, drag-create).
    /// For finer-grained edits (precise minute adjustment), use the Edit sheet.
    static let snapMinutes: Int = 15
    static let totalHeight: CGFloat = 24 * 60 * pixelsPerMinute

    /// Scale factor derived from the user's font-size boost (0–3 pt).
    /// Matches the panel's width-scaling formula: `base * (15 + boost) / 15`.
    static func scale(for fontBoost: CGFloat) -> CGFloat {
        (15 + fontBoost) / 15
    }
}

/// Vertical time ruler showing 00:00–23:00 hour labels with faint 5-minute grid lines.
struct TimeAxisView: View {
    @Environment(\.theme) private var theme
    @Environment(\.entryFontSizeBoost) private var fontBoost

    private var scaledWidth: CGFloat { TimelineLayout.timeAxisWidth * TimelineLayout.scale(for: fontBoost) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Hour labels
            ForEach(0..<24, id: \.self) { hour in
                Text(String(format: "%02d:00", hour))
                    .font(.system(size: Theme.FontSize.caption + fontBoost, design: .monospaced))
                    .foregroundStyle(theme.textTertiary)
                    .offset(y: CGFloat(hour * 60) * TimelineLayout.pixelsPerMinute - 6)
            }
        }
        .frame(width: scaledWidth, height: TimelineLayout.totalHeight, alignment: .topLeading)
        .padding(.leading, 4)
    }
}

/// Full-width background grid drawn behind both panes.
struct TimeAxisGridBackground: View {
    var workdayStartHour: Int = 8
    var workdayEndHour: Int = 17
    /// When true, the workday band is suppressed (weekends).
    var isWeekend: Bool = false
    /// Optional absence for the day — rendered as a tinted band with icon.
    var absence: MocoSchedule? = nil
    @Environment(\.theme) private var theme

    var body: some View {
        ZStack(alignment: .topLeading) {
            Canvas { context, size in
                let ppm = TimelineLayout.pixelsPerMinute

                // Workday background band — hidden on weekends
                if !isWeekend {
                    let workStart = CGFloat(workdayStartHour * 60) * ppm
                    let workEnd = CGFloat(workdayEndHour * 60) * ppm
                    let workRect = CGRect(x: 0, y: workStart, width: size.width, height: workEnd - workStart)
                    context.fill(Path(workRect), with: .color(Color.accentColor.opacity(0.04)))
                }

                // Hour lines
                for hour in 0...24 {
                    let y = CGFloat(hour * 60) * ppm
                    let path = Path { p in
                        p.move(to: CGPoint(x: 0, y: y))
                        p.addLine(to: CGPoint(x: size.width, y: y))
                    }
                    context.stroke(path, with: .color(Color.primary.opacity(0.08)), lineWidth: 0.5)
                }
            }

            // Absence overlay — tinted band over the workday range with icon
            if let absence {
                let info = AbsenceStyle.resolve(absence)
                let ppm = TimelineLayout.pixelsPerMinute
                let startY = CGFloat(workdayStartHour * 60) * ppm
                let endY = CGFloat(workdayEndHour * 60) * ppm
                info.color.opacity(0.06)
                    .frame(height: endY - startY)
                    .offset(y: startY)
                    .overlay(alignment: .center) {
                        VStack(spacing: 4) {
                            Image(systemName: info.icon)
                                .font(.system(size: 28, weight: .light))
                                .foregroundStyle(info.color.opacity(0.3))
                            Text(absence.assignment.name)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(info.color.opacity(0.4))
                        }
                        .offset(y: startY + (endY - startY) / 2)
                    }
                    .allowsHitTesting(false)
            }
        }
        .frame(height: TimelineLayout.totalHeight)
        .allowsHitTesting(false)
    }
}
