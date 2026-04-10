import SwiftUI

/// A horizontal red line indicating the current time on the timeline.
/// Only rendered when the selected date is today. Updates position every 60 seconds.
struct NowLineView: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let minuteOfDay = Self.currentMinuteOfDay(at: context.date)
            let y = CGFloat(minuteOfDay) * TimelineLayout.pixelsPerMinute

            HStack(spacing: 0) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 6, height: 6)
                Rectangle()
                    .fill(Color.red)
                    .frame(height: 1)
            }
            .offset(y: y - 3) // center the 6pt circle on the line
        }
        .frame(height: TimelineLayout.totalHeight, alignment: .topLeading)
    }

    private static func currentMinuteOfDay(at date: Date) -> Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }
}
