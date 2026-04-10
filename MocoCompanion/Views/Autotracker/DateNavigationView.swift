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
                    .font(.system(size: Theme.FontSize.body, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.textSecondary)

            Spacer()

            Text(Self.displayFormatter.string(from: viewModel.selectedDate))
                .font(.system(size: Theme.FontSize.callout, weight: .semibold))
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
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)
                    .padding()
                }

            if viewModel.isToday {
                Text("Today")
                    .font(.system(size: Theme.FontSize.caption, weight: .medium))
                    .foregroundStyle(theme.textTertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
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
