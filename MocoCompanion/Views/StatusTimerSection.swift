import SwiftUI

/// Timer status section for the status popover.
/// Shows idle, running (with stop button), or paused state.
struct StatusTimerSection: View {
    let timerState: TimerState
    let currentActivity: ShadowEntry?
    var onStop: () -> Void

    var body: some View {
        switch timerState {
        case .idle:
            HStack(spacing: 10) {
                Image(systemName: "clock")
                    .foregroundStyle(.tertiary)
                    .font(.system(size: 18))
                Text(String(localized: "popover.noTimer"))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 16)

        case .running(_, let projectName):
            HStack(spacing: 10) {
                Circle()
                    .fill(.green)
                    .frame(width: 8, height: 8)
                    .shadow(color: .green.opacity(0.4), radius: 3)

                ElapsedTimeText(activity: currentActivity)

                Spacer()

                Button(action: onStop) {
                    Label(String(localized: "popover.stop"), systemImage: "stop.fill")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .controlSize(.small)
                .accessibilityLabel(String(localized: "a11y.stopTimer \(projectName)"))
            }
            .padding(.vertical, 8)

        case .paused(_, let projectName):
            HStack(spacing: 10) {
                Circle()
                    .fill(.orange)
                    .frame(width: 8, height: 8)

                Text(String(localized: "popover.paused"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.orange)

                Text("· \(projectName)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer()
            }
            .padding(.vertical, 8)
        }
    }
}
