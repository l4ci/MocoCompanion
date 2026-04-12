import SwiftUI

// MARK: - Absence Visual Style

/// Resolves icon, color, and detail text for different absence types.
/// Matches against German Moco assignment names (Urlaub, Feiertag, Krankheit, etc.).
enum AbsenceStyle {
    struct Info {
        let icon: String
        let color: Color

        /// Returns an optional detail line (half-day indicator or comment).
        func detail(schedule: MocoSchedule) -> String? {
            if schedule.am && !schedule.pm {
                return String(localized: "absence.morning")
            } else if !schedule.am && schedule.pm {
                return String(localized: "absence.afternoon")
            }
            return schedule.comment?.isEmpty == false ? schedule.comment : nil
        }
    }

    static func resolve(_ schedule: MocoSchedule) -> Info {
        let name = schedule.assignment.name.lowercased()

        // Sick day
        if name.contains("krank") || name.contains("sick") {
            return Info(icon: "heart.circle", color: .red)
        }

        // Public holiday
        if name.contains("feier") || name.contains("holiday") {
            return Info(icon: "star.circle", color: .purple)
        }

        // Vacation / leave
        if name.contains("urlaub") || name.contains("vacation") || name.contains("ferien") {
            return Info(icon: "airplane.circle", color: .cyan)
        }

        // Compensation / overtime
        if name.contains("ausgleich") || name.contains("comp") || name.contains("überstunden") {
            return Info(icon: "clock.arrow.circlepath", color: .green)
        }

        // Training / education
        if name.contains("bildung") || name.contains("training") || name.contains("weiterbildung") {
            return Info(icon: "book.circle", color: .blue)
        }

        // Fallback — generic absence
        return Info(icon: "calendar.circle", color: .orange)
    }
}
