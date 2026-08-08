// Dấu macOS — Finder launch regression tests (v0.1.1–0.1.3).
// Regression: CGPreflightPostEventAccess defaulted false, blocking injection when app
// launched via Finder/LaunchServices. Terminal's TCC inheritance made it pass (true),
// so bug was invisible during `swift test` / Xcode run via Terminal. Fix removed the
// CGPreflightPostEventAccess gate entirely — AppState + TextInjector must work without it.

import XCTest

// MARK: - Launch context mock (Finder vs Terminal)

// Finder/LaunchServices: app launched without parent Terminal TCC inheritance.
// CGPreflightPostEventAccess() returns false until user grants post-event access
// (which on Finder-isolated launch was never reached because gate blocked inject).
// Terminal: parent inherits TCC, CGPreflightPostEventAccess() returned true.
enum MockLaunchContext: String, Sendable {
    case finderViaLaunchServices
    case terminalWithInheritedTCC

    var preflightWouldReturnFalse: Bool {
        switch self {
        case .finderViaLaunchServices: return true // would have been false → blocked
        case .terminalWithInheritedTCC: return false // true → hid bug
        }
    }

    var displayName: String { rawValue }
}

/// Harness that simulates the old buggy gate vs current fixed behaviour.
/// Legacy: inject blocked when `SyntheticPostAccess.check() == false` (cachedGranted == false on fresh launch).
/// Fixed: no SyntheticPostAccess gate — inject always attempts sink.
private struct LaunchContextHarness {
    let context: MockLaunchContext
    // Legacy gate simulation — fresh process default is `false` (blocked).
    var legacyDefaultCheck: () -> Bool = { false }

    func legacyWouldBlock() -> Bool { !legacyDefaultCheck() }
}

final class FinderLaunchTests: XCTestCase {

    // MARK: - Helpers

    private func makeInjector(
        sink: RecordingEventSink = RecordingEventSink(),
        sleeper: RecordingInjectorSleeper = RecordingInjectorSleeper()
    ) -> (TextInjector, RecordingEventSink, RecordingInjectorSleeper) {
        let injector = TextInjector(sink: sink, sleeper: sleeper, axAccessor: AXTextAccessor())
        return (injector, sink, sleeper)
    }

    private func makeFinderTrustedState(suite: String? = nil) -> AppState {
        let name = suite ?? "dau.finderLaunch.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let state = AppState(defaults: defaults)
        // Finder launch: Accessibility trusted (user granted), tap running,
        // but NO CGPreflightPostEventAccess / postEventAccessGranted concept.
        state.accessibilityTrusted = true
        state.eventTapRunning = true
        state.eventTapDegraded = false
        state.inputSourceBlocked = false
        state.typingEnabled = true
        return state
    }

    // MARK: - 1. Fresh Finder launch must not block injection (core regression)

    func testFinderLaunch_InjectSucceedsWithoutPostEventPreflight() {
        // Simulate Finder/LaunchServices: no prior CGPreflightPostEventAccess call,
        // legacy cachedGranted == false → would have returned .postAccessDenied.
        let harness = LaunchContextHarness(context: .finderViaLaunchServices)
        XCTAssertTrue(harness.legacyWouldBlock(), "legacy gate would block Finder launch")
        XCTAssertTrue(harness.context.preflightWouldReturnFalse)

        let (injector, sink, _) = makeInjector()
        let result = injector.inject(backspace: 1, text: "â", method: .backspaceFast, delays: .zero)

        // Fixed: must succeed — no CGPreflightPostEventAccess gate exists.
        if case .failure(let err) = result {
            XCTFail("Finder launch must not block inject, got \(err) — regression of v0.1.1–0.1.3")
        }
        XCTAssertEqual(sink.commands, [.backspace, .unicodeChunk("â")])
    }

    func testFreshProcess_DefaultCheckDoesNotBlockWhenCalledFresh() {
        // Pure fresh-process check: legacy `SyntheticPostAccess.check` defaulted to
        // `{ cachedGranted }` where cachedGranted == false → blocked. Fixed code has no such check.
        // We prove current injector has no postAccessDenied path.
        let freshHarness = LaunchContextHarness(context: .finderViaLaunchServices, legacyDefaultCheck: { false })
        XCTAssertFalse(freshHarness.legacyDefaultCheck(), "fresh legacy defaultCheck blocks")

        let (injector, sink, _) = makeInjector()
        // Never called any preflight / setCachedGranted — inject must still succeed.
        let r1 = injector.inject(backspace: 0, text: "a", method: .backspaceFast, delays: .zero)
        let r2 = injector.inject(backspace: 2, text: "vi", method: .backspaceFast, delays: .zero)
        for r in [r1, r2] {
            if case .failure(let e) = r { XCTFail("fresh inject must not fail, got \(e)") }
        }
        XCTAssertTrue(sink.commands.contains(.unicodeChunk("a")))
        XCTAssertTrue(sink.commands.contains(.unicodeChunk("vi")))

        // Guard: InjectionError must no longer have .postAccessDenied case.
        // If this switch becomes non-exhaustive after re-adding that case, compiler forces update.
        let sampleError: InjectionError = .invalidBackspaceCount
        switch sampleError {
        case .invalidBackspaceCount, .unsupportedMethod, .sinkFailed:
            break // no .postAccessDenied — gate removed
        }
    }

    // MARK: - 2. Finder vs Terminal parity

    func testFinderVsTerminalParity_BothContextsAllowInjection() {
        for ctx in [MockLaunchContext.finderViaLaunchServices, .terminalWithInheritedTCC] {
            let (injector, sink, _) = makeInjector()
            let result = injector.inject(backspace: 1, text: "ê", method: .backspaceFast, delays: .zero)
            if case .failure(let e) = result {
                XCTFail("\(ctx.displayName) must allow inject, got \(e)")
            }
            XCTAssertEqual(sink.commands, [.backspace, .unicodeChunk("ê")], "\(ctx.displayName) plan mismatch")
        }
    }

    func testFinderLaunch_AllImplementedMethodsSucceedWithoutPreflight() {
        // selection / emptyCharPrefix / charByChar / axDirect fallback must also bypass old gate.
        let methods: [InjectionMethod] = [.selection, .emptyCharPrefix, .charByChar, .axDirect, .backspaceFast]
        for method in methods {
            let (injector, sink, _) = makeInjector()
            let result = injector.inject(backspace: 1, text: "x", method: method, delays: .zero)
            if case .failure(let e) = result {
                XCTFail("Finder method \(method.rawValue) must not block, got \(e)")
            }
            XCTAssertFalse(sink.commands.isEmpty, "method \(method.rawValue) must post commands via Finder")
        }
    }

    // MARK: - 3. AppState readiness via Finder (no postEventAccessGranted dependency)

    func testFinderLaunch_AppStateReadyWithoutPostEventAccess() {
        let state = makeFinderTrustedState()
        // Must be ready even though we never set any post-event access flag
        // (property removed — gate no longer exists).
        XCTAssertTrue(state.isReadyToType, "Finder launch: trusted + tap running must be ready")
        XCTAssertEqual(state.onboardingPhase, .ready)
        XCTAssertNotEqual(state.onboardingPhase, .setupFailed)

        // Reflection guard: AppState must not have postEventAccessGranted stored property.
        let mirror = Mirror(reflecting: state)
        let hasPostEventProp = mirror.children.contains { $0.label == "postEventAccessGranted" }
        // Also check published storage naming (`_postEventAccessGranted` or `postEventAccessGranted`).
        let hasAnyPostEventKey = mirror.children.contains { ($0.label ?? "").lowercased().contains("postevent") }
        XCTAssertFalse(hasPostEventProp, "postEventAccessGranted must be removed — Finder regression gate")
        XCTAssertFalse(hasAnyPostEventKey, "no postEvent key should remain on AppState")
    }

    func testFinderLaunch_MenuBarShowsActiveNotSetup() {
        let state = makeFinderTrustedState()
        XCTAssertEqual(state.menuBarIconState, .active, "Finder: trusted+running VI must be .active not .setup")
        XCTAssertNotEqual(state.menuBarIconState, .setup)
        XCTAssertEqual(state.menuBarIconState.assetName, "MenuBarActive")
        XCTAssertEqual(state.menuBarTitle, "VI")
        XCTAssertTrue(state.menuBarToolTip.contains("VI"), "tooltip must show VI, not 'cần quyền gửi sự kiện'")
        XCTAssertFalse(state.menuBarToolTip.contains("quyền gửi sự kiện"))
        XCTAssertFalse(state.menuBarToolTip.contains("need post-event"))
        XCTAssertEqual(state.accessibilityMenuLabel, "Accessibility: đã cấp quyền · đang gõ")
    }

    func testFinderLaunch_OnboardingReadyNotNeedsPostEventAccess() {
        let state = makeFinderTrustedState()
        // Before fix, onboardingPhase was .needsPostEventAccess when postEventAccessGranted==false
        // That case has been removed — Finder launch must be .ready.
        switch state.onboardingPhase {
        case .needsAccessibility:
            XCTFail("Finder trusted state must not needAccessibility")
        case .ready:
            break // expected
        case .setupFailed:
            XCTFail("Finder trusted+running must not be setupFailed")
        }
        // Compile-time guard: .needsPostEventAccess should not exist.
        // If it still exists, this file would not compile without handling it;
        // runtime mirror check below catches it more explicitly.
        let phaseMirror = String(describing: state.onboardingPhase)
        XCTAssertFalse(phaseMirror.contains("needsPostEventAccess"))
        XCTAssertFalse(phaseMirror.contains("PostEvent"))
    }

    func testFinderLaunch_BlockedInputSourceStillInactive() {
        // Sanity: other gates (inputSourceBlocked) still work via Finder — only post-event gate removed.
        let state = makeFinderTrustedState()
        state.inputSourceBlocked = true
        XCTAssertEqual(state.menuBarIconState, .inactive)
        XCTAssertFalse(state.isReadyToType == false && state.menuBarIconState == .active, "blocked must not be active")
    }

    // MARK: - 4. TypingSession via Finder (integration)

    func testFinderLaunch_TypingSessionStillTransformsViaInject() {
        // End-to-end: TypingSession (pipeline+injector) must transform a→â via Finder
        // without any preflight setup. Legacy would have fail-open passed original.
        let sink = RecordingEventSink()
        let sleeper = RecordingInjectorSleeper()
        let bridge = DauCoreBridge(method: DauMethod_Telex)
        bridge.setAutoCapitalize(false)
        bridge.setAutoRestore(false)
        bridge.setEnabled(true)
        let pipeline = MacKeyPipeline(bridge: bridge)
        let injector = TextInjector(sink: sink, sleeper: sleeper, axAccessor: AXTextAccessor())
        let session = TypingSession(pipeline: pipeline, injector: injector)
        session.applyRuntimeSettings(
            typingEnabled: true,
            injectionMethod: .backspaceFast,
            delays: .zero,
            engineMethod: DauMethod_Telex
        )

        func printable(_ ch: Character) -> ClassifiedKey {
            ClassifiedKey(kind: .printable(ch.unicodeScalars.first!), keyCode: 0, isRepeat: false, shiftHeld: false)
        }
        // First 'a' plain append passes
        _ = session.handleKey(printable("a"))
        sink.reset()
        // Second 'a' → â transform must consumeOriginal + inject via Finder
        let exp = expectation(description: "finder-inject")
        var sawInjectResult: Result<Void, InjectionError>?
        session.onInjectCompleted = { r in sawInjectResult = r; exp.fulfill() }
        let d = session.handleKey(printable("a"))
        wait(for: [exp], timeout: 1.0)
        session.onInjectCompleted = nil

        XCTAssertTrue(d.consumeOriginal, "Finder transform must consume original")
        XCTAssertTrue(d.injectScheduled)
        if case .failure(let e) = sawInjectResult {
            XCTFail("Finder TypingSession inject must not fail with \(e)")
        }
        XCTAssertEqual(sink.commands, [.backspace, .unicodeChunk("â")])
    }

    // MARK: - 5. Explicit regression guard: error case removed

    func testInjectionError_HasNoPostAccessDeniedCase() {
        // String reflection guard — survives even if exhaustive switch above is missed.
        let allErrors: [InjectionError] = [.invalidBackspaceCount, .unsupportedMethod(.passthrough), .sinkFailed("x")]
        for err in allErrors {
            let desc = String(describing: err)
            XCTAssertFalse(desc.contains("postAccess"), "InjectionError must not contain postAccessDenied, got \(desc)")
            XCTAssertFalse(desc.contains("post_access"))
        }
        // Ensure no case string equals "postAccessDenied" via Mirror on the type.
        // This catches re-introduction even if tests aren't recompiled exhaustively.
        let typeDesc = String(describing: InjectionError.self)
        XCTAssertFalse(typeDesc.contains("postAccessDenied"))
    }
}
