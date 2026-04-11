import Foundation

enum RuleMode: String, Sendable, Codable, CaseIterable {
    case suggest
    case create
}

enum RuleType: String, Sendable, Codable, CaseIterable {
    case app
    case calendar
}

struct TrackingRule: Sendable, Identifiable, Equatable, Codable {
    var id: Int64?
    var name: String
    var appBundleId: String?
    var appNamePattern: String?
    var windowTitlePattern: String?
    var eventTitlePattern: String?
    var mode: RuleMode
    var ruleType: RuleType
    var projectId: Int
    var projectName: String
    var taskId: Int
    var taskName: String
    var description: String
    var enabled: Bool
    var createdAt: String
    var updatedAt: String
}
