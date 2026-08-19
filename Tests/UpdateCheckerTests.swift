import Testing
@testable import MocoCompanion

@Suite("UpdateChecker")
struct UpdateCheckerTests {

    private typealias IsNewer = (String, String) -> Bool
    private let isNewer: IsNewer = { UpdateChecker.isNewerVersion(remote: $0, current: $1) }

    @Test("Newer patch/minor/major versions beat the current version")
    func newerBeatsCurrent() {
        #expect(isNewer("1.2.4", "1.2.3"))
        #expect(isNewer("1.3.0", "1.2.3"))
        #expect(isNewer("2.0.0", "1.9.9"))
    }

    @Test("Equal version is not newer")
    func equalIsNotNewer() {
        #expect(!isNewer("1.2.3", "1.2.3"))
        #expect(!isNewer("1.2", "1.2.0"))
    }

    @Test("Older version is not newer")
    func olderIsNotNewer() {
        #expect(!isNewer("1.2.2", "1.2.3"))
    }

    @Test("A leading 'v' prefix is stripped before comparing")
    func vPrefixStripped() {
        #expect(isNewer("v1.2.4", "1.2.3"))
        #expect(isNewer("1.2.4", "v1.2.3"))
        #expect(!isNewer("v1.2.3", "v1.2.3"))
    }

    @Test("A pre-release is older than the same numeric release version")
    func prereleaseIsOlderThanRelease() {
        #expect(isNewer("1.2.0", "1.2.0-beta1"))
        #expect(!isNewer("1.2.0-beta1", "1.2.0"))
    }

    @Test("Malformed version strings never crash and are never newer")
    func malformedInputReturnsFalse() {
        #expect(!isNewer("", ""))
        #expect(!isNewer("abc", "1.0.0"))
        #expect(!isNewer("1.0.0", "abc"))
        #expect(!isNewer("1.2.3.4.5", "1.0.0"))
        #expect(!isNewer("1.x.0", "1.0.0"))
        #expect(!isNewer("1e308", "1.0.0"))
    }

    @Test("Multi-digit components compare numerically, not lexicographically")
    func numericNotLexicographic() {
        #expect(isNewer("1.10.0", "1.9.0"))
        #expect(!isNewer("1.9.0", "1.10.0"))
    }
}
