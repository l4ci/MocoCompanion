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
}
