import Foundation

/// Day selection for Today/Yesterday/Tomorrow navigation.
/// Extracted from TodayView so TodayViewModel can reference it without pulling in the full View.
enum DaySelection: CaseIterable {
    case yesterday
    case today
    case tomorrow

    var label: String {
        switch self {
        case .today: String(localized: "today.title")
        case .yesterday: String(localized: "yesterday.title")
        case .tomorrow: String(localized: "tomorrow.title")
        }
    }

    var dateString: String {
        switch self {
        case .today: DateUtilities.todayString()
        case .yesterday: DateUtilities.yesterdayString() ?? ""
        case .tomorrow: DateUtilities.tomorrowString() ?? ""
        }
    }
}
