// Dấu macOS — update checker tests (UPDATE-01).
// Pure logic only: semver, GitHub JSON parse, 24h throttle, status mapping.

import XCTest

// MARK: - Semantic version

final class SemanticVersionTests: XCTestCase {
    func testParseFull() {
        XCTAssertEqual(
            SemanticVersionParser.parse("0.2.0"),
            SemanticVersion(major: 0, minor: 2, patch: 0)
        )
    }

    func testParseVPrefix() {
        XCTAssertEqual(
            SemanticVersionParser.parse("v1.3.7"),
            SemanticVersion(major: 1, minor: 3, patch: 7)
        )
    }

    func testParseShortVersions() {
        XCTAssertEqual(SemanticVersionParser.parse("0.2"), SemanticVersion(major: 0, minor: 2, patch: 0))
        XCTAssertEqual(SemanticVersionParser.parse("2"), SemanticVersion(major: 2, minor: 0, patch: 0))
    }

    func testParseWhitespaceTrimmed() {
        XCTAssertEqual(
            SemanticVersionParser.parse("  v0.1.0  "),
            SemanticVersion(major: 0, minor: 1, patch: 0)
        )
    }

    func testParseInvalidReturnsNil() {
        XCTAssertNil(SemanticVersionParser.parse(""))
        XCTAssertNil(SemanticVersionParser.parse("v"))
        XCTAssertNil(SemanticVersionParser.parse("1.2.3.4"))
        XCTAssertNil(SemanticVersionParser.parse("1.a.3"))
        XCTAssertNil(SemanticVersionParser.parse("abc"))
        XCTAssertNil(SemanticVersionParser.parse("1.2-beta"))
    }

    func testComparison() {
        XCTAssertLessThan(SemanticVersion(major: 0, minor: 1, patch: 9),
                          SemanticVersion(major: 0, minor: 2, patch: 0))
        XCTAssertLessThan(SemanticVersion(major: 0, minor: 2, patch: 0),
                          SemanticVersion(major: 0, minor: 2, patch: 1))
        XCTAssertLessThan(SemanticVersion(major: 1, minor: 0, patch: 0),
                          SemanticVersion(major: 2, minor: 0, patch: 0))
        XCTAssertEqual(SemanticVersion(major: 1, minor: 2, patch: 3),
                       SemanticVersion(major: 1, minor: 2, patch: 3))
        XCTAssertFalse(SemanticVersion(major: 1, minor: 2, patch: 3) <
                       SemanticVersion(major: 1, minor: 2, patch: 3))
    }
}

// MARK: - GitHub JSON parsing

final class GitHubReleaseParserTests: XCTestCase {
    func testParseValidRelease() throws {
        let json = """
        {"tag_name": "v0.2.0", "html_url": "https://github.com/hapo-nghialuu/dau/releases/tag/v0.2.0", "draft": false}
        """.data(using: .utf8)!
        let release = try XCTUnwrap(GitHubReleaseParser.parse(json: json))
        XCTAssertEqual(release.tagName, "v0.2.0")
        XCTAssertEqual(
            release.htmlURL.absoluteString,
            "https://github.com/hapo-nghialuu/dau/releases/tag/v0.2.0"
        )
    }

    func testParseMissingTagReturnsNil() {
        let json = #"{"html_url": "https://github.com/hapo-nghialuu/dau/releases"}"#
            .data(using: .utf8)!
        XCTAssertNil(GitHubReleaseParser.parse(json: json))
    }

    func testParseGarbageReturnsNil() {
        XCTAssertNil(GitHubReleaseParser.parse(json: Data("not json".utf8)))
        XCTAssertNil(GitHubReleaseParser.parse(json: Data()))
    }
}

// MARK: - 24h throttle

final class UpdateCheckThrottleTests: XCTestCase {
    func testShouldCheckWhenNeverChecked() {
        XCTAssertTrue(UpdateCheckThrottle.shouldCheck(now: Date(), lastCheckedAt: nil))
    }

    func testShouldCheckWhenOlderThanInterval() {
        let now = Date()
        let old = now.addingTimeInterval(-(UpdateCheckThrottle.defaultInterval + 60))
        XCTAssertTrue(UpdateCheckThrottle.shouldCheck(now: now, lastCheckedAt: old))
    }

    func testShouldNotCheckWithinInterval() {
        let now = Date()
        let recent = now.addingTimeInterval(-60)
        XCTAssertFalse(UpdateCheckThrottle.shouldCheck(now: now, lastCheckedAt: recent))
    }

    func testExactlyAtIntervalShouldCheck() {
        let now = Date()
        let boundary = now.addingTimeInterval(-UpdateCheckThrottle.defaultInterval)
        XCTAssertTrue(UpdateCheckThrottle.shouldCheck(now: now, lastCheckedAt: boundary))
    }
}

// MARK: - Throttle-on-attempt (network-level)

/// URLProtocol stub: returns canned data or an error without hitting the network.
private final class StubURLProtocol: URLProtocol {
    static var responseData: Data?
    static var error: Error?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        if let error = Self.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        if let data = Self.responseData {
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
        }
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class UpdateCheckerThrottleAttemptTests: XCTestCase {
    private var defaults: UserDefaults!
    private var session: URLSession!
    private var checker: UpdateChecker!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "dau.update.throttle-attempt")!
        defaults.removePersistentDomain(forName: "dau.update.throttle-attempt")
        StubURLProtocol.responseData = nil
        StubURLProtocol.error = nil
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        session = URLSession(configuration: config)
        checker = UpdateChecker(
            session: session,
            defaults: defaults,
            currentVersion: "0.1.0"
        )
    }

    override func tearDown() {
        defaults = nil
        session = nil
        checker = nil
        super.tearDown()
    }

    private func waitForResult(
        _ check: @escaping (@escaping (ReleaseCheckResult) -> Void) -> Void,
        timeout: TimeInterval = 5
    ) -> ReleaseCheckResult {
        let exp = expectation(description: "check completion")
        var captured: ReleaseCheckResult?
        check { result in
            captured = result
            exp.fulfill()
        }
        wait(for: [exp], timeout: timeout)
        return captured!
    }

    /// A failed automatic check must still cool down: it stamps `lastCheckedAt`,
    /// so the next `checkIfNeeded` is throttled to `.none` without a fetch.
    func testAutoCheckStampsOnNetworkFailure() {
        StubURLProtocol.error = URLError(.notConnectedToInternet)

        let first = waitForResult { self.checker.checkIfNeeded(completion: $0) }
        XCTAssertEqual(first.state, .failed)

        // A "newer" release would pass the network check, but the attempt-based
        // throttle must gate the next automatic run regardless.
        let release = """
        {"tag_name": "v9.9.9", "html_url": "https://github.com/hapo-nghialuu/dau/releases/tag/v9.9.9"}
        """.data(using: .utf8)!
        StubURLProtocol.error = nil
        StubURLProtocol.responseData = release

        let second = waitForResult { self.checker.checkIfNeeded(completion: $0) }
        XCTAssertEqual(second.state, .none)
        XCTAssertNil(second.release)
    }

    /// Manual check bypasses the throttle: after a forced failure it still hits
    /// the network on the next `checkNow`.
    func testManualCheckBypassesThrottle() {
        StubURLProtocol.error = URLError(.notConnectedToInternet)
        _ = waitForResult { self.checker.checkNow(completion: $0) }

        let release = """
        {"tag_name": "v0.2.0", "html_url": "https://github.com/hapo-nghialuutrung/dau/releases/tag/v0.2.0"}
        """.data(using: .utf8)!
        StubURLProtocol.error = nil
        StubURLProtocol.responseData = release

        let second = waitForResult { self.checker.checkNow(completion: $0) }
        XCTAssertEqual(second.state, .updateAvailable(version: "v0.2.0"))
    }
}

// MARK: - Status mapping

final class LaunchAtLoginStatusMappingTests: XCTestCase {
    func testKindMapping() {
        XCTAssertEqual(LaunchAtLoginStatusMapper.kind(from: .enabled), .enabled)
        XCTAssertEqual(LaunchAtLoginStatusMapper.kind(from: .notRegistered), .notRegistered)
        XCTAssertEqual(LaunchAtLoginStatusMapper.kind(from: .notFound), .notFound)
        XCTAssertEqual(LaunchAtLoginStatusMapper.kind(from: .requiresApproval), .requiresApproval)
    }

    func testStateMapping() {
        XCTAssertEqual(LaunchAtLoginStatusMapper.state(kind: .enabled), .enabled)
        XCTAssertEqual(LaunchAtLoginStatusMapper.state(kind: .notRegistered), .disabled)
        XCTAssertEqual(LaunchAtLoginStatusMapper.state(kind: .notFound), .notFound)
        XCTAssertEqual(LaunchAtLoginStatusMapper.state(kind: .requiresApproval), .requiresApproval)
        guard case .error = LaunchAtLoginStatusMapper.state(kind: .unknown) else {
            XCTFail("unknown kind must map to error")
            return
        }
    }

    func testLabelMapping() {
        XCTAssertEqual(LaunchAtLoginStatusMapper.label(kind: .enabled), "Đang bật")
        XCTAssertEqual(LaunchAtLoginStatusMapper.label(kind: .notRegistered), "Đang tắt")
        XCTAssertEqual(LaunchAtLoginStatusMapper.label(kind: .notFound), "Chưa có mục Login Items (cần app cài đúng bundle)")
        XCTAssertEqual(LaunchAtLoginStatusMapper.label(kind: .requiresApproval), "Chờ duyệt trong Cài đặt hệ thống")
    }

    func testStateIsEnabled() {
        XCTAssertTrue(LaunchAtLoginState.enabled.isEnabled)
        XCTAssertFalse(LaunchAtLoginState.disabled.isEnabled)
        XCTAssertFalse(LaunchAtLoginState.requiresApproval.isEnabled)
        XCTAssertFalse(LaunchAtLoginState.notFound.isEnabled)
        XCTAssertFalse(LaunchAtLoginState.error("x").isEnabled)
    }
}

// MARK: - AppState update notice

final class AppStateUpdateNoticeTests: XCTestCase {
    func testUpdateNoticeOnlyWhenAvailable() {
        let state = AppState(defaults: UserDefaults(suiteName: "dau.update.notice")!)
        state.releaseCheckState = .updateAvailable(version: "v0.2.0")
        XCTAssertTrue(state.updateAvailable)
        XCTAssertEqual(state.updateNotice, "Có bản mới v0.2.0 — xem trên GitHub")

        state.releaseCheckState = .none
        XCTAssertFalse(state.updateAvailable)
        XCTAssertNil(state.updateNotice)

        state.releaseCheckState = .failed
        XCTAssertFalse(state.updateAvailable)
        XCTAssertNil(state.updateNotice)
    }

    func testLaunchAtLoginStatusLabel() {
        let state = AppState(defaults: UserDefaults(suiteName: "dau.update.launch")!)
        state.launchAtLoginState = .enabled
        XCTAssertEqual(state.launchAtLoginStatusLabel, "Đang bật")
        state.launchAtLoginState = .disabled
        XCTAssertEqual(state.launchAtLoginStatusLabel, "Đang tắt")
        state.launchAtLoginState = .requiresApproval
        XCTAssertEqual(state.launchAtLoginStatusLabel, "Chờ duyệt trong Cài đặt hệ thống")
    }
}
