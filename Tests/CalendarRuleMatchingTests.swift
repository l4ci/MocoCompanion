import Testing
import Foundation
@testable import MocoCompanion

/// Focused unit coverage for the two `Autotracker.atRuleMatches` overloads
/// added by the calendar-rule pipeline. These tests skip the full `evaluate`
/// flow and exercise the matcher in isolation — the happy-path evaluate test
/// lives in `AutotrackerTests.calendarRuleCreatesShadowEntryStampedWithCalendarEventId`.
@MainActor
struct CalendarRuleMatchingTests {

    // MARK: - .app vs .calendar gate

    @Test func appRuleDoesNotMatchCalendarEvent() {
        let rule = makeAppRule(
            name: "Safari",
            appBundleId: "com.apple.Safari"
        )
        let event = makeEvent(title: "Safari Team Sync")

        #expect(Autotracker._testRuleMatches(rule, event: event) == false)
    }

    @Test func calendarRuleDoesNotMatchAppBlock() {
        // A calendar-type rule should NOT fire against an app usage block
        // even when the app name happens to contain the rule's pattern.
        let rule = makeCalendarRule(
            name: "Standup",
            eventTitlePattern: "standup"
        )
        let block = makeAppBlock(
            bundleId: "com.apple.Standup",
            appName: "Standup"
        )

        #expect(
            Autotracker._testRuleMatches(rule, block: block, windowTitlesEnabled: false) == false
        )
    }

    // MARK: - .calendar substring matching

    @Test func calendarRuleMatchesEventTitleSubstring() {
        let rule = makeCalendarRule(
            name: "Standup",
            eventTitlePattern: "standup"
        )
        let event = makeEvent(title: "Engineering Standup")

        #expect(Autotracker._testRuleMatches(rule, event: event) == true)
    }

    @Test func calendarRuleMatchIsCaseInsensitive() {
        let rule = makeCalendarRule(
            name: "Standup",
            eventTitlePattern: "STANDUP"
        )
        let event = makeEvent(title: "weekly standup with team")

        #expect(Autotracker._testRuleMatches(rule, event: event) == true)
    }

    @Test func calendarRuleDoesNotMatchUnrelatedEventTitle() {
        let rule = makeCalendarRule(
            name: "Standup",
            eventTitlePattern: "standup"
        )
        let event = makeEvent(title: "Lunch with design team")

        #expect(Autotracker._testRuleMatches(rule, event: event) == false)
    }

    @Test func calendarRuleWithEmptyPatternMatchesNothing() {
        let rule = makeCalendarRule(
            name: "Bad rule",
            eventTitlePattern: ""
        )
        let event = makeEvent(title: "Any meeting")

        #expect(Autotracker._testRuleMatches(rule, event: event) == false)
    }

    // MARK: - Helpers

    private func makeAppRule(
        name: String,
        appBundleId: String
    ) -> TrackingRule {
        TrackingRule(
            id: 1,
            name: name,
            appBundleId: appBundleId,
            appNamePattern: nil,
            windowTitlePattern: nil,
            eventTitlePattern: nil,
            mode: .create,
            ruleType: .app,
            projectId: 1,
            projectName: "P",
            taskId: 1,
            taskName: "T",
            description: "",
            enabled: true,
            createdAt: "",
            updatedAt: ""
        )
    }

    private func makeCalendarRule(
        name: String,
        eventTitlePattern: String
    ) -> TrackingRule {
        TrackingRule(
            id: 2,
            name: name,
            appBundleId: nil,
            appNamePattern: nil,
            windowTitlePattern: nil,
            eventTitlePattern: eventTitlePattern,
            mode: .create,
            ruleType: .calendar,
            projectId: 1,
            projectName: "P",
            taskId: 1,
            taskName: "T",
            description: "",
            enabled: true,
            createdAt: "",
            updatedAt: ""
        )
    }

    private func makeEvent(title: String) -> CalendarEvent {
        let start = Date()
        return CalendarEvent(
            id: UUID().uuidString,
            calendarItemIdentifier: UUID().uuidString,
            title: title,
            location: nil,
            startDate: start,
            endDate: start.addingTimeInterval(3600),
            isAllDay: false,
            isAcceptedByUser: true,
            calendarColorHex: "#808080"
        )
    }

    private func makeAppBlock(bundleId: String, appName: String) -> AppUsageBlock {
        let start = Date()
        return AppUsageBlock(
            id: UUID().uuidString,
            appBundleId: bundleId,
            appName: appName,
            startTime: start,
            endTime: start.addingTimeInterval(3600),
            durationSeconds: 3600,
            recordCount: 1,
            contributingApps: [],
            windowTitle: nil
        )
    }
}
