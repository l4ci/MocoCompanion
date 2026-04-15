import Testing
@testable import MocoCompanion

// MARK: - Helpers

/// Build an AppRecord at a given hour:minute with a duration in minutes.
private func record(
    hour: Int, minute: Int, durationMin: Int,
    bundleId: String = "com.test.app",
    appName: String = "TestApp",
    windowTitle: String? = nil
) -> AppRecord {
    let cal = Calendar.current
    let base = cal.startOfDay(for: Date.now)
    let timestamp = cal.date(bySettingHour: hour, minute: minute, second: 0, of: base)!
    return AppRecord(
        id: nil,
        timestamp: timestamp,
        appBundleId: bundleId,
        appName: appName,
        windowTitle: windowTitle,
        durationSeconds: TimeInterval(durationMin * 60)
    )
}

// MARK: - Tests

@Suite("TimeSlot Aggregation")
struct TimeSlotTests {

    @Test("Empty records produce no slots")
    func emptyInput() {
        let slots = TimeSlot.aggregate([])
        #expect(slots.isEmpty)
    }

    @Test("Single app filling one slot produces one time slot")
    func singleAppOneSlot() {
        // 10 minutes in the 09:00–09:30 window
        let records = [record(hour: 9, minute: 5, durationMin: 10)]
        let slots = TimeSlot.aggregate(records)
        #expect(slots.count == 1)
        let slot = slots[0]
        #expect(slot.startMinutes == 9 * 60) // 540
        #expect(slot.endMinutes == 9 * 60 + 30) // 570
        #expect(slot.dominantBundleId == "com.test.app")
        #expect(slot.dominantDurationSeconds == 600) // 10 min
        #expect(slot.contributingApps.isEmpty)
    }

    @Test("Record spanning slot boundary splits proportionally")
    func boundarySpan() {
        // Starts at 09:20, lasts 20 min → 09:20-09:40
        // 09:00 slot gets 10 min (09:20-09:30)
        // 09:30 slot gets 10 min (09:30-09:40)
        let records = [record(hour: 9, minute: 20, durationMin: 20)]
        let slots = TimeSlot.aggregate(records)
        #expect(slots.count == 2)

        let first = slots[0]
        #expect(first.startMinutes == 540)
        #expect(first.dominantDurationSeconds == 600) // 10 min

        let second = slots[1]
        #expect(second.startMinutes == 570)
        #expect(second.dominantDurationSeconds == 600) // 10 min
    }

    @Test("Slot omitted when no app reaches 5 minutes")
    func belowThreshold() {
        // Only 4 minutes of usage
        let records = [record(hour: 9, minute: 0, durationMin: 4)]
        let slots = TimeSlot.aggregate(records)
        #expect(slots.isEmpty)
    }

    @Test("Dominant app wins when two apps compete")
    func dominantSelection() {
        let records = [
            record(hour: 9, minute: 0, durationMin: 15, bundleId: "com.a", appName: "AppA"),
            record(hour: 9, minute: 15, durationMin: 10, bundleId: "com.b", appName: "AppB"),
        ]
        let slots = TimeSlot.aggregate(records)
        #expect(slots.count == 1)
        #expect(slots[0].dominantBundleId == "com.a")
        #expect(slots[0].dominantAppName == "AppA")
        #expect(slots[0].dominantDurationSeconds == 15 * 60)
    }

    @Test("Contributing apps included when >= 5 min")
    func contributingAppsThreshold() {
        let records = [
            record(hour: 9, minute: 0, durationMin: 15, bundleId: "com.a", appName: "AppA"),
            record(hour: 9, minute: 15, durationMin: 8, bundleId: "com.b", appName: "AppB"),
            record(hour: 9, minute: 23, durationMin: 3, bundleId: "com.c", appName: "AppC"),
        ]
        let slots = TimeSlot.aggregate(records)
        #expect(slots.count == 1)
        #expect(slots[0].dominantBundleId == "com.a")
        // AppB has 8 min → included as contributing
        #expect(slots[0].contributingApps.count == 1)
        #expect(slots[0].contributingApps[0].bundleId == "com.b")
        // AppC has 3 min → excluded
    }

    @Test("Contributing apps below 5 min excluded")
    func contributingBelowThreshold() {
        let records = [
            record(hour: 9, minute: 0, durationMin: 20, bundleId: "com.a", appName: "AppA"),
            record(hour: 9, minute: 20, durationMin: 4, bundleId: "com.b", appName: "AppB"),
        ]
        let slots = TimeSlot.aggregate(records)
        #expect(slots.count == 1)
        #expect(slots[0].contributingApps.isEmpty)
    }

    @Test("Dominant window title is the one with most seconds")
    func windowTitleSelection() {
        let records = [
            record(hour: 9, minute: 0, durationMin: 3, windowTitle: "Page A"),
            record(hour: 9, minute: 3, durationMin: 7, windowTitle: "Page B"),
        ]
        let slots = TimeSlot.aggregate(records)
        #expect(slots.count == 1)
        #expect(slots[0].dominantWindowTitle == "Page B")
    }

    @Test("Nil window titles are ignored")
    func nilWindowTitle() {
        let records = [
            record(hour: 9, minute: 0, durationMin: 5, windowTitle: nil),
            record(hour: 9, minute: 5, durationMin: 5, windowTitle: "Title"),
        ]
        let slots = TimeSlot.aggregate(records)
        #expect(slots.count == 1)
        #expect(slots[0].dominantWindowTitle == "Title")
    }

    @Test("Multiple slots across the day")
    func multipleSlots() {
        let records = [
            record(hour: 9, minute: 0, durationMin: 10),
            record(hour: 14, minute: 0, durationMin: 15),
        ]
        let slots = TimeSlot.aggregate(records)
        #expect(slots.count == 2)
        #expect(slots[0].startMinutes == 9 * 60)
        #expect(slots[1].startMinutes == 14 * 60)
    }

    @Test("Slot start minutes are always multiples of 30")
    func slotAlignment() {
        let records = [
            record(hour: 9, minute: 17, durationMin: 10),
        ]
        let slots = TimeSlot.aggregate(records)
        #expect(slots.count == 1)
        #expect(slots[0].startMinutes % 30 == 0)
    }

    @Test("View-ready labels are formatted correctly")
    func labelFormatting() {
        let records = [record(hour: 9, minute: 0, durationMin: 10)]
        let slots = TimeSlot.aggregate(records)
        #expect(slots[0].startTimeLabel == "09:00")
        #expect(slots[0].endTimeLabel == "09:30")
        #expect(slots[0].dominantDurationLabel == "10m")
    }

    @Test("Same app across multiple records accumulates in one slot")
    func sameAppAccumulates() {
        let records = [
            record(hour: 9, minute: 0, durationMin: 3),
            record(hour: 9, minute: 5, durationMin: 3),
            record(hour: 9, minute: 10, durationMin: 3),
        ]
        let slots = TimeSlot.aggregate(records)
        #expect(slots.count == 1)
        #expect(slots[0].dominantDurationSeconds == 9 * 60) // 9 min total
    }
}
