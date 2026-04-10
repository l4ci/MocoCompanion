import Foundation

enum RuleMode: String, Sendable, Codable, CaseIterable {
    case suggest
    case create
}

struct TrackingRule: Sendable, Identifiable, Equatable, Codable {
    var id: Int64?
    var name: String
    var appBundleId: String?
    var appNamePattern: String?
    var windowTitlePattern: String?
    var mode: RuleMode
    var projectId: Int
    var projectName: String
    var taskId: Int
    var taskName: String
    var description: String
    var enabled: Bool
    var createdAt: String
    var updatedAt: String
}
