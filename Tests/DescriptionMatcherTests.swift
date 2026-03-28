import Testing
import Foundation

@Suite("DescriptionMatcher")
struct DescriptionMatcherTests {

    private typealias Entry = DescriptionStore.Entry

    // MARK: - Suggest

    @Test("Suggest returns prefix match")
    func suggestPrefixMatch() {
        let entries = [Entry(text: "Meeting with client", count: 5), Entry(text: "Development", count: 3)]
        let result = DescriptionMatcher.suggest(for: "Meet", entries: entries)
        #expect(result == "Meeting with client")
    }

    @Test("Suggest is case-insensitive")
    func suggestCaseInsensitive() {
        let entries = [Entry(text: "Development", count: 3)]
        let result = DescriptionMatcher.suggest(for: "dev", entries: entries)
        #expect(result == "Development")
    }

    @Test("Suggest returns nil for exact match")
    func suggestExactMatch() {
        let entries = [Entry(text: "Dev", count: 3)]
        let result = DescriptionMatcher.suggest(for: "Dev", entries: entries)
        #expect(result == nil) // don't suggest what's already typed
    }

    @Test("Suggest returns nil for short input")
    func suggestShortInput() {
        let entries = [Entry(text: "Development", count: 3)]
        #expect(DescriptionMatcher.suggest(for: "D", entries: entries) == nil)
        #expect(DescriptionMatcher.suggest(for: "", entries: entries) == nil)
    }

    @Test("Suggest returns most-used match first")
    func suggestMostUsed() {
        let entries = [
            Entry(text: "Meeting prep", count: 10),
            Entry(text: "Meeting notes", count: 2),
        ]
        let result = DescriptionMatcher.suggest(for: "Meet", entries: entries)
        #expect(result == "Meeting prep") // higher count comes first
    }

    @Test("Suggest returns nil when no match")
    func suggestNoMatch() {
        let entries = [Entry(text: "Development", count: 3)]
        #expect(DescriptionMatcher.suggest(for: "xyz", entries: entries) == nil)
    }

    // MARK: - Record

    @Test("Record adds new entry")
    func recordNew() {
        let result = DescriptionMatcher.record("New task", into: [])
        #expect(result?.count == 1)
        #expect(result?.first?.text == "New task")
        #expect(result?.first?.count == 1)
    }

    @Test("Record increments existing entry count")
    func recordIncrement() {
        let existing = [Entry(text: "Existing task", count: 3)]
        let result = DescriptionMatcher.record("existing task", into: existing)
        #expect(result?.count == 1) // still one entry
        #expect(result?.first?.count == 4) // incremented
    }

    @Test("Record strips tags")
    func recordStripsTags() {
        let result = DescriptionMatcher.record("Working on #TICKET-123 feature", into: [])
        #expect(result?.first?.text == "Working on feature")
    }

    @Test("Record ignores short descriptions")
    func recordIgnoresShort() {
        #expect(DescriptionMatcher.record("ab", into: []) == nil)
        #expect(DescriptionMatcher.record("", into: []) == nil)
        #expect(DescriptionMatcher.record("  ", into: []) == nil)
    }

    @Test("Record caps at max entries")
    func recordCaps() {
        var entries = (1...10).map { Entry(text: "Entry \($0)", count: 10 - $0) }
        let result = DescriptionMatcher.record("New entry", into: entries, maxEntries: 10)
        #expect(result?.count == 10) // capped at 10, not 11
    }

    @Test("Record sorts by count descending")
    func recordSorts() {
        let entries = [
            Entry(text: "Low usage", count: 1),
            Entry(text: "High usage", count: 10),
        ]
        let result = DescriptionMatcher.record("Medium usage", into: entries)!
        #expect(result[0].text == "High usage")
        #expect(result[1].text == "Low usage")
        #expect(result[2].text == "Medium usage")
    }
}
