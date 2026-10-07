import Testing
@testable import MocoCompanion

@Suite("ProjectPickerSelection")
struct ProjectPickerSelectionTests {

    private func entry(_ n: Int) -> SearchEntry {
        SearchEntry(projectId: n, taskId: n * 10, customerName: "C", projectName: "P\(n)", taskName: "T\(n)")
    }

    private var results: [SearchEntry] { [entry(1), entry(2), entry(3)] }

    @Test("step down moves to the next row")
    func stepDown() {
        #expect(ProjectPickerSelection.step(entry(1), in: results, by: 1)?.id == entry(2).id)
    }

    @Test("step up moves to the previous row")
    func stepUp() {
        #expect(ProjectPickerSelection.step(entry(3), in: results, by: -1)?.id == entry(2).id)
    }

    @Test("step clamps at both ends")
    func clamps() {
        #expect(ProjectPickerSelection.step(entry(3), in: results, by: 1)?.id == entry(3).id)
        #expect(ProjectPickerSelection.step(entry(1), in: results, by: -1)?.id == entry(1).id)
    }

    @Test("step without a selection picks the first row")
    func stepFromNil() {
        #expect(ProjectPickerSelection.step(nil, in: results, by: 1)?.id == entry(1).id)
        #expect(ProjectPickerSelection.step(nil, in: results, by: -1)?.id == entry(1).id)
    }

    @Test("step from a selection missing in results picks the first row")
    func stepFromStale() {
        #expect(ProjectPickerSelection.step(entry(9), in: results, by: 1)?.id == entry(1).id)
    }

    @Test("step in empty results yields nil")
    func stepEmpty() {
        #expect(ProjectPickerSelection.step(entry(1), in: [], by: 1) == nil)
    }

    @Test("query change selects the top result")
    func queryTop() {
        let sel = ProjectPickerSelection.afterQueryChange(
            query: "p", results: results, current: entry(3), clearsOnEmptyQuery: true)
        #expect(sel?.id == entry(1).id)
    }

    @Test("query change with no results clears the selection")
    func queryNoResults() {
        let sel = ProjectPickerSelection.afterQueryChange(
            query: "zzz", results: [], current: entry(3), clearsOnEmptyQuery: true)
        #expect(sel == nil)
    }

    @Test("empty query clears the selection when asked")
    func emptyClears() {
        let sel = ProjectPickerSelection.afterQueryChange(
            query: "", results: results, current: entry(2), clearsOnEmptyQuery: true)
        #expect(sel == nil)
    }

    @Test("empty query keeps the selection when asked")
    func emptyKeeps() {
        let sel = ProjectPickerSelection.afterQueryChange(
            query: "", results: results, current: entry(2), clearsOnEmptyQuery: false)
        #expect(sel?.id == entry(2).id)
    }
}
