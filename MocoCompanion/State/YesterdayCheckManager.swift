import Foundation
import os

/// Monitors yesterday's booked hours against the employment model.
/// Runs as a PollingMonitor inside MonitorEngine — no standalone polling loop.
///
/// Check logic: fetch employment model + absences + activities for yesterday,
/// compare booked vs expected hours. If below 85%, emit a warning alert.
/// MonitorEngine handles dedup (perDay strategy) so the notification fires once per day.
@MainActor
final class YesterdayCheckManager: PollingMonitor {
    let monitorName = "YesterdayCheck"
    let pollInterval: Duration = .seconds(600) // 10 minutes

    private let logger = Logger(category: "YesterdayCheck")
    private let settings: SettingsStore
    private let clientFactory: () -> (any YesterdayAPI)?
    private let setWarning: (YesterdayWarning?) -> Void

    static let threshold = 0.85

    init(
        settings: SettingsStore,
        clientFactory: @escaping () -> (any YesterdayAPI)?,
        setWarning: @escaping (YesterdayWarning?) -> Void
    ) {
        self.settings = settings
        self.clientFactory = clientFactory
        self.setWarning = setWarning
    }

    var isActive: Bool { settings.isConfigured }

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

            // Check for absences
            let schedules = try await client.fetchSchedules(from: yesterdayStr, to: yesterdayStr)
            if schedules.contains(where: { $0.date == yesterdayStr }) {
                logger.info("Yesterday had an absence — skipping check")
                setWarning(nil)
                return []
            }

            let activities = try await client.fetchActivities(from: yesterdayStr, to: yesterdayStr)
            let bookedHours = activities.reduce(0.0) { $0 + $1.hours }
            let ratio = bookedHours / expectedHours

            logger.info("Yesterday: \(String(format: "%.1f", bookedHours))h of \(String(format: "%.1f", expectedHours))h (\(String(format: "%.0f", ratio * 100))%)")

            if ratio < Self.threshold {
                setWarning(YesterdayWarning(bookedHours: bookedHours, expectedHours: expectedHours))
                return [MonitorAlert(
                    type: .yesterdayUnderBooked,
                    message: String(format: "Yesterday: %.1fh of %.1fh booked", bookedHours, expectedHours),
                    dedupKey: "YesterdayCheck:underbooked",
                    dedupStrategy: .perDay
                )]
            } else {
                setWarning(nil)
                return []
            }
        } catch {
            logger.error("Yesterday check failed: \(error.localizedDescription)")
            return []
        }
    }
}

/// Warning data for yesterday's under-booking, displayed in the popup.
struct YesterdayWarning {
    let bookedHours: Double
    let expectedHours: Double

    var message: String {
        String(format: "Yesterday: %.1fh of %.1fh booked", bookedHours, expectedHours)
    }
}
