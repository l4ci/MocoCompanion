import Testing

@Suite("FuzzyMatcher")
struct FuzzyMatcherTests {

    private func makeEntry(customer: String, project: String, task: String) -> SearchEntry {
        SearchEntry(projectId: 1, taskId: 1, customerName: customer, projectName: project, taskName: task)
    }

    @Test("Exact substring match returns result")
    func exactSubstringMatch() {
        let entries = [makeEntry(customer: "Acme", project: "Marketing", task: "Social Media")]
        let results = FuzzyMatcher.search(query: "marketing", in: entries)
        #expect(results.count == 1)
        #expect(results.first?.entry.projectName == "Marketing")
    }

    @Test("Partial match returns result")
    func partialMatch() {
        let entries = [makeEntry(customer: "Acme", project: "Marketing Campaign", task: "Design")]
        let results = FuzzyMatcher.search(query: "mark", in: entries)
        #expect(results.count == 1)
    }

    @Test("Non-matching query returns empty")
    func noMatch() {
        let entries = [makeEntry(customer: "Acme", project: "Marketing", task: "Design")]
        let results = FuzzyMatcher.search(query: "finance", in: entries)
        #expect(results.count == 0)
    }

    @Test("Empty query returns empty")
    func emptyQuery() {
        let entries = [makeEntry(customer: "Acme", project: "Marketing", task: "Design")]
        let results = FuzzyMatcher.search(query: "", in: entries)
        #expect(results.count == 0)
    }

    @Test("Whitespace query returns empty")
    func whitespaceQuery() {
        let entries = [makeEntry(customer: "Acme", project: "Marketing", task: "Design")]
        let results = FuzzyMatcher.search(query: "   ", in: entries)
        #expect(results.count == 0)
    }

    @Test("Result limit is respected")
    func resultLimit() {
        let entries = (0..<20).map { makeEntry(customer: "C\($0)", project: "P\($0)", task: "T\($0)") }
        let results = FuzzyMatcher.search(query: "P", in: entries, limit: 5)
        #expect(results.count == 5)
    }

    @Test("Recency boost ranks recent entries higher")
    func recencyBoost() {
        let entry1 = SearchEntry(projectId: 1, taskId: 1, customerName: "A", projectName: "Alpha", taskName: "T")
        let entry2 = SearchEntry(projectId: 2, taskId: 2, customerName: "B", projectName: "Also Alpha", taskName: "T")
        let results = FuzzyMatcher.search(query: "alpha", in: [entry1, entry2], recencyScores: [2: 1.0])
        #expect(results.first?.entry.projectId == 2)
    }

    @Test("Search is case-insensitive")
    func caseInsensitive() {
        let entries = [makeEntry(customer: "Acme", project: "Marketing", task: "Design")]
        let upper = FuzzyMatcher.search(query: "MARKETING", in: entries)
        let lower = FuzzyMatcher.search(query: "marketing", in: entries)
        #expect(upper.count == lower.count)
    }
}
