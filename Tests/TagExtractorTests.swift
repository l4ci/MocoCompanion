import Testing
@testable import MocoCompanion

@Suite("TagExtractor")
struct TagExtractorTests {

    @Test("extract finds hashtag in text")
    func extractHashtag() {
        #expect(TagExtractor.extract(from: "Fix login #PRJ-456 edge case") == "PRJ-456")
    }

    @Test("extract returns first hashtag when multiple exist")
    func extractFirstHashtag() {
        #expect(TagExtractor.extract(from: "#FIRST then #SECOND") == "FIRST")
    }

    @Test("extract returns nil when no hashtag")
    func noHashtag() {
        #expect(TagExtractor.extract(from: "No tags here") == nil)
    }

    @Test("extract returns nil for empty string")
    func emptyString() {
        #expect(TagExtractor.extract(from: "") == nil)
    }

    @Test("stripTags removes hashtag from text")
    func stripTags() {
        let result = TagExtractor.stripTags(from: "Fix login #PRJ-456 edge case")
        #expect(result.trimmingCharacters(in: .whitespaces) == "Fix login edge case")
    }

    @Test("stripTags removes multiple hashtags")
    func stripMultipleTags() {
        let result = TagExtractor.stripTags(from: "#TAG1 work #TAG2 more")
        #expect(!result.contains("#"))
    }
}
