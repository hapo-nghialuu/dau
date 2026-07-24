// Dấu macOS — TypingSession unit tests (P0 review).
// No real CGEventTap; RecordingEventSink proves inject scheduling without sleep on caller.

import XCTest

final class TypingSessionTests: XCTestCase {
    private var sink: RecordingEventSink!
    private var sleeper: RecordingInjectorSleeper!
    private var bridge: DauCoreBridge!
    private var pipeline: MacKeyPipeline!
    private var injector: TextInjector!
    private var session: TypingSession!

    override func setUp() {
        super.setUp()
        // Unit tests never exercise real CGEvent posts; always grant synthetic post access.
        SyntheticPostAccess.check = { true }
        sink = RecordingEventSink()
        sleeper = RecordingInjectorSleeper()
        bridge = DauCoreBridge(method: DauMethod_Telex)
        bridge.setAutoCapitalize(false)
        bridge.setAutoRestore(false)
        bridge.setEnabled(true)
        pipeline = MacKeyPipeline(bridge: bridge)
        injector = TextInjector(sink: sink, sleeper: sleeper, axAccessor: AXTextAccessor())
        session = TypingSession(pipeline: pipeline, injector: injector)
        session.applyRuntimeSettings(
            typingEnabled: true,
            injectionMethod: .backspaceFast,
            delays: .zero,
            engineMethod: DauMethod_Telex
        )
    }

    override func tearDown() {
        session = nil
        injector = nil
        pipeline = nil
        bridge = nil
        sleeper = nil
        sink = nil
        SyntheticPostAccess.resetToDefault()
        super.tearDown()
    }

    private func sc(_ ch: Character) -> Unicode.Scalar {
        ch.unicodeScalars.first!
    }

    private func printable(_ ch: Character) -> ClassifiedKey {
        ClassifiedKey(
            kind: .printable(sc(ch)),
            keyCode: 0,
            isRepeat: false,
            shiftHeld: false
        )
    }

    private func deleteKey(isRepeat: Bool = false, keyCode: UInt16 = KeyClassifier.KeyCode.delete) -> ClassifiedKey {
        ClassifiedKey(
            kind: .delete,
            keyCode: keyCode,
            isRepeat: isRepeat,
            shiftHeld: false
        )
    }

    private func breakSpace() -> ClassifiedKey {
        ClassifiedKey(
            kind: .breakKey(sc(" ")),
            keyCode: KeyClassifier.KeyCode.space,
            isRepeat: false,
            shiftHeld: false
        )
    }

    private func otherKey(keyCode: UInt16) -> ClassifiedKey {
        ClassifiedKey(
            kind: .other,
            keyCode: keyCode,
            isRepeat: false,
            shiftHeld: false
        )
    }

    /// Handle key with inject hook registered before the call (avoids race).
    @discardableResult
    private func handle(_ key: ClassifiedKey) -> TypingSessionDecision {
        let exp = expectation(description: "inject-or-skip")
        var sawInject = false
        session.onInjectCompleted = { _ in
            sawInject = true
            exp.fulfill()
        }
        let d = session.handleKey(key)
        if d.injectScheduled {
            wait(for: [exp], timeout: 1.0)
        } else {
            // Cancel unused expectation.
            exp.fulfill()
            wait(for: [exp], timeout: 0.1)
            XCTAssertFalse(sawInject)
        }
        session.onInjectCompleted = nil
        return d
    }

    @discardableResult
    private func typeASCII(_ s: String) -> TypingSessionDecision {
        var last = TypingSessionDecision(
            consumeOriginal: false,
            result: .passthrough,
            injectScheduled: false
        )
        for ch in s {
            last = handle(printable(ch))
        }
        return last
    }

    // MARK: - Consume / pass

    func testPrintableConsumesAndSchedulesInject() {
        let d = handle(printable("a"))
        XCTAssertTrue(d.consumeOriginal)
        XCTAssertTrue(d.injectScheduled)
        XCTAssertEqual(d.result.text, "a")
        XCTAssertTrue(d.consumeOriginal)
        XCTAssertEqual(sink.commands, [.unicodeChunk("a")])
    }

    func testBoundaryPassesWithoutInject() {
        let key = ClassifiedKey(
            kind: .other,
            keyCode: KeyClassifier.KeyCode.leftArrow,
            isRepeat: false,
            shiftHeld: false
        )
        let d = handle(key)
        XCTAssertFalse(d.consumeOriginal)
        XCTAssertFalse(d.injectScheduled)
        XCTAssertTrue(sink.commands.isEmpty)
    }

    // MARK: - Delete during compose

    func testDeleteWhileComposingConsumesAndWipesViaInject() {
        _ = handle(printable("a"))
        sink.reset()

        let d = handle(deleteKey())
        XCTAssertTrue(d.consumeOriginal)
        XCTAssertTrue(d.injectScheduled)
        XCTAssertEqual(d.result.backspace, 1)
        XCTAssertEqual(d.result.text, "")
        XCTAssertEqual(sink.commands, [.backspace])
        XCTAssertEqual(session.provisionalLength, 0)
    }

    func testDeleteWithoutComposePasses() {
        let d = handle(deleteKey())
        XCTAssertFalse(d.consumeOriginal)
        XCTAssertFalse(d.injectScheduled)
        XCTAssertTrue(sink.commands.isEmpty)
    }

    // MARK: - DELETE-05: wipe → retype → commit (session + inject)

    /// P0 contract: Backspace while composing wipes **whole provisional**, then retype commits once.
    func testTelexDeleteRetypeCommitOnceViaSession() {
        _ = typeASCII("tieengs")
        XCTAssertEqual(session.provisionalLength, "tiếng".unicodeScalars.count)
        sink.reset()

        let wipe = handle(deleteKey())
        XCTAssertTrue(wipe.consumeOriginal)
        XCTAssertTrue(wipe.injectScheduled)
        XCTAssertEqual(wipe.result.backspace, "tiếng".unicodeScalars.count)
        XCTAssertEqual(wipe.result.text, "")
        // Whole-provisional wipe: N backspaces, no replacement text.
        XCTAssertEqual(sink.commands, Array(repeating: .backspace, count: "tiếng".unicodeScalars.count))
        XCTAssertEqual(session.provisionalLength, 0)

        sink.reset()
        _ = typeASCII("tieengs")
        XCTAssertEqual(session.provisionalLength, "tiếng".unicodeScalars.count)

        sink.reset()
        let commit = handle(breakSpace())
        // Matching provisional + Space: no inject rewrite; Space is not consumed.
        XCTAssertFalse(commit.consumeOriginal)
        XCTAssertFalse(commit.injectScheduled)
        XCTAssertEqual(commit.result.backspace, 0)
        XCTAssertEqual(commit.result.text, "")
        XCTAssertTrue(sink.commands.isEmpty)
        XCTAssertEqual(session.provisionalLength, 0)
    }

    func testVniDeleteRetypeCommitOnceViaSession() {
        session.setMethod(DauMethod_Vni)
        _ = typeASCII("tie6ng1")
        XCTAssertEqual(session.provisionalLength, "tiếng".unicodeScalars.count)
        sink.reset()

        let wipe = handle(deleteKey())
        XCTAssertTrue(wipe.consumeOriginal)
        XCTAssertEqual(wipe.result.backspace, "tiếng".unicodeScalars.count)
        XCTAssertEqual(sink.commands, Array(repeating: .backspace, count: "tiếng".unicodeScalars.count))
        XCTAssertEqual(session.provisionalLength, 0)

        sink.reset()
        _ = typeASCII("tie6ng1")
        sink.reset()
        let commit = handle(breakSpace())
        XCTAssertFalse(commit.consumeOriginal)
        XCTAssertFalse(commit.injectScheduled)
        XCTAssertEqual(commit.result.backspace, 0)
        XCTAssertEqual(session.provisionalLength, 0)
        XCTAssertTrue(sink.commands.isEmpty)
    }

    func testDeleteAfterCommitPassesWithoutInject() {
        _ = typeASCII("tieengs")
        _ = handle(breakSpace())
        XCTAssertEqual(session.provisionalLength, 0)
        sink.reset()

        let d = handle(deleteKey())
        XCTAssertFalse(d.consumeOriginal)
        XCTAssertFalse(d.injectScheduled)
        XCTAssertEqual(d.result, .passthrough)
        XCTAssertTrue(sink.commands.isEmpty)
        XCTAssertEqual(session.provisionalLength, 0)
    }

    func testForwardDeleteWhileComposingWipesViaInject() {
        _ = typeASCII("aa")
        sink.reset()
        let d = handle(deleteKey(keyCode: KeyClassifier.KeyCode.forwardDelete))
        XCTAssertTrue(d.consumeOriginal)
        XCTAssertTrue(d.injectScheduled)
        XCTAssertEqual(d.result.backspace, 1)
        XCTAssertEqual(sink.commands, [.backspace])
        XCTAssertEqual(session.provisionalLength, 0)
    }

    func testDeleteRepeatAfterWipePassesNoSecondInject() {
        _ = typeASCII("a")
        sink.reset()
        _ = handle(deleteKey(isRepeat: false))
        XCTAssertEqual(session.provisionalLength, 0)
        sink.reset()

        let repeated = handle(deleteKey(isRepeat: true))
        XCTAssertFalse(repeated.consumeOriginal)
        XCTAssertFalse(repeated.injectScheduled)
        XCTAssertEqual(repeated.result, .passthrough)
        XCTAssertTrue(sink.commands.isEmpty)
    }

    func testCmdVBoundaryWhileComposingResetsWithoutInject() {
        _ = typeASCII("tieengs")
        XCTAssertGreaterThan(session.provisionalLength, 0)
        sink.reset()

        // Cmd+V classified as .other (boundary): reset compose, pass original shortcut.
        let d = handle(otherKey(keyCode: 9))
        XCTAssertFalse(d.consumeOriginal)
        XCTAssertFalse(d.injectScheduled)
        XCTAssertEqual(d.result, .passthrough)
        XCTAssertTrue(sink.commands.isEmpty, "must not inject stale provisional on paste shortcut")
        XCTAssertEqual(session.provisionalLength, 0)

        // Next word starts clean after paste boundary.
        sink.reset()
        let next = handle(printable("a"))
        XCTAssertTrue(next.consumeOriginal)
        XCTAssertEqual(next.result.text, "a")
        XCTAssertEqual(next.result.backspace, 0)
        XCTAssertEqual(sink.commands, [.unicodeChunk("a")])
    }

    // MARK: - None wipe while composing

    func testDisabledKeyWhileComposingWipesAsync() {
        _ = handle(printable("a"))
        sink.reset()
        XCTAssertEqual(session.provisionalLength, 1)

        bridge.setEnabled(false)
        let d = handle(printable("x"))
        // None wipe: forward original key, still schedule wipe inject.
        XCTAssertFalse(d.consumeOriginal)
        XCTAssertTrue(d.injectScheduled)
        XCTAssertEqual(d.result.backspace, 1)
        XCTAssertEqual(sink.commands, [.backspace])
        XCTAssertEqual(session.provisionalLength, 0)
    }

    // MARK: - EN mode

    func testTypingDisabledPassesAndClears() {
        _ = handle(printable("a"))
        session.setTypingEnabled(false)
        let d = handle(printable("b"))
        XCTAssertFalse(d.consumeOriginal)
        XCTAssertFalse(d.injectScheduled)
        XCTAssertEqual(session.provisionalLength, 0)
    }

    // MARK: - Delays only on async inject path

    func testAsyncInjectMaySleepButMapReturnedAlready() {
        session.setDelays(DelayPreset(backspaceUs: 100, settleUs: 200, textUs: 300))
        sleeper.reset()
        let d = handle(printable("a"))
        XCTAssertTrue(d.consumeOriginal)
        XCTAssertTrue(d.injectScheduled)
        // After inject completed, sleeper recorded delays (async path only).
        XCTAssertFalse(sleeper.sleeps.isEmpty)
    }

    func testApplyRuntimeSettingsIsQueueSafe() {
        session.applyRuntimeSettings(
            typingEnabled: true,
            injectionMethod: .backspaceSlow,
            delays: .slow,
            engineMethod: DauMethod_Vni
        )
        XCTAssertEqual(session.currentInjectionMethod(), .backspaceSlow)
        XCTAssertEqual(session.currentDelays(), .slow)
        XCTAssertTrue(session.isTypingEnabled())
    }

    // MARK: - Dead-key inject fail-open

    /// Without synthetic post access, VI must not consume — original key must pass (no dead key).
    func testPostAccessDeniedFailOpenDoesNotConsume() {
        SyntheticPostAccess.check = { false }
        let d = handle(printable("a"))
        XCTAssertFalse(d.consumeOriginal, "must pass original when inject cannot post")
        XCTAssertFalse(d.injectScheduled)
        XCTAssertEqual(session.provisionalLength, 0)
        XCTAssertTrue(sink.commands.isEmpty)
    }

    /// Zero-delay path: sink failure after map → fail-open (pass original + clear compose).
    func testZeroDelaySinkFailureFailOpenDoesNotConsume() {
        sink.shouldSucceed = false
        var injectResult: Result<Void, InjectionError>?
        let exp = expectation(description: "inject-failed")
        session.onInjectCompleted = { result in
            injectResult = result
            exp.fulfill()
        }
        let d = session.handleKey(printable("a"))
        wait(for: [exp], timeout: 1.0)
        session.onInjectCompleted = nil

        XCTAssertFalse(d.consumeOriginal, "dead-key guard: pass original after inject failure")
        XCTAssertTrue(d.injectScheduled, "inject was attempted")
        if case .failure = injectResult {
            // expected
        } else {
            XCTFail("expected inject failure, got \(String(describing: injectResult))")
        }
        XCTAssertEqual(session.provisionalLength, 0, "compose cleared after fail-open")
        // Next key must not be stuck on stale provisional from the failed path.
        sink.shouldSucceed = true
        sink.reset()
        let next = handle(printable("b"))
        XCTAssertTrue(next.consumeOriginal)
        XCTAssertEqual(next.result.text, "b")
        XCTAssertEqual(sink.commands, [.unicodeChunk("b")])
    }

    /// Zero-delay success still runs inject before decision returns (sync path).
    func testZeroDelayInjectCompletesBeforeHandleKeyReturns() {
        var completedBeforeReturn = false
        session.onInjectCompleted = { _ in
            completedBeforeReturn = true
        }
        let d = session.handleKey(printable("x"))
        session.onInjectCompleted = nil
        XCTAssertTrue(d.consumeOriginal)
        XCTAssertTrue(d.injectScheduled)
        XCTAssertTrue(completedBeforeReturn, "zero-delay inject must finish before EventTap gets decision")
        XCTAssertEqual(sink.commands, [.unicodeChunk("x")])
    }
}
