import XCTest

final class TagExtractorTests: XCTestCase {

    func testExtractHashtag() {
        XCTAssertEqual(TagExtractor.extract(from: "Fix login #PRJ-456 edge case"), "PRJ-456")
    }

    func testExtractFirstHashtag() {
        XCTAssertEqual(TagExtractor.extract(from: "#FIRST then #SECOND"), "FIRST")
    }

    func testNoHashtag() {
        XCTAssertNil(TagExtractor.extract(from: "No tags here"))
    }

    func testEmptyString() {
        XCTAssertNil(TagExtractor.extract(from: ""))
    }

    func testStripTags() {
        let result = TagExtractor.stripTags(from: "Fix login #PRJ-456 edge case")
        XCTAssertEqual(result.trimmingCharacters(in: .whitespaces), "Fix login edge case")
    }

    func testStripMultipleTags() {
        let result = TagExtractor.stripTags(from: "#TAG1 work #TAG2 more")
        XCTAssertFalse(result.contains("#"))
    }
}
