import SwiftUI

/// Date navigation bar for the Autotracker timeline: previous/next day arrows,
/// date label with popover picker, and a Today badge.
struct DateNavigationView: View {
    @Bindable var viewModel: TimelineViewModel
    @Environment(\.theme) private var theme

    @State private var showingDatePicker = false

    private static let displayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE, d MMM yyyy"
        return f
    }()

    /// "Do., 9 Apr. 2026 (KW: 13)" — appends the ISO calendar week so
    /// users can match the date to their weekly planning views.
    private static func dateLabel(for date: Date) -> String {
        let base = displayFormatter.string(from: date)
        let week = Calendar.current.component(.weekOfYear, from: date)
        return "\(base) (KW: \(week))"
    }

    var body: some View {
        HStack(spacing: 12) {
            Button("Previous Day", systemImage: "chevron.left", action: viewModel.selectPreviousDay)
                .labelStyle(.iconOnly)
                .font(.system(size: Theme.FontSize.callout, weight: .medium))
                .disabled(!viewModel.canSelectPreviousDay)
                .buttonStyle(.plain)
                .foregroundStyle(theme.textSecondary)

            Spacer()

            Text(Self.dateLabel(for: viewModel.selectedDate))
                .font(.system(size: Theme.FontSize.title, weight: .semibold))
                .foregroundStyle(theme.textPrimary)
                .onTapGesture(count: 1) {
                    showingDatePicker.toggle()
                }
                .onTapGesture(count: 2) {
                    viewModel.selectToday()
                }
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("Select date")
                .popover(isPresented: $showingDatePicker) {
                    DatePicker(
                        "",
                        selection: Binding(
                            get: { viewModel.selectedDate },
                            set: { date in
                                viewModel.selectDate(date)
                                showingDatePicker = false
                            }
                        ),
                        // Clamp to the retention window: no data exists
                        // before the autotracker deletion threshold, and
                        // we don't let the user navigate into the future.
                        in: viewModel.autotracker.earliestRetainedDate...Date.now,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)
                    .padding()
                }

            Button("Today", action: viewModel.selectToday)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(viewModel.isToday)
                .help("Jump to today")
                .accessibilityLabel(String(localized: "date.today"))

            Spacer()

            Button("Next Day", systemImage: "chevron.right", action: viewModel.selectNextDay)
                .labelStyle(.iconOnly)
                .font(.system(size: Theme.FontSize.body, weight: .medium))
                .buttonStyle(.plain)
                .foregroundStyle(viewModel.isToday ? theme.textTertiary.opacity(0.5) : theme.textSecondary)
                .disabled(viewModel.isToday)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }
}
