import SwiftUI

/// Date navigation bar for the Autotracker timeline: previous/next day arrows,
/// date label with popover picker, and a conditional "Go to: Today" button.
struct DateNavigationView: View {
    @Bindable var viewModel: TimelineViewModel
    @Environment(\.theme) private var theme
    @Environment(\.entryFontSizeBoost) private var fontBoost

    @State private var showingDatePicker = false

    private static let displayFormatter: DateFormatter = {
        let f = DateFormatter()
        // "Dienstag, 14. April" / "Monday, 14 April"
        f.dateFormat = "EEEE, d. MMMM"
        return f
    }()

    /// "Dienstag, 14. April (KW 16)"
    private static func dateLabel(for date: Date) -> String {
        let base = displayFormatter.string(from: date)
        let week = Calendar.current.component(.weekOfYear, from: date)
        return "\(base) (KW \(week))"
    }

    var body: some View {
        HStack(spacing: 12) {
            Button("Previous Day", systemImage: "chevron.left", action: viewModel.selectPreviousDay)
                .labelStyle(.iconOnly)
                .font(.system(size: Theme.FontSize.callout + fontBoost, weight: .medium))
                .disabled(!viewModel.canSelectPreviousDay)
                .buttonStyle(.plain)
                .foregroundStyle(theme.textSecondary)

            Spacer()

            HStack(spacing: 8) {
                // Blue dot indicator for today
                if viewModel.isToday {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 7, height: 7)
                }

                Text(Self.dateLabel(for: viewModel.selectedDate))
                    .font(.system(size: Theme.FontSize.title + fontBoost, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
            }
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
                    in: viewModel.autotracker.earliestRetainedDate...Date.now,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .padding()
            }

            // "Go to: Today" — only shown when viewing a past day
            if !viewModel.isToday {
                Button("Go to: Today", action: viewModel.selectToday)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Jump to today")
                    .accessibilityLabel(String(localized: "date.today"))
            }

            Spacer()

            Button("Next Day", systemImage: "chevron.right", action: viewModel.selectNextDay)
                .labelStyle(.iconOnly)
                .font(.system(size: Theme.FontSize.body + fontBoost, weight: .medium))
                .buttonStyle(.plain)
                .foregroundStyle(viewModel.isToday ? theme.textTertiary.opacity(0.5) : theme.textSecondary)
                .disabled(viewModel.isToday)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }
}
