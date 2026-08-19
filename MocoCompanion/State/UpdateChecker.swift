import Foundation
import os

/// Checks GitHub releases on app launch to detect newer versions.
/// Only checks once per launch — not on background polls.
actor UpdateChecker {
    private let logger = Logger(category: "UpdateChecker")

    struct Release: Sendable {
        let version: String
        let url: URL
    }

    private let repoOwner = "l4ci"
    private let repoName = "MocoCompanion"
    private let updateGuideURL = URL(string: "https://github.com/l4ci/MocoCompanion/blob/main/docs/updating.md")!

    /// Compare tag_name (stripped of "v" prefix) with current CFBundleShortVersionString.
    /// Returns Release if a newer version is available, nil if current or on error.
    func checkForUpdate() async -> Release? {
        guard let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String else {
            logger.warning("Could not read CFBundleShortVersionString")
            return nil
        }

        let urlString = "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest"
        guard let url = URL(string: urlString) else { return nil }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                logger.info("GitHub API returned non-200 response")
                return nil
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String else {
                logger.warning("Could not parse GitHub release response")
                return nil
            }

            let remoteVersion = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName

            if Self.isNewerVersion(remote: remoteVersion, current: currentVersion) {
                logger.info("Update available: \(remoteVersion) (current: \(currentVersion))")
                return Release(version: remoteVersion, url: updateGuideURL)
            } else {
                logger.info("App is up to date (\(currentVersion))")
                return nil
            }
        } catch {
            logger.error("Update check failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Parses a `MAJOR[.MINOR[.PATCH]]` version, with an optional leading
    /// `v`/`V` and an optional `-prerelease` suffix (e.g. `"v1.2.0-beta1"`).
    /// `nil` for anything that doesn't fit that shape — a non-numeric
    /// component, an empty string, or more than three numeric components.
    private struct ParsedVersion {
        let numeric: [Int]
        let isPrerelease: Bool

        init?(_ raw: String) {
            var stripped = raw.trimmingCharacters(in: .whitespaces)
            if stripped.hasPrefix("v") || stripped.hasPrefix("V") {
                stripped.removeFirst()
            }
            guard !stripped.isEmpty else { return nil }

            let dashIndex = stripped.firstIndex(of: "-")
            let numericPart = dashIndex.map { String(stripped[stripped.startIndex..<$0]) } ?? stripped
            isPrerelease = dashIndex != nil

            let parts = numericPart.split(separator: ".", omittingEmptySubsequences: false)
            guard !parts.isEmpty, parts.count <= 3 else { return nil }

            var values: [Int] = []
            for part in parts {
                guard let value = Int(part), value >= 0 else { return nil }
                values.append(value)
            }
            numeric = values
        }
    }

    /// Compares two version strings numerically (`"1.10.0" > "1.9.0"`), not
    /// lexicographically. A pre-release (`"1.2.0-beta1"`) is treated as
    /// older than the same numeric version without a suffix (`"1.2.0"`).
    /// Returns `false` — never crashes — when either string doesn't parse.
    static func isNewerVersion(remote: String, current: String) -> Bool {
        guard let remoteVersion = ParsedVersion(remote), let currentVersion = ParsedVersion(current) else {
            return false
        }

        let count = max(remoteVersion.numeric.count, currentVersion.numeric.count)
        for i in 0..<count {
            let r = i < remoteVersion.numeric.count ? remoteVersion.numeric[i] : 0
            let c = i < currentVersion.numeric.count ? currentVersion.numeric[i] : 0
            if r != c { return r > c }
        }

        if remoteVersion.isPrerelease != currentVersion.isPrerelease {
            // Same numeric version, different prerelease status: the release
            // (non-prerelease) side is newer.
            return !remoteVersion.isPrerelease
        }

        return false
    }
}
