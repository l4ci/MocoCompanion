import Foundation

/// Computes time-of-day-aware greeting text.
/// Extracted from PanelContentView for testability.
enum GreetingHelper {
    /// Generate a greeting for the given hour, weekday, name, and locale.
    /// - Parameters:
    ///   - hour: Hour of the day (0-23)
    ///   - weekday: Day of the week (1=Sun, 2=Mon, ..., 6=Fri, 7=Sat)
    ///   - name: User's first name (fallback: "Moco")
    ///   - locale: Locale for language selection (defaults to .current)
    /// - Returns: Greeting string like "Guten Morgen, Volker" or "Good morning, Volker"
    static func greeting(hour: Int, weekday: Int = 0, name: String, locale: Locale = .current) -> String {
        let isGerman = locale.language.languageCode?.identifier == "de"

        let salutation: String

        // Friday afternoon — earned it
        if weekday == 6 && hour >= 15 && hour < 18 {
            salutation = isGerman ? "Schönen Freitag" : "Happy Friday"
        }
        // Late night owl
        else if hour >= 22 || hour < 5 {
            salutation = isGerman ? "Nachtschicht" : "Night owl"
        }
        // Early bird
        else if hour >= 5 && hour < 7 {
            salutation = isGerman ? "Frühaufsteher" : "Early bird"
        }
        // Standard time-of-day
        else if hour < 11 {
            salutation = isGerman ? "Guten Morgen" : "Good morning"
        } else if hour < 14 {
            salutation = isGerman ? "Mahlzeit" : "Good afternoon"
        } else if hour < 18 {
            salutation = isGerman ? "Hallo" : "Hello"
        } else {
            salutation = isGerman ? "Guten Abend" : "Good evening"
        }

        return "\(salutation), \(name)"
    }

    /// Generate a greeting using the current time and user profile.
    static func currentGreeting(name: String?, locale: Locale = .current) -> String {
        let now = Date()
        let cal = Calendar.current
        let hour = cal.component(.hour, from: now)
        let weekday = cal.component(.weekday, from: now)
        return greeting(hour: hour, weekday: weekday, name: name ?? "Moco", locale: locale)
    }
}
