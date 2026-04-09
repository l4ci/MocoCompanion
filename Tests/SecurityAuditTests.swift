import Testing
import Foundation
@testable import MocoCompanion

/// Automated security audit tests covering:
/// - R016: No API tokens in logs or debug output
/// - R017: No secrets in git-tracked source files
/// - R018: Correct Keychain access controls
@Suite("Security Audit")
struct SecurityAuditTests {

    // MARK: - Helpers

    /// Project root derived from this file's location (Tests/SecurityAuditTests.swift → project root).
    private static let projectRoot: URL = {
        let testsDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        return testsDir.deletingLastPathComponent()
    }()

    private static let sourceDir: URL = projectRoot.appendingPathComponent("MocoCompanion")

    /// Recursively enumerate all `.swift` files under a directory.
    private static func swiftFiles(in directory: URL) -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var files: [URL] = []
        for case let url as URL in enumerator {
            if url.pathExtension == "swift" {
                files.append(url)
            }
        }
        return files
    }

    /// Read file contents, returning nil on failure.
    private static func contents(of url: URL) -> String? {
        try? String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - R016: No Tokens in Logs

    @Test("R016a: No raw print/NSLog/debugPrint/dump calls in source")
    func noRawPrintStatements() throws {
        let files = Self.swiftFiles(in: Self.sourceDir)
        #expect(!files.isEmpty, "Should find Swift source files")

        // Patterns that indicate uncontrolled debug output.
        // Match function calls, not comments or string literals containing the word.
        let forbiddenPatterns = [
            #"(?m)^\s*print\("#,
            #"(?m)^\s*NSLog\("#,
            #"(?m)^\s*debugPrint\("#,
            #"(?m)^\s*dump\("#,
        ]

        var violations: [String] = []
        for file in files {
            guard let content = Self.contents(of: file) else { continue }
            let filename = file.lastPathComponent
            for pattern in forbiddenPatterns {
                if let regex = try? NSRegularExpression(pattern: pattern),
                   regex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)) != nil {
                    violations.append("\(filename) contains forbidden pattern: \(pattern)")
                }
            }
        }

        #expect(violations.isEmpty, "Found raw debug output calls: \(violations.joined(separator: "; "))")
    }

    @Test("R016b: No logger calls interpolating apiKey")
    func noLoggerApiKeyInterpolation() throws {
        let files = Self.swiftFiles(in: Self.sourceDir)
        #expect(!files.isEmpty)

        // Match logger.<anything> that references apiKey in interpolation
        let pattern = #"logger\.\w+\(.*apiKey"#
        let regex = try NSRegularExpression(pattern: pattern)

        var violations: [String] = []
        for file in files {
            guard let content = Self.contents(of: file) else { continue }
            if regex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)) != nil {
                violations.append(file.lastPathComponent)
            }
        }

        #expect(violations.isEmpty, "Logger calls interpolate apiKey in: \(violations.joined(separator: ", "))")
    }

    @Test("R016c: MocoClient has CustomDebugStringConvertible that redacts API key")
    func debugDescriptionRedactsApiKey() throws {
        // Source-level verification: MocoClient.swift must contain a debugDescription
        // that includes [REDACTED] and does not expose the apiKey field.
        let mocoClientFile = Self.sourceDir
            .appendingPathComponent("API")
            .appendingPathComponent("MocoClient.swift")
        let content = try #require(Self.contents(of: mocoClientFile), "Could not read MocoClient.swift")

        #expect(content.contains("CustomDebugStringConvertible"),
                "MocoClient should conform to CustomDebugStringConvertible")
        #expect(content.contains("[REDACTED]"),
                "debugDescription should use [REDACTED] for the API key")
        // Verify the debugDescription interpolation does NOT include apiKey raw value
        // The pattern should be something like "apiKey: [REDACTED]" not "apiKey: \(apiKey)"
        let debugDescLines = content.components(separatedBy: .newlines).filter {
            $0.contains("debugDescription")
        }
        let exposesKey = debugDescLines.contains { $0.contains("\\(apiKey)") }
        #expect(!exposesKey, "debugDescription must NOT interpolate the raw apiKey value")
    }

    // MARK: - R017: No Secrets in Git-Tracked Files

    @Test("R017a: .gitignore contains .env pattern")
    func gitignoreContainsEnvPattern() throws {
        let gitignoreURL = Self.projectRoot.appendingPathComponent(".gitignore")
        let content = try #require(Self.contents(of: gitignoreURL), "Could not read .gitignore")

        let hasEnvPattern = content.components(separatedBy: .newlines).contains { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed == ".env" || trimmed == ".env.*" || trimmed == ".env*"
        }
        #expect(hasEnvPattern, ".gitignore should contain a .env exclusion pattern")
    }

    @Test("R017b: No hardcoded API key patterns in source files")
    func noHardcodedApiKeys() throws {
        let files = Self.swiftFiles(in: Self.sourceDir)
        #expect(!files.isEmpty)

        // Match 32-char hex strings that look like API keys (in string literals)
        let pattern = #""[0-9a-fA-F]{32}""#
        let regex = try NSRegularExpression(pattern: pattern)

        var violations: [String] = []
        for file in files {
            guard let content = Self.contents(of: file) else { continue }
            if regex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)) != nil {
                violations.append(file.lastPathComponent)
            }
        }

        #expect(violations.isEmpty, "Hardcoded API key pattern found in: \(violations.joined(separator: ", "))")
    }

    // MARK: - R018: Keychain Access Controls

    @Test("R018a: KeychainHelper uses kSecAttrAccessibleWhenUnlocked")
    func keychainUsesCorrectAccessibility() throws {
        let keychainFile = Self.sourceDir
            .appendingPathComponent("Utilities")
            .appendingPathComponent("KeychainHelper.swift")
        let content = try #require(Self.contents(of: keychainFile), "Could not read KeychainHelper.swift")

        #expect(content.contains("kSecAttrAccessibleWhenUnlocked"),
                "KeychainHelper should use kSecAttrAccessibleWhenUnlocked")
    }

    @Test("R018b: KeychainHelper does NOT use kSecAttrAccessibleAlways")
    func keychainDoesNotUseAlwaysAccessible() throws {
        let keychainFile = Self.sourceDir
            .appendingPathComponent("Utilities")
            .appendingPathComponent("KeychainHelper.swift")
        let content = try #require(Self.contents(of: keychainFile), "Could not read KeychainHelper.swift")

        #expect(!content.contains("kSecAttrAccessibleAlways"),
                "KeychainHelper must NOT use kSecAttrAccessibleAlways (insecure)")
    }

    @Test("R018c: KeychainHelper does NOT use kSecAttrSynchronizable")
    func keychainDoesNotSyncToICloud() throws {
        let keychainFile = Self.sourceDir
            .appendingPathComponent("Utilities")
            .appendingPathComponent("KeychainHelper.swift")
        let content = try #require(Self.contents(of: keychainFile), "Could not read KeychainHelper.swift")

        #expect(!content.contains("kSecAttrSynchronizable"),
                "KeychainHelper must NOT use kSecAttrSynchronizable (prevents iCloud sync of credentials)")
    }
}
