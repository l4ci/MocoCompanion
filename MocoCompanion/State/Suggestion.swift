import Foundation

/// A suggestion produced by the rule engine when a suggest-mode rule matches an app usage block.
struct Suggestion: Identifiable, Sendable, Equatable {
    let id: String
    let ruleId: Int64
    let ruleName: String
    let startTime: String // HH:mm
    let durationSeconds: Int
    let projectId: Int
    let projectName: String
    let taskId: Int
    let taskName: String
    let description: String
    let appName: String
    /// Bundle id of the app block that triggered the rule. Propagated
    /// into the created ShadowEntry as origin metadata so the timeline
    /// can show it as linked to that recorded activity.
    let appBundleId: String
    /// When this suggestion was created from a calendar event, the
    /// event's `calendarItemIdentifier`. Propagated to the resulting
    /// ShadowEntry's `sourceCalendarEventId` when the suggestion is
    /// approved.
    var sourceCalendarEventId: String? = nil
}
