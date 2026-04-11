import EventKit
import Foundation
import SwiftUI
import os

/// Owns the app's EKEventStore and vends CalendarEvent snapshots
/// for a given date. Subscribes to EKEventStoreChanged while at
/// least one consumer is attached, so the Timeline window can
/// re-fetch without a polling loop.
///
/// Permission is requested lazily on first access — see
/// `requestAccessIfNeeded()`. On macOS 14+ we call
/// `requestFullAccessToEvents`; on older versions `requestAccess(to: .event)`.
@Observable @MainActor
final class CalendarService {
    private static let logger = Logger(category: "CalendarService")

    /// Current authorization state, refreshed after any request/toggle.
    private(set) var authorizationStatus: EKAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)

    /// List of the user's calendars, populated on first access after
    /// access is granted. Used by the Settings tab's calendar picker.
    private(set) var availableCalendars: [CalendarReference] = []

    /// Monotonically bumped whenever events may have changed (on
    /// EKEventStoreChanged notification). Views observe it to
    /// re-fetch without this service holding a per-date cache.
    private(set) var changeTick: Int = 0

    private let eventStore = EKEventStore()
    /// Must be nonisolated(unsafe) so deinit (which is nonisolated) can read it
    /// to remove the observer. Safe because the token is only written on the
    /// main actor and deinit is only reached after all strong references are gone.
    /// Pattern established by AppRecordStore — keep until Swift supports isolated deinit.
    // swiftlint:disable:next redundant_nonisolated_unsafe
    nonisolated(unsafe) private var changeObserver: NSObjectProtocol?

    // MARK: - Permission

    /// Triggers the system permission prompt if status is .notDetermined.
    /// Refreshes `authorizationStatus` on completion. Safe to call repeatedly.
    @discardableResult
    func requestAccessIfNeeded() async -> EKAuthorizationStatus {
        let current = EKEventStore.authorizationStatus(for: .event)
        if current != .notDetermined {
            authorizationStatus = current
            return current
        }
        do {
            if #available(macOS 14.0, *) {
                _ = try await eventStore.requestFullAccessToEvents()
            } else {
                _ = try await eventStore.requestAccess(to: .event)
            }
        } catch {
            Self.logger.error("Calendar access request failed: \(error.localizedDescription)")
        }
        let after = EKEventStore.authorizationStatus(for: .event)
        authorizationStatus = after
        return after
    }

    /// Returns true only for the statuses that allow read access.
    var hasReadAccess: Bool {
        if #available(macOS 14.0, *) {
            return authorizationStatus == .fullAccess
        } else {
            return authorizationStatus == .authorized
        }
    }

    // MARK: - Calendars

    /// Populates `availableCalendars` from EKEventStore. Returns
    /// empty if no access. Call after `requestAccessIfNeeded`.
    func refreshAvailableCalendars() {
        guard hasReadAccess else {
            availableCalendars = []
            return
        }
        availableCalendars = eventStore.calendars(for: .event).map { cal in
            CalendarReference(
                id: cal.calendarIdentifier,
                title: cal.title,
                sourceTitle: cal.source.title,
                colorHex: Self.hexString(from: cal.cgColor)
            )
        }
        .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    // MARK: - Fetch

    /// Fetch all events for the day containing `date` from the selected
    /// calendar. Returns [] if no permission, no calendar selected, or
    /// the calendar no longer exists. Filters out declined + cancelled;
    /// tentative are included; all-day events are returned via their
    /// own flag on `CalendarEvent`.
    func fetchEvents(for date: Date, selectedCalendarId: String?) -> [CalendarEvent] {
        guard hasReadAccess, let calId = selectedCalendarId else { return [] }
        guard let calendar = eventStore.calendar(withIdentifier: calId) else { return [] }

        let startOfDay = Calendar.current.startOfDay(for: date)
        guard let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay) else { return [] }

        let predicate = eventStore.predicateForEvents(
            withStart: startOfDay,
            end: endOfDay,
            calendars: [calendar]
        )

        let rawEvents = eventStore.events(matching: predicate)

        return rawEvents.compactMap { ek -> CalendarEvent? in
            // Filter: exclude declined, cancelled.
            if Self.userDeclined(ek) { return nil }
            if ek.status == .canceled { return nil }
            return CalendarEvent(
                id: ek.eventIdentifier ?? UUID().uuidString,
                calendarItemIdentifier: ek.calendarItemIdentifier,
                title: ek.title ?? "",
                location: (ek.location?.isEmpty == false) ? ek.location : nil,
                startDate: ek.startDate,
                endDate: ek.endDate,
                isAllDay: ek.isAllDay,
                isAcceptedByUser: Self.userAccepted(ek),
                calendarColorHex: Self.hexString(from: ek.calendar.cgColor)
            )
        }
    }

    // MARK: - Change observation

    /// Start listening for EKEventStoreChanged. Idempotent. Bumps
    /// `changeTick` on each notification so SwiftUI observers
    /// re-fetch.
    func startObservingChanges() {
        guard changeObserver == nil else { return }
        changeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: eventStore,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.changeTick += 1
                Self.logger.debug("Calendar change tick \(self?.changeTick ?? 0)")
            }
        }
    }

    func stopObservingChanges() {
        if let obs = changeObserver {
            NotificationCenter.default.removeObserver(obs)
            changeObserver = nil
        }
    }

    deinit {
        if let obs = changeObserver {
            NotificationCenter.default.removeObserver(obs)
        }
    }

    // MARK: - Helpers

    private static func userDeclined(_ event: EKEvent) -> Bool {
        guard let attendees = event.attendees else { return false }
        return attendees.contains { $0.isCurrentUser && $0.participantStatus == .declined }
    }

    private static func userAccepted(_ event: EKEvent) -> Bool {
        // Events without attendees = personal, always "accepted".
        guard let attendees = event.attendees, !attendees.isEmpty else { return true }
        return attendees.contains { $0.isCurrentUser && $0.participantStatus == .accepted }
    }

    private static func hexString(from cg: CGColor?) -> String {
        guard let cg, let comps = cg.components else { return "#808080" }
        let r = Int((comps[0] * 255).rounded())
        let g = Int((comps.count > 1 ? comps[1] * 255 : comps[0] * 255).rounded())
        let b = Int((comps.count > 2 ? comps[2] * 255 : comps[0] * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

/// Value-typed reference to a calendar, for the Settings picker.
struct CalendarReference: Identifiable, Hashable, Sendable {
    let id: String           // calendarIdentifier
    let title: String
    let sourceTitle: String  // "iCloud", "Google", etc.
    let colorHex: String
}
