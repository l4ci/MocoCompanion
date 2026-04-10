import Foundation
import os

/// Owns all yesterday-checking logic: polling the API for employment/hours comparison
/// and local rechecking when yesterday activities change. Consolidates what was previously
/// split across YesterdayCheckManager, SessionManager.recheckYesterdayWarning, and AppState.
@Observable
@MainActor
final class YesterdayService: PollingMonitor {
    private let logger = Logger(category: "YesterdayService")

    // MARK: - PollingMonitor

    let monitorName = "YesterdayCheck"
    let pollInterval: Duration = .seconds(600) // 10 minutes

    // MARK: - Observable State

    /// The current yesterday warning, if any. Observed by views.
    var warning: YesterdayWarning?

    // MARK: - Configuration

    /// Threshold ratio (booked/expected) below which a warning is shown.
    static let threshold = 0.85

    // MARK: - Dependencies

    private let settings: SettingsStore
    private let clientFactory: () -> (any YesterdayAPI)?
    private let userIdProvider: () -> Int?

    init(
        settings: SettingsStore,
        clientFactory: @escaping () -> (any YesterdayAPI)?,
        userIdProvider: @escaping () -> Int? = { nil }
    ) {
        self.settings = settings
        self.clientFactory = clientFactory
        self.userIdProvider = userIdProvider
    }

    var isActive: Bool { settings.isConfigured }

    // MARK: - API-based check (called by MonitorEngine)

    func check() async -> [MonitorAlert] {
        guard let client = clientFactory() else { return [] }
        guard let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) else { return [] }

        let yesterdayStr = DateUtilities.dateString(yesterday)
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: yesterday)

        // Skip weekends
        guard weekday >= 2 && weekday <= 6 else { return [] }

        let patternIndex = weekday - 2 // Mon=0, Tue=1, ..., Fri=4

        do {
            let employments = try await client.fetchEmployments(from: yesterdayStr)
            guard let employment = employments.first else { return [] }

            let expectedHours = employment.pattern.expectedHours(weekdayIndex: patternIndex)
            guard expectedHours > 0 else { return [] }

            // Check for absences — filter to current user
            let schedules = try await client.fetchSchedules(from: yesterdayStr, to: yesterdayStr)
            let userId = userIdProvider()
            let userSchedules = schedules.filter { userId == nil || $0.user.id == userId }
            if userSchedules.contains(where: { $0.date == yesterdayStr }) {
                logger.info("Yesterday had an absence — skipping check")
                warning = nil
                return []
            }

            let activities = try await client.fetchActivities(from: yesterdayStr, to: yesterdayStr, userId: userId)
            let bookedHours = activities.reduce(0.0) { $0 + $1.hours }
            let ratio = bookedHours / expectedHours

            logger.info("Yesterday: \(String(format: "%.1f", bookedHours))h of \(String(format: "%.1f", expectedHours))h (\(String(format: "%.0f", ratio * 100))%)")

            if ratio < Self.threshold {
                let w = YesterdayWarning(bookedHours: bookedHours, expectedHours: expectedHours)
                warning = w
                return [MonitorAlert(
                    type: .yesterdayUnderBooked,
                    message: w.message,
                    dedupKey: "YesterdayCheck:underbooked",
                    dedupStrategy: .perDay
                )]
            } else {
                warning = nil
                return []
            }
        } catch {
            logger.error("Yesterday check failed: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Local recheck (called after activity edits/deletes)

    /// Recheck the warning using locally cached yesterday activities.
    /// Called directly after edits/deletes — no API call, instant feedback.
    func recheckLocally(yesterdayActivities: [ShadowEntry]) {
        guard let existing = warning else { return }
        let yesterdayHours = yesterdayActivities.reduce(0.0) { $0 + $1.hours }
        let ratio = yesterdayHours / existing.expectedHours
        if ratio >= Self.threshold {
            warning = nil
        } else {
            warning = YesterdayWarning(bookedHours: yesterdayHours, expectedHours: existing.expectedHours)
        }
    }
}

/// Warning data for yesterday's under-booking, displayed in the popup.
struct YesterdayWarning {
    let bookedHours: Double
    let expectedHours: Double

    var message: String {
        let booked = String(format: "%.1f", bookedHours)
        let expected = String(format: "%.1f", expectedHours)
        return String(localized: "yesterday.warningMessage \(booked) \(expected)")
    }
}
