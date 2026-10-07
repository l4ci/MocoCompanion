import Testing
import Foundation
@testable import MocoCompanion

@Suite("TimeRangeModel")
struct TimeRangeModelTests {

    @Test("editing start keeps duration and moves end")
    func startKeepsDuration() {
        var m = TimeRangeModel(start: 11 * 60 + 15, duration: 15)
        m.setStart(10 * 60)
        #expect(m.start == 600)
        #expect(m.duration == 15)
        #expect(m.end == 615)
    }

    @Test("editing start near midnight shrinks duration to fit the day")
    func startNearMidnight() {
        var m = TimeRangeModel(start: 600, duration: 120)
        m.setStart(23 * 60 + 30)
        #expect(m.start == 1410)
        #expect(m.end == 1440)
        #expect(m.duration == 30)
    }

    @Test("editing end recomputes duration")
    func endRecomputesDuration() {
        var m = TimeRangeModel(start: 600, duration: 15)
        m.setEnd(660)
        #expect(m.start == 600)
        #expect(m.duration == 60)
    }

    @Test("end before or at start clamps to minimum duration")
    func endBeforeStart() {
        var m = TimeRangeModel(start: 600, duration: 30)
        m.setEnd(540)
        #expect(m.duration == TimeRangeModel.minDuration)
        m.setEnd(600)
        #expect(m.duration == TimeRangeModel.minDuration)
        #expect(m.end >= m.start)
    }

    @Test("editing duration moves end")
    func durationMovesEnd() {
        var m = TimeRangeModel(start: 600, duration: 15)
        m.setDuration(90)
        #expect(m.start == 600)
        #expect(m.end == 690)
    }

    @Test("values clamp to day bounds")
    func dayBounds() {
        var m = TimeRangeModel(start: -30, duration: 0)
        #expect(m.start == 0)
        #expect(m.duration == 1)

        m = TimeRangeModel(start: 5000, duration: 5000)
        #expect(m.start == 1439)
        #expect(m.end == 1440)

        m = TimeRangeModel(start: 600, duration: 15)
        m.setEnd(5000)
        #expect(m.end == 1440)
        m.setDuration(99_999)
        #expect(m.end == 1440)
        m.setDuration(-5)
        #expect(m.duration == 1)
    }

    @Test("parses H:mm and HH:mm")
    func parsesTimes() {
        #expect(TimeRangeModel.parseTime("9:05") == 545)
        #expect(TimeRangeModel.parseTime("09:05") == 545)
        #expect(TimeRangeModel.parseTime(" 23:59 ") == 1439)
        #expect(TimeRangeModel.parseTime("0:00") == 0)
        #expect(TimeRangeModel.parseTime("24:00") == 1440)
    }

    @Test("invalid time input returns nil")
    func rejectsInvalidTimes() {
        for bad in ["", "abc", "9", "905", "9:5", "09:60", "25:00", "24:01", "-1:00", "1:2:3", ":30", "9:", "١٢:٣٠"] {
            #expect(TimeRangeModel.parseTime(bad) == nil, "\(bad)")
        }
    }

    @Test("parses durations")
    func parsesDurations() {
        #expect(TimeRangeModel.parseDuration("15") == 15)
        #expect(TimeRangeModel.parseDuration(" 90 ") == 90)
        #expect(TimeRangeModel.parseDuration("0") == nil)
        #expect(TimeRangeModel.parseDuration("-5") == nil)
        #expect(TimeRangeModel.parseDuration("1.5") == nil)
        #expect(TimeRangeModel.parseDuration("") == nil)
    }

    @Test("formats minutes as HH:mm")
    func formats() {
        #expect(TimeRangeModel.format(545) == "09:05")
        #expect(TimeRangeModel.format(1440) == "24:00")
        #expect(TimeRangeModel.format(-3) == "00:00")
    }
}
