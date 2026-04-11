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

    var body: some View {
        HStack(spacing: 12) {
            Button(action: viewModel.selectPreviousDay) {
                Image(systemName: "chevron.left")
                    .font(.system(size: Theme.FontSize.callout, weight: .medium))
            }
            .disabled(!viewModel.canSelectPreviousDay)
            .buttonStyle(.plain)
            .foregroundStyle(theme.textSecondary)

            Spacer()

            Text(Self.displayFormatter.string(from: viewModel.selectedDate))
                .font(.system(size: Theme.FontSize.title, weight: .semibold))
                .foregroundStyle(theme.textPrimary)
                .onTapGesture {
                    showingDatePicker.toggle()
                }
                .onTapGesture(count: 2) {
                    viewModel.selectToday()
                }
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
                        in: viewModel.autotracker.earliestRetainedDate...Date(),
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)
                    .padding()
                }

            if viewModel.isToday {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 8, height: 8)
                    .help("Today")
                    .accessibilityLabel(String(localized: "date.today"))
            }

            Spacer()

            Button(action: viewModel.selectNextDay) {
                Image(systemName: "chevron.right")
                    .font(.system(size: Theme.FontSize.body, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(viewModel.isToday ? theme.textTertiary.opacity(0.5) : theme.textSecondary)
            .disabled(viewModel.isToday)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }
}
