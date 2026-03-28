import XCTest

final class FuzzyMatcherTests: XCTestCase {

    private func makeEntry(customer: String, project: String, task: String) -> SearchEntry {
        SearchEntry(projectId: 1, taskId: 1, customerName: customer, projectName: project, taskName: task)
    }

    func testExactSubstringMatch() {
        let entries = [makeEntry(customer: "Acme", project: "Marketing", task: "Social Media")]
        let results = FuzzyMatcher.search(query: "marketing", in: entries)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.entry.projectName, "Marketing")
    }

    func testPartialMatch() {
        let entries = [makeEntry(customer: "Acme", project: "Marketing Campaign", task: "Design")]
        let results = FuzzyMatcher.search(query: "mark", in: entries)
        XCTAssertEqual(results.count, 1)
    }

    func testNoMatch() {
        let entries = [makeEntry(customer: "Acme", project: "Marketing", task: "Design")]
        let results = FuzzyMatcher.search(query: "finance", in: entries)
        XCTAssertEqual(results.count, 0)
    }

    func testEmptyQuery() {
        let entries = [makeEntry(customer: "Acme", project: "Marketing", task: "Design")]
        let results = FuzzyMatcher.search(query: "", in: entries)
        XCTAssertEqual(results.count, 0)
    }

    func testWhitespaceQuery() {
        let entries = [makeEntry(customer: "Acme", project: "Marketing", task: "Design")]
        let results = FuzzyMatcher.search(query: "   ", in: entries)
        XCTAssertEqual(results.count, 0)
    }

    func testResultLimit() {
        let entries = (0..<20).map { makeEntry(customer: "C\($0)", project: "P\($0)", task: "T\($0)") }
        let results = FuzzyMatcher.search(query: "P", in: entries, limit: 5)
        XCTAssertEqual(results.count, 5)
    }

    func testRecencyBoost() {
        let entry1 = SearchEntry(projectId: 1, taskId: 1, customerName: "A", projectName: "Alpha", taskName: "T")
        let entry2 = SearchEntry(projectId: 2, taskId: 2, customerName: "B", projectName: "Also Alpha", taskName: "T")
        let results = FuzzyMatcher.search(query: "alpha", in: [entry1, entry2], recencyScores: [2: 1.0])
        // entry2 (projectId=2) should rank higher due to recency
        XCTAssertEqual(results.first?.entry.projectId, 2)
    }

    func testCaseInsensitive() {
        let entries = [makeEntry(customer: "Acme", project: "Marketing", task: "Design")]
        let upper = FuzzyMatcher.search(query: "MARKETING", in: entries)
        let lower = FuzzyMatcher.search(query: "marketing", in: entries)
        XCTAssertEqual(upper.count, lower.count)
    }
}
