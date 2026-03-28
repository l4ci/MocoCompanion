import XCTest

final class DateUtilitiesTests: XCTestCase {

    // MARK: - parseHours

    func testParseHoursDecimal() {
        XCTAssertEqual(DateUtilities.parseHours("1.5"), 1.5)
        XCTAssertEqual(DateUtilities.parseHours("0.25"), 0.25)
        XCTAssertEqual(DateUtilities.parseHours("2"), 2.0)
    }

    func testParseHoursCommaDecimal() {
        XCTAssertEqual(DateUtilities.parseHours("1,5"), 1.5)
    }

    func testParseHoursWithH() {
        XCTAssertEqual(DateUtilities.parseHours("1h"), 1.0)
        XCTAssertEqual(DateUtilities.parseHours("2h"), 2.0)
    }

    func testParseHoursWithM() {
        XCTAssertEqual(DateUtilities.parseHours("30m"), 0.5)
        XCTAssertEqual(DateUtilities.parseHours("90m"), 1.5)
        XCTAssertEqual(DateUtilities.parseHours("60m"), 1.0)
    }

    func testParseHoursWithHM() {
        XCTAssertEqual(DateUtilities.parseHours("1h 30m"), 1.5)
        XCTAssertEqual(DateUtilities.parseHours("1h30m"), 1.5)
        XCTAssertEqual(DateUtilities.parseHours("2h 15m"), 2.25)
    }

    func testParseHoursWithHAndMinutes() {
        let result = DateUtilities.parseHours("1h 4m")
        XCTAssertNotNil(result)
        XCTAssertEqual(result!, 1.0 + 4.0/60.0, accuracy: 0.001)
    }

    func testParseHoursEmpty() {
        XCTAssertNil(DateUtilities.parseHours(""))
        XCTAssertNil(DateUtilities.parseHours("   "))
    }

    func testParseHoursInvalid() {
        XCTAssertNil(DateUtilities.parseHours("abc"))
        XCTAssertNil(DateUtilities.parseHours("hello world"))
    }

    // MARK: - formatElapsedCompact

    func testFormatElapsedCompactSeconds() {
        XCTAssertEqual(DateUtilities.formatElapsedCompact(45), "45s")
    }

    func testFormatElapsedCompactMinutes() {
        XCTAssertEqual(DateUtilities.formatElapsedCompact(180), "3m")
    }

    func testFormatElapsedCompactHours() {
        XCTAssertEqual(DateUtilities.formatElapsedCompact(3780), "1h3m")
    }

    // MARK: - formatHoursCompact

    func testFormatHoursCompactZero() {
        XCTAssertEqual(DateUtilities.formatHoursCompact(0), "0m")
    }

    func testFormatHoursCompactMinutes() {
        XCTAssertEqual(DateUtilities.formatHoursCompact(0.75), "45m")
    }

    func testFormatHoursCompactHours() {
        XCTAssertEqual(DateUtilities.formatHoursCompact(2.5), "2h30m")
    }

    // MARK: - todayString / yesterdayString

    func testTodayStringFormat() {
        let today = DateUtilities.todayString()
        // Should be YYYY-MM-DD format
        XCTAssertTrue(today.contains("-"))
        XCTAssertEqual(today.count, 10)
    }

    func testYesterdayStringNotNil() {
        XCTAssertNotNil(DateUtilities.yesterdayString())
    }

    func testYesterdayIsDifferentFromToday() {
        XCTAssertNotEqual(DateUtilities.todayString(), DateUtilities.yesterdayString())
    }
}
