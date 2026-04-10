import SwiftUI

/// Layout constants shared across timeline components.
enum TimelineLayout {
    static let pixelsPerMinute: CGFloat = 1.5
    static let timeAxisWidth: CGFloat = 50
    static let appUsagePaneWidth: CGFloat = 140
    static let blockCornerRadius: CGFloat = Theme.Radius.medium
    static let snapMinutes: Int = 5
    static let totalHeight: CGFloat = 24 * 60 * pixelsPerMinute
}

/// Vertical time ruler showing 00:00–23:00 hour labels with faint 5-minute grid lines.
struct TimeAxisView: View {
    @Environment(\.theme) private var theme

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Hour labels
            ForEach(0..<24, id: \.self) { hour in
                Text(String(format: "%02d:00", hour))
                    .font(.system(size: Theme.FontSize.caption, design: .monospaced))
                    .foregroundStyle(theme.textTertiary)
                    .offset(y: CGFloat(hour * 60) * TimelineLayout.pixelsPerMinute - 6)
            }
        }
        .frame(width: TimelineLayout.timeAxisWidth, height: TimelineLayout.totalHeight, alignment: .topLeading)
        .padding(.leading, 4)
    }
}

/// Full-width background grid drawn behind both panes.
struct TimeAxisGridBackground: View {
    @Environment(\.theme) private var theme

    var body: some View {
        Canvas { context, size in
            let ppm = TimelineLayout.pixelsPerMinute
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
        .frame(height: TimelineLayout.totalHeight)
        .allowsHitTesting(false)
    }
}
