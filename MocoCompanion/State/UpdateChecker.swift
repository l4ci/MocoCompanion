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

            if isNewerVersion(remote: remoteVersion, current: currentVersion) {
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

    private func isNewerVersion(remote: String, current: String) -> Bool {
        let remoteParts = remote.split(separator: ".").compactMap { Int($0) }
        let currentParts = current.split(separator: ".").compactMap { Int($0) }
        let count = max(remoteParts.count, currentParts.count)
        for i in 0..<count {
            let r = i < remoteParts.count ? remoteParts[i] : 0
            let c = i < currentParts.count ? currentParts[i] : 0
            if r != c { return r > c }
        }
        return false
    }
}
