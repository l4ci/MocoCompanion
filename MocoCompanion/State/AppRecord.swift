import Foundation

/// A single record of which application was frontmost during a time window.
struct AppRecord: Sendable, Identifiable, Equatable {
    let id: Int64?
    let timestamp: Date
    let appBundleId: String
    let appName: String
    let windowTitle: String?
    let durationSeconds: TimeInterval
}
