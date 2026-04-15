import SwiftUI

/// A horizontal red line indicating the current time on the timeline.
/// Only rendered when the selected date is today. Updates position every 60 seconds.
struct NowLineView: View {
    @Environment(\.timelineActive) private var timelineActive

    var body: some View {
        if timelineActive {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                nowLine(at: context.date)
            }
            .frame(height: TimelineLayout.totalHeight, alignment: .topLeading)
        } else {
            nowLine(at: Date())
                .frame(height: TimelineLayout.totalHeight, alignment: .topLeading)
        }
    }

    private func nowLine(at date: Date) -> some View {
        let minuteOfDay = Self.currentMinuteOfDay(at: date)
        let y = CGFloat(minuteOfDay) * TimelineLayout.pixelsPerMinute

        return HStack(spacing: 0) {
            Circle()
                .fill(Color.red)
                .frame(width: 6, height: 6)
            Rectangle()
                .fill(Color.red)
                .frame(height: 1)
        }
        .offset(y: y - 3) // center the 6pt circle on the line
    }

    private static func currentMinuteOfDay(at date: Date) -> Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }
}
