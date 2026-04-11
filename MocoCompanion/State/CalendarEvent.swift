import Foundation
import SwiftUI

/// Ephemeral snapshot of an EKEvent at fetch time. Never persisted —
/// re-fetched on every CalendarService invocation. Parallels
/// `AppUsageBlock` in structure so the view layer can treat both
/// kinds of external-source blocks uniformly.
struct CalendarEvent: Identifiable, Equatable, Sendable {
    /// Stable identifier from EKEvent.eventIdentifier. Used for
    /// Identifiable, SwiftUI list diffing, and nothing else — the
    /// cross-link with Moco entries uses calendarItemIdentifier.
    let id: String

    /// EKEvent.calendarItemIdentifier — the identifier to pass to
    /// `ical://ekevent/<id>` when "Open in Calendar" is invoked,
    /// and the value stored on a ShadowEntry's sourceCalendarEventId.
    let calendarItemIdentifier: String

    let title: String
    let location: String?
    let startDate: Date
    let endDate: Date

    /// True if this event has no start/end time (birthdays, vacations,
    /// full-day conferences). Rendered in the aboveline region, not
    /// in the timeline's calendar column.
    let isAllDay: Bool

    /// True if the user has accepted the invite OR is the organizer
    /// (events the user created with no attendees count as
    /// self-organized). Gate for rule firing — declined / tentative
    /// / external-only events do not auto-create entries.
    let isAcceptedByUser: Bool

    /// Resolved from `EKCalendar.cgColor` at fetch time. Value-typed
    /// so it can cross actor boundaries safely and survive EKEvent
    /// lifetime concerns.
    let calendarColorHex: String

    var color: Color {
        Color(hex: calendarColorHex) ?? .accentColor
    }

    /// Minutes since start of day for the event's start. Returns
    /// nil for all-day events.
    var startMinutes: Int? {
        guard !isAllDay else { return nil }
        let comps = Calendar.current.dateComponents([.hour, .minute], from: startDate)
        return (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
    }

    /// Duration in whole minutes (rounded down).
    var durationMinutes: Int {
        max(Int(endDate.timeIntervalSince(startDate) / 60), 0)
    }
}
