// Dấu macOS — async update checker for GitHub Releases (UPDATE-01).
// NEVER downloads or replaces the app. Surfaces a menu notice + opens
// GitHub Releases / Homebrew guide. Silent on network/parse failure.
// Runs off the keyboard hot path: URLSession background queue only.

import AppKit
import Foundation

// MARK: - Semantic version

/// Parsed semantic version (major.minor.patch, optional "v" prefix).
struct SemanticVersion: Equatable, Comparable, Sendable {
    let major: Int
    let minor: Int
    let patch: Int

    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }
}

enum SemanticVersionParser {
    /// `"v0.2.0"`, `"0.2"`, `"2"` → version; malformed → `nil`.
    static func parse(_ string: String) -> SemanticVersion? {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        let noPrefix = (trimmed.hasPrefix("v") || trimmed.hasPrefix("V"))
            ? String(trimmed.dropFirst())
            : trimmed
        let parts = noPrefix.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 1, parts.count <= 3 else { return nil }
        let ints = parts.compactMap { Int($0) }
        guard ints.count == parts.count else { return nil }
        let major = ints[0]
        let minor = ints.count > 1 ? ints[1] : 0
        let patch = ints.count > 2 ? ints[2] : 0
        return SemanticVersion(major: major, minor: minor, patch: patch)
    }
}

// MARK: - GitHub releases/latest payload

/// Fields we read from the GitHub `/releases/latest` JSON.
struct DauReleaseInfo: Codable, Equatable, Sendable {
    let tagName: String
    let htmlURL: URL

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
    }
}

enum GitHubReleaseParser {
    static let latestReleaseURL =
        URL(string: "https://api.github.com/repos/hapo-nghialuu/dau/releases/latest")!

    /// Parse the `/releases/latest` JSON body. `nil` on malformed payload.
    static func parse(json: Data) -> DauReleaseInfo? {
        let decoder = JSONDecoder()
        return try? decoder.decode(DauReleaseInfo.self, from: json)
    }
}

// MARK: - Throttle (24h)

enum UpdateCheckKey {
    static let lastCheckedAt = "dau.update.lastCheckedAt"
}

enum UpdateCheckThrottle {
    /// Background checks at most once per 24h; manual checks bypass this.
    static let defaultInterval: TimeInterval = 24 * 60 * 60

    static func shouldCheck(
        now: Date,
        lastCheckedAt: Date?,
        interval: TimeInterval = defaultInterval
    ) -> Bool {
        guard let last = lastCheckedAt else { return true }
        return now.timeIntervalSince(last) >= interval
    }
}

// MARK: - Check state (UI mirror)

/// Update-check state surfaced to the menu/settings. Never touches typing path.
enum ReleaseCheckState: Equatable, Sendable {
    case none          // not checked this session / throttled skip
    case checking
    case upToDate
    case updateAvailable(version: String)
    case failed        // silent network / parse failure
}

struct ReleaseCheckResult: Equatable, Sendable {
    let state: ReleaseCheckState
    let release: DauReleaseInfo?
}

// MARK: - Checker

final class UpdateChecker {
    static let homebrewGuideURL =
        URL(string: "https://github.com/hapo-nghialuu/dau/blob/main/docs/release-macos.md")!

    private let session: URLSession
    private let defaults: UserDefaults
    /// Current installed marketing version (e.g. "0.1.0").
    let currentVersion: String

    init(
        session: URLSession = .shared,
        defaults: UserDefaults = .standard,
        currentVersion: String = UpdateChecker.bundleVersion
    ) {
        self.session = session
        self.defaults = defaults
        self.currentVersion = currentVersion
    }

    /// Bundle marketing version from Info.plist (`CFBundleShortVersionString`).
    static var bundleVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
    }

    /// Latest GitHub release, or `nil` on network/parse failure (silent).
    func fetchLatestRelease(completion: @escaping (DauReleaseInfo?) -> Void) {
        var request = URLRequest(url: GitHubReleaseParser.latestReleaseURL)
        request.timeoutInterval = 15
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        session.dataTask(with: request) { data, response, error in
            guard error == nil,
                  let http = response as? HTTPURLResponse,
                  http.statusCode == 200,
                  let data,
                  let release = GitHubReleaseParser.parse(json: data)
            else {
                completion(nil)
                return
            }
            completion(release)
        }.resume()
    }

    /// Background check honoring the 24h throttle. Never blocks the UI/keyboard path.
    /// Throttled → `.none` (state unchanged). The throttle is enforced on the
    /// *attempt*, so a network/parse failure still cools down for a full interval.
    func checkIfNeeded(completion: @escaping (ReleaseCheckResult) -> Void) {
        let now = Date()
        let last = defaults.object(forKey: UpdateCheckKey.lastCheckedAt) as? Date
        guard UpdateCheckThrottle.shouldCheck(now: now, lastCheckedAt: last) else {
            completion(ReleaseCheckResult(state: .none, release: nil))
            return
        }
        // Stamp before fetching: failed attempts are throttled too. Manual
        // checks (`checkNow`) never stamp, so they remain an explicit bypass.
        defaults.set(now, forKey: UpdateCheckKey.lastCheckedAt)
        performCheck(completion: completion)
    }

    /// Manual check — bypasses throttle, still silent on failure.
    func checkNow(completion: @escaping (ReleaseCheckResult) -> Void) {
        performCheck(completion: completion)
    }

    private func performCheck(completion: @escaping (ReleaseCheckResult) -> Void) {
        fetchLatestRelease { [currentVersion] release in
            let state: ReleaseCheckState
            if let release {
                if let latest = SemanticVersionParser.parse(release.tagName),
                   let current = SemanticVersionParser.parse(currentVersion),
                   latest > current {
                    state = .updateAvailable(version: release.tagName)
                } else {
                    state = .upToDate
                }
            } else {
                state = .failed
            }
            completion(ReleaseCheckResult(state: state, release: release))
        }
    }

    func openLatestReleasePage() {
        NSWorkspace.shared.open(GitHubReleaseParser.latestReleaseURL)
    }

    func openHomebrewGuide() {
        NSWorkspace.shared.open(Self.homebrewGuideURL)
    }
}
