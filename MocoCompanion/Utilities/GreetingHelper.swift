import Foundation

/// Computes time-of-day-aware greeting text.
/// Extracted from PanelContentView for testability.
enum GreetingHelper {
    /// Generate a greeting for the given hour and name.
    /// - Parameters:
    ///   - hour: Hour of the day (0-23)
    ///   - name: User's first name (fallback: "Moco")
    /// - Returns: Greeting string like "Guten Morgen, Volker"
    static func greeting(hour: Int, name: String) -> String {
        let salutation: String
        if hour < 11 {
            salutation = "Guten Morgen"
        } else if hour < 14 {
            salutation = "Mahlzeit"
        } else if hour < 18 {
            salutation = "Hallo"
        } else {
            salutation = "Guten Abend"
        }
        return "\(salutation), \(name)"
    }

    /// Generate a greeting using the current time and user profile.
    static func currentGreeting(name: String?) -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        return greeting(hour: hour, name: name ?? "Moco")
    }
}
