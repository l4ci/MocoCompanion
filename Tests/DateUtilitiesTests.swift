import Testing
@testable import MocoCompanion

@Suite("DateUtilities")
struct DateUtilitiesTests {

    // MARK: - parseHours

    @Test("parseHours handles decimal formats")
    func parseHoursDecimal() {
        #expect(DateUtilities.parseHours("1.5") == 1.5)
        #expect(DateUtilities.parseHours("0.25") == 0.25)
        #expect(DateUtilities.parseHours("2") == 2.0)
    }

    @Test("parseHours handles comma decimal")
    func parseHoursCommaDecimal() {
        #expect(DateUtilities.parseHours("1,5") == 1.5)
    }

    @Test("parseHours handles h suffix")
    func parseHoursWithH() {
        #expect(DateUtilities.parseHours("1h") == 1.0)
        #expect(DateUtilities.parseHours("2h") == 2.0)
    }

    @Test("parseHours handles m suffix")
    func parseHoursWithM() {
        #expect(DateUtilities.parseHours("30m") == 0.5)
        #expect(DateUtilities.parseHours("90m") == 1.5)
        #expect(DateUtilities.parseHours("60m") == 1.0)
    }

    @Test("parseHours handles h+m combined")
    func parseHoursWithHM() {
        #expect(DateUtilities.parseHours("1h 30m") == 1.5)
        #expect(DateUtilities.parseHours("1h30m") == 1.5)
        #expect(DateUtilities.parseHours("2h 15m") == 2.25)
    }

    @Test("parseHours handles h with small minutes")
    func parseHoursWithHAndMinutes() {
        let result = DateUtilities.parseHours("1h 4m")
        #expect(result != nil)
        let expected = 1.0 + 4.0 / 60.0
        #expect(abs(result! - expected) < 0.001)
    }

    @Test("parseHours returns nil for empty input")
    func parseHoursEmpty() {
        #expect(DateUtilities.parseHours("") == nil)
        #expect(DateUtilities.parseHours("   ") == nil)
    }

    @Test("parseHours returns nil for invalid input")
    func parseHoursInvalid() {
        #expect(DateUtilities.parseHours("abc") == nil)
        #expect(DateUtilities.parseHours("hello world") == nil)
    }

    // MARK: - formatElapsedCompact

    @Test("formatElapsedCompact shows seconds")
    func formatElapsedCompactSeconds() {
        #expect(DateUtilities.formatElapsedCompact(45) == "45s")
    }

    @Test("formatElapsedCompact shows minutes")
    func formatElapsedCompactMinutes() {
        #expect(DateUtilities.formatElapsedCompact(180) == "3m")
    }

    @Test("formatElapsedCompact shows hours and minutes")
    func formatElapsedCompactHours() {
        #expect(DateUtilities.formatElapsedCompact(3780) == "1h3m")
    }

    // MARK: - formatHoursCompact

    @Test("formatHoursCompact shows 0m for zero")
    func formatHoursCompactZero() {
        #expect(DateUtilities.formatHoursCompact(0) == "0m")
    }

    @Test("formatHoursCompact shows minutes for fractional hours")
    func formatHoursCompactMinutes() {
        #expect(DateUtilities.formatHoursCompact(0.75) == "45m")
    }

    @Test("formatHoursCompact shows hours and minutes")
    func formatHoursCompactHours() {
        #expect(DateUtilities.formatHoursCompact(2.5) == "2h30m")
    }

    // MARK: - todayString / yesterdayString

    @Test("todayString returns YYYY-MM-DD format")
    func todayStringFormat() {
        let today = DateUtilities.todayString()
        #expect(today.contains("-"))
        #expect(today.count == 10)
    }

    @Test("yesterdayString returns a value")
    func yesterdayStringNotNil() {
        #expect(DateUtilities.yesterdayString() != nil)
    }

    @Test("yesterdayString differs from todayString")
    func yesterdayIsDifferentFromToday() {
        #expect(DateUtilities.todayString() != DateUtilities.yesterdayString())
    }
}
