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

    private func backspaceKey(isRepeat: Bool = false) -> ClassifiedKey {
        ClassifiedKey(
            kind: .backspace,
            keyCode: KeyClassifier.KeyCode.delete,
            isRepeat: isRepeat,
            shiftHeld: false
        )
    }

    private func forwardDeleteKey(isRepeat: Bool = false) -> ClassifiedKey {
        ClassifiedKey(
            kind: .forwardDelete,
            keyCode: KeyClassifier.KeyCode.forwardDelete,
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

    /// TG-02: plain single-scalar append passes the physical key (no synthetic inject).
    func testPrintablePlainAppendPassesOriginal() {
        let d = handle(printable("a"))
        XCTAssertFalse(d.consumeOriginal)
        XCTAssertFalse(d.injectScheduled)
        XCTAssertEqual(d.result.backspace, 0)
        XCTAssertEqual(d.result.text, "")
        XCTAssertTrue(sink.commands.isEmpty)
        XCTAssertEqual(session.provisionalLength, 1)
    }

    /// Transform path still consumes and injects minimal rewrite (e.g. a + a → â).
    func testPrintableTransformConsumesAndSchedulesInject() {
        _ = handle(printable("a"))
        sink.reset()
        let d = handle(printable("a"))
        XCTAssertTrue(d.consumeOriginal)
        XCTAssertTrue(d.injectScheduled)
        XCTAssertEqual(d.result.backspace, 1)
        XCTAssertEqual(d.result.text, "â")
        XCTAssertEqual(sink.commands, [.backspace, .unicodeChunk("â")])
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

    func testBackspaceWhileComposingConsumesOneScalarViaInject() {
        _ = handle(printable("a"))
        sink.reset()

        let d = handle(backspaceKey())
        XCTAssertTrue(d.consumeOriginal)
        XCTAssertTrue(d.injectScheduled)
        XCTAssertEqual(d.result.backspace, 1)
        XCTAssertEqual(d.result.text, "")
        XCTAssertEqual(sink.commands, [.backspace])
        XCTAssertEqual(session.provisionalLength, 0)
    }

    func testBackspaceWithoutComposePasses() {
        let d = handle(backspaceKey())
        XCTAssertFalse(d.consumeOriginal)
        XCTAssertFalse(d.injectScheduled)
        XCTAssertTrue(sink.commands.isEmpty)
    }

    // MARK: - TG-04: per-char Backspace → retype suffix → commit (session + inject)

    /// Telex: `tiếng → Backspace → tiến → g → tiếng` then Space commits once.
    func testTelexBackspaceRetypeSuffixCommitViaSession() {
        _ = typeASCII("tieengs")
        XCTAssertEqual(session.provisionalLength, "tiếng".unicodeScalars.count)
        sink.reset()

        let bs = handle(backspaceKey())
        XCTAssertTrue(bs.consumeOriginal)
        XCTAssertTrue(bs.injectScheduled)
        XCTAssertEqual(bs.result.backspace, 1, "one display scalar only")
        XCTAssertEqual(bs.result.text, "")
        XCTAssertEqual(sink.commands, [.backspace])
        XCTAssertEqual(session.provisionalLength, "tiến".unicodeScalars.count)

        sink.reset()
        _ = typeASCII("g")
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

    func testVniBackspaceRetypeSuffixCommitViaSession() {
        session.setMethod(DauMethod_Vni)
        _ = typeASCII("tie6ng1")
        XCTAssertEqual(session.provisionalLength, "tiếng".unicodeScalars.count)
        sink.reset()

        let bs = handle(backspaceKey())
        XCTAssertTrue(bs.consumeOriginal)
        XCTAssertEqual(bs.result.backspace, 1)
        XCTAssertEqual(sink.commands, [.backspace])
        XCTAssertEqual(session.provisionalLength, "tiến".unicodeScalars.count)

        sink.reset()
        _ = typeASCII("g")
        sink.reset()
        let commit = handle(breakSpace())
        XCTAssertFalse(commit.consumeOriginal)
        XCTAssertFalse(commit.injectScheduled)
        XCTAssertEqual(commit.result.backspace, 0)
        XCTAssertEqual(session.provisionalLength, 0)
        XCTAssertTrue(sink.commands.isEmpty)
    }

    func testEnglishDeleteBackspaceThenEViaSession() {
        _ = typeASCII("delete")
        XCTAssertEqual(session.provisionalLength, 6)
        sink.reset()

        let bs = handle(backspaceKey())
        XCTAssertTrue(bs.consumeOriginal)
        XCTAssertEqual(bs.result.backspace, 1)
        XCTAssertEqual(sink.commands, [.backspace])
        XCTAssertEqual(session.provisionalLength, 5)

        sink.reset()
        let e = handle(printable("e"))
        // Plain append: original key passes, no inject rewrite.
        XCTAssertFalse(e.consumeOriginal)
        XCTAssertFalse(e.injectScheduled)
        XCTAssertEqual(session.provisionalLength, 6)
        XCTAssertTrue(sink.commands.isEmpty)
    }

    func testBackspaceAfterCommitPassesWithoutInject() {
        _ = typeASCII("tieengs")
        _ = handle(breakSpace())
        XCTAssertEqual(session.provisionalLength, 0)
        sink.reset()

        let d = handle(backspaceKey())
        XCTAssertFalse(d.consumeOriginal)
        XCTAssertFalse(d.injectScheduled)
        XCTAssertEqual(d.result, .passthrough)
        XCTAssertTrue(sink.commands.isEmpty)
        XCTAssertEqual(session.provisionalLength, 0)
    }

    /// Forward Delete: pass-through + reset; no inject wipe of provisional.
    func testForwardDeleteWhileComposingResetsWithoutInject() {
        _ = typeASCII("aa")
        sink.reset()
        let d = handle(forwardDeleteKey())
        XCTAssertFalse(d.consumeOriginal)
        XCTAssertFalse(d.injectScheduled)
        XCTAssertEqual(d.result, .passthrough)
        XCTAssertEqual(d.result.backspace, 0)
        XCTAssertTrue(sink.commands.isEmpty)
        XCTAssertEqual(session.provisionalLength, 0)
    }

    func testBackspaceRepeatAfterEmptyPassesNoSecondInject() {
        _ = typeASCII("a")
        sink.reset()
        _ = handle(backspaceKey(isRepeat: false))
        XCTAssertEqual(session.provisionalLength, 0)
        sink.reset()

        let repeated = handle(backspaceKey(isRepeat: true))
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

        // Next word starts clean after paste boundary (plain append passes original).
        sink.reset()
        let next = handle(printable("a"))
        XCTAssertFalse(next.consumeOriginal)
        XCTAssertEqual(next.result.text, "")
        XCTAssertEqual(next.result.backspace, 0)
        XCTAssertTrue(sink.commands.isEmpty)
        XCTAssertEqual(session.provisionalLength, 1)
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

    // MARK: - Delays / async path (TG-05)

    /// Destructive inject (consumeOriginal) with non-zero delays still completes before return
    /// (no consume-then-async-without-recovery). Delays run on the session queue via sleeper.
    func testDestructiveDelayedInjectCompletesBeforeReturn() {
        session.setDelays(DelayPreset(backspaceUs: 100, settleUs: 200, textUs: 300))
        _ = handle(printable("a"))
        sleeper.reset()
        var completedBeforeReturn = false
        session.onInjectCompleted = { _ in
            completedBeforeReturn = true
        }
        let d = session.handleKey(printable("a")) // a→â
        session.onInjectCompleted = nil
        XCTAssertTrue(d.consumeOriginal)
        XCTAssertTrue(d.injectScheduled)
        XCTAssertTrue(completedBeforeReturn, "destructive delayed inject must finish before decision returns")
        XCTAssertFalse(sleeper.sleeps.isEmpty, "profile delays still applied on session queue")
        XCTAssertEqual(sink.commands, [.backspace, .unicodeChunk("â")])
    }

    /// Non-destructive inject (pass original + wipe) may still run async when delays > 0.
    func testNonDestructiveWipeMayRunAsyncWithDelays() {
        session.setDelays(DelayPreset(backspaceUs: 50, settleUs: 50, textUs: 50))
        _ = handle(printable("a"))
        sink.reset()
        sleeper.reset()
        bridge.setEnabled(false)
        let d = handle(printable("x"))
        XCTAssertFalse(d.consumeOriginal, "original passes")
        XCTAssertTrue(d.injectScheduled)
        XCTAssertEqual(sink.commands, [.backspace])
        XCTAssertEqual(session.provisionalLength, 0)
    }

    func testApplyRuntimeSettingsIsQueueSafe() {
        session.applyRuntimeSettings(
            typingEnabled: true,
            injectionMethod: .backspaceSlow,
            delays: .slow,
            engineMethod: DauMethod_Vni,
            frontmostBundleId: "com.apple.Terminal"
        )
        XCTAssertEqual(session.currentInjectionMethod(), .backspaceSlow)
        XCTAssertEqual(session.currentDelays(), .slow)
        XCTAssertTrue(session.isTypingEnabled())
        XCTAssertEqual(session.currentFrontmostBundleId(), "com.apple.Terminal")
    }

    /// Declared-only stub methods are rewritten at apply time (never silent stub delivery).
    func testStubInjectionMethodFallsBackAtApply() {
        session.applyRuntimeSettings(
            typingEnabled: true,
            injectionMethod: .selection,
            delays: .zero,
            engineMethod: DauMethod_Telex
        )
        XCTAssertEqual(session.currentInjectionMethod(), .backspaceFast)
        session.setInjectionMethod(.syncProxy)
        XCTAssertEqual(session.currentInjectionMethod(), .backspaceFast)
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
    /// Uses transform inject (a→â) because plain append no longer schedules inject (TG-02).
    func testZeroDelaySinkFailureFailOpenDoesNotConsume() {
        _ = handle(printable("a"))
        sink.reset()
        sink.shouldSucceed = false
        var injectResult: Result<Void, InjectionError>?
        let exp = expectation(description: "inject-failed")
        session.onInjectCompleted = { result in
            injectResult = result
            exp.fulfill()
        }
        let d = session.handleKey(printable("a")) // transform → inject path
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
        XCTAssertFalse(next.consumeOriginal, "plain append passes original")
        XCTAssertEqual(next.result.text, "")
        XCTAssertTrue(sink.commands.isEmpty)
        XCTAssertEqual(session.provisionalLength, 1)
    }

    /// Zero-delay success still runs inject before decision returns (sync path).
    func testZeroDelayInjectCompletesBeforeHandleKeyReturns() {
        _ = handle(printable("a"))
        sink.reset()
        var completedBeforeReturn = false
        session.onInjectCompleted = { _ in
            completedBeforeReturn = true
        }
        let d = session.handleKey(printable("a")) // a→â transform inject
        session.onInjectCompleted = nil
        XCTAssertTrue(d.consumeOriginal)
        XCTAssertTrue(d.injectScheduled)
        XCTAssertTrue(completedBeforeReturn, "zero-delay inject must finish before EventTap gets decision")
        XCTAssertEqual(sink.commands, [.backspace, .unicodeChunk("â")])
    }

    // MARK: - TG-00 fail-open / budget

    /// EN path must not touch SyntheticPostAccess even when the checker blocks forever.
    func testENBypassNeverCallsSyntheticPostAccess() {
        session.setTypingEnabled(false)
        var checkCount = 0
        let latch = DispatchSemaphore(value: 0)
        SyntheticPostAccess.check = {
            checkCount += 1
            latch.wait() // would hang the callback if EN path touched this
            return false
        }

        // English "delete " — every key must pass without waiting on access check.
        for ch in "delete" {
            let d = session.handleKey(printable(ch))
            XCTAssertFalse(d.consumeOriginal)
            XCTAssertFalse(d.injectScheduled)
            XCTAssertFalse(d.timedOut)
        }
        let space = session.handleKey(breakSpace())
        XCTAssertFalse(space.consumeOriginal)
        XCTAssertEqual(checkCount, 0, "EN must not call SyntheticPostAccess.check")
        XCTAssertTrue(sink.commands.isEmpty)

        // Release latch so any stray blocked check cannot hang process teardown.
        latch.signal()
        SyntheticPostAccess.check = { true }
    }

    /// Session/inject work held by latch: callback returns within budget; no late inject after release.
    func testCallbackBudgetTimeoutSkipsLateInject() {
        let budgetNs: UInt64 = 30_000_000 // 30ms test budget
        session = TypingSession(
            pipeline: pipeline,
            injector: injector,
            callbackBudgetNanoseconds: budgetNs
        )
        session.applyRuntimeSettings(
            typingEnabled: true,
            injectionMethod: .backspaceFast,
            delays: .zero,
            engineMethod: DauMethod_Telex
        )
        // Seed provisional so next key can take transform inject path.
        _ = session.handleKey(printable("a"))
        sink.reset()

        let latch = DispatchSemaphore(value: 0)
        var injectStarted = false
        session.testBeforeZeroDelayInject = {
            injectStarted = true
            latch.wait()
        }

        var injectCompletions = 0
        session.onInjectCompleted = { _ in
            injectCompletions += 1
        }

        let start = DispatchTime.now().uptimeNanoseconds
        let d = session.handleKey(printable("a")) // a→â would inject
        let elapsed = DispatchTime.now().uptimeNanoseconds &- start

        XCTAssertTrue(d.timedOut, "must fail-open when work exceeds budget")
        XCTAssertFalse(d.consumeOriginal, "must pass original on timeout")
        XCTAssertFalse(d.injectScheduled)
        XCTAssertLessThan(
            elapsed,
            budgetNs + 200_000_000,
            "callback must return near budget (got \(elapsed)ns)"
        )
        XCTAssertTrue(sink.commands.isEmpty, "no inject posts before/during timeout")

        // Release latch: generation quarantined → no late inject posts.
        latch.signal()
        // Drain session queue.
        _ = session.provisionalLength
        // Give async completion path a beat if any.
        let drain = expectation(description: "drain")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) { drain.fulfill() }
        wait(for: [drain], timeout: 1.0)

        XCTAssertTrue(sink.commands.isEmpty, "no late inject after latch release")
        XCTAssertEqual(injectCompletions, 0, "quarantined generation must not report inject")
        // Compose must not keep stale mutation after timeout.
        XCTAssertEqual(session.provisionalLength, 0)
        // Next key starts clean (plain append).
        sink.reset()
        let next = session.handleKey(printable("b"))
        XCTAssertFalse(next.timedOut)
        XCTAssertFalse(next.consumeOriginal)
        XCTAssertEqual(session.provisionalLength, 1)
        XCTAssertTrue(sink.commands.isEmpty)
        _ = injectStarted // may or may not have reached inject before quarantine
        session.onInjectCompleted = nil
        session.testBeforeZeroDelayInject = nil
    }

    /// Queue held before map: callback still returns; after release no stale core mutation.
    func testQueueLatchBeforeMapFailsOpenWithoutStaleMutation() {
        let budgetNs: UInt64 = 25_000_000
        session = TypingSession(
            pipeline: pipeline,
            injector: injector,
            callbackBudgetNanoseconds: budgetNs
        )
        session.applyRuntimeSettings(
            typingEnabled: true,
            injectionMethod: .backspaceFast,
            delays: .zero,
            engineMethod: DauMethod_Telex
        )

        let latch = DispatchSemaphore(value: 0)
        session.testQueueWorkBegan = {
            latch.wait()
        }

        let d = session.handleKey(printable("x"))
        XCTAssertTrue(d.timedOut)
        XCTAssertFalse(d.consumeOriginal)

        latch.signal()
        _ = session.provisionalLength
        let drain = expectation(description: "drain-map")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) { drain.fulfill() }
        wait(for: [drain], timeout: 1.0)

        XCTAssertEqual(session.provisionalLength, 0, "late map must not keep stale compose")
        session.testQueueWorkBegan = nil
    }

    /// Boundary/shortcut path returns pass without SyntheticPostAccess.
    func testBoundaryEarlyPassSkipsPostAccess() {
        var checkCount = 0
        SyntheticPostAccess.check = {
            checkCount += 1
            return true
        }
        session.setTypingEnabled(true)
        let d = session.handleKey(otherKey(keyCode: 9)) // Cmd+V-like boundary
        XCTAssertFalse(d.consumeOriginal)
        XCTAssertEqual(checkCount, 0)
    }

    // MARK: - TG-05 delayed inject fail-open + state reset

    /// Non-zero delay + destructive transform: sink failure → fail-open (pass original, clear compose).
    func testDelayedDestructiveSinkFailureFailOpen() {
        session.setDelays(DelayPreset(backspaceUs: 10, settleUs: 20, textUs: 30))
        _ = handle(printable("a"))
        sink.reset()
        sink.shouldSucceed = false
        var injectResult: Result<Void, InjectionError>?
        let exp = expectation(description: "inject-failed-delayed")
        session.onInjectCompleted = { result in
            injectResult = result
            exp.fulfill()
        }
        let d = session.handleKey(printable("a"))
        wait(for: [exp], timeout: 1.0)
        session.onInjectCompleted = nil

        XCTAssertFalse(d.consumeOriginal, "must not consume after failed destructive inject")
        XCTAssertTrue(d.injectScheduled)
        if case .failure = injectResult {
            // expected
        } else {
            XCTFail("expected inject failure, got \(String(describing: injectResult))")
        }
        XCTAssertEqual(session.provisionalLength, 0)

        sink.shouldSucceed = true
        sink.reset()
        let next = handle(printable("b"))
        XCTAssertFalse(next.consumeOriginal)
        XCTAssertEqual(session.provisionalLength, 1)
        XCTAssertTrue(sink.commands.isEmpty)
    }

    /// Mid-batch failure resets compose deterministically; next key starts clean.
    func testMidBatchInjectFailureResetsState() {
        _ = handle(printable("a"))
        sink.reset()
        sink.failAtCommandIndex = 1 // fail first BS of transform inject
        var injectResult: Result<Void, InjectionError>?
        let exp = expectation(description: "mid-batch-fail")
        session.onInjectCompleted = { result in
            injectResult = result
            exp.fulfill()
        }
        let d = session.handleKey(printable("a"))
        wait(for: [exp], timeout: 1.0)
        session.onInjectCompleted = nil

        XCTAssertFalse(d.consumeOriginal)
        if case .failure = injectResult {
            // expected
        } else {
            XCTFail("expected failure")
        }
        XCTAssertEqual(session.provisionalLength, 0)

        sink.failAtCommandIndex = nil
        sink.shouldSucceed = true
        sink.reset()
        _ = handle(printable("c"))
        XCTAssertEqual(session.provisionalLength, 1)
    }

    // MARK: - TG-05 fake target document harness

    /// Drive keys through session+injector into an in-memory document.
    /// Physical pass-through keys are applied only when `consumeOriginal` is false.
    @discardableResult
    private func typeIntoDocument(
        _ text: String,
        document: FakeTargetDocument,
        session: TypingSession
    ) -> [String] {
        var snapshots: [String] = []
        for ch in text {
            let key = printable(ch)
            let exp = expectation(description: "doc-key-\(ch)")
            var sawInject = false
            session.onInjectCompleted = { _ in
                sawInject = true
                exp.fulfill()
            }
            let d = session.handleKey(key)
            if d.injectScheduled {
                wait(for: [exp], timeout: 1.0)
            } else {
                exp.fulfill()
                wait(for: [exp], timeout: 0.1)
                XCTAssertFalse(sawInject)
            }
            session.onInjectCompleted = nil
            if !d.consumeOriginal {
                document.applyPhysicalKey(String(ch))
            }
            snapshots.append(document.content)
        }
        return snapshots
    }

    private func makeDocumentSession() -> (FakeTargetDocument, TypingSession, MacKeyPipeline, DauCoreBridge) {
        let doc = FakeTargetDocument()
        let bridge = DauCoreBridge(method: DauMethod_Telex)
        bridge.setAutoCapitalize(false)
        bridge.setAutoRestore(false)
        bridge.setEnabled(true)
        let pipeline = MacKeyPipeline(bridge: bridge)
        let injector = TextInjector(
            sink: doc,
            sleeper: RecordingInjectorSleeper(),
            axAccessor: AXTextAccessor()
        )
        let session = TypingSession(pipeline: pipeline, injector: injector)
        session.applyRuntimeSettings(
            typingEnabled: true,
            injectionMethod: .backspaceFast,
            delays: .zero,
            engineMethod: DauMethod_Telex,
            frontmostBundleId: "com.apple.TextEdit"
        )
        return (doc, session, pipeline, bridge)
    }

    // MARK: - Fake document English contracts (TG-05)
    //
    // Core Telex ownership (verified against engine progressive display):
    // - `delete`, `keyboard`: no mid-word tone transform → strict English prefixes per key.
    // - `text`, `software`: tone letters (x/f/w/…) transform WHILE composing; raw English
    //   returns only on word break (Space) via auto-restore. Do NOT assert English prefixes
    //   per key for these words.

    /// Plain English (no Telex tone letters): strict per-key prefix growth.
    func testFakeDocumentEnglishDeleteExact() {
        let (doc, session, _, _) = makeDocumentSession()
        let snaps = typeIntoDocument("delete", document: doc, session: session)
        // Core progressive: d → de → del → dele → delet → delete
        XCTAssertEqual(snaps, ["d", "de", "del", "dele", "delet", "delete"])
        XCTAssertEqual(doc.content, "delete")
        assertNoLossOrDuplication(snapshots: snaps, finalAfterBreak: nil)
    }

    /// Plain English verified via core: keyboard stays ASCII per key (no mid-compose tone).
    func testFakeDocumentEnglishKeyboardExact() {
        let (doc, session, _, _) = makeDocumentSession()
        let snaps = typeIntoDocument("keyboard", document: doc, session: session)
        XCTAssertEqual(snaps, [
            "k", "ke", "key", "keyb", "keybo", "keyboa", "keyboar", "keyboard",
        ])
        XCTAssertEqual(doc.content, "keyboard")
        assertNoLossOrDuplication(snapshots: snaps, finalAfterBreak: nil)
    }

    /// English with Telex tone letter `x`: mid-compose MAY show `tẽ`/`tẽt` (engine-correct).
    /// Auto-restore on Space must yield raw `"text "` once — no loss, no duplication.
    func testFakeDocumentEnglishTextExact() {
        let (doc, session, _, bridge) = makeDocumentSession()
        bridge.setAutoRestore(true)
        session.setAutoRestore(true)

        let snaps = typeIntoDocument("text", document: doc, session: session)
        XCTAssertEqual(snaps.count, 4, "one snapshot per keystroke")
        XCTAssertEqual(snaps.first, "t")
        // Do NOT require English prefixes "tex"/"text" while composing — Telex applies `x`=ngã.
        // Delivery must still produce non-empty progressive states without wipe-to-empty mid-word.
        for (i, s) in snaps.enumerated() {
            XCTAssertFalse(s.isEmpty, "step \(i) must not drop all text")
        }
        // Document after keys is whatever engine displayed last (transformed is OK).
        XCTAssertEqual(doc.content, snaps.last)

        commitSpaceIntoDocument(document: doc, session: session)
        XCTAssertEqual(
            doc.content,
            "text ",
            "auto-restore on break must deliver raw English + space once"
        )
        assertNoLossOrDuplication(snapshots: snaps, finalAfterBreak: doc.content)
        XCTAssertFalse(doc.content.contains("texttext"), "no duplicated raw word")
        XCTAssertFalse(doc.content.contains("tẽttẽt"), "no duplicated composed form")
    }

    /// English with Telex tone letters `f`/`w`: mid-compose MAY be `sò`/`sờ…` (engine-correct).
    /// Auto-restore on Space must yield raw `"software "` once.
    func testFakeDocumentEnglishSoftwareExact() {
        let (doc, session, _, bridge) = makeDocumentSession()
        bridge.setAutoRestore(true)
        session.setAutoRestore(true)

        let snaps = typeIntoDocument("software", document: doc, session: session)
        XCTAssertEqual(snaps.count, 8, "one snapshot per keystroke")
        XCTAssertEqual(snaps.first, "s")
        // Do NOT assert English prefixes ("sof","soft",…) — f/w are tone/horn keys in Telex.
        for (i, s) in snaps.enumerated() {
            XCTAssertFalse(s.isEmpty, "step \(i) must not drop all text")
        }
        XCTAssertEqual(doc.content, snaps.last)

        commitSpaceIntoDocument(document: doc, session: session)
        XCTAssertEqual(
            doc.content,
            "software ",
            "auto-restore on break must deliver raw English + space once"
        )
        assertNoLossOrDuplication(snapshots: snaps, finalAfterBreak: doc.content)
        XCTAssertFalse(doc.content.contains("softwaresoftware"), "no duplicated raw word")
    }

    private func commitSpaceIntoDocument(document: FakeTargetDocument, session: TypingSession) {
        let exp = expectation(description: "space-commit")
        session.onInjectCompleted = { _ in exp.fulfill() }
        let d = session.handleKey(breakSpace())
        if d.injectScheduled {
            wait(for: [exp], timeout: 1.0)
        } else {
            exp.fulfill()
            wait(for: [exp], timeout: 0.1)
        }
        session.onInjectCompleted = nil
        if !d.consumeOriginal {
            document.applyPhysicalKey(" ")
        }
    }

    /// Loss/duplication guards for delivery harness (not tone-transform detection).
    /// - Every intermediate snapshot non-empty (no wipe-to-empty mid-word)
    /// - No snapshot equals previous+previous (classic inject duplication)
    /// - Optional final-after-break must be non-empty and not double the pre-break last snapshot
    private func assertNoLossOrDuplication(
        snapshots: [String],
        finalAfterBreak: String?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertFalse(snapshots.isEmpty, file: file, line: line)
        for (i, s) in snapshots.enumerated() {
            XCTAssertFalse(
                s.isEmpty,
                "snapshot[\(i)] empty → text loss mid-compose",
                file: file,
                line: line
            )
            if i > 0 {
                let prev = snapshots[i - 1]
                XCTAssertNotEqual(
                    s,
                    prev + prev,
                    "snapshot[\(i)] doubles previous → duplication",
                    file: file,
                    line: line
                )
            }
        }
        if let final = finalAfterBreak {
            XCTAssertFalse(final.isEmpty, "final document empty after break", file: file, line: line)
            if let last = snapshots.last {
                // e.g. "tẽttẽt " or last+last without space would be a restore/inject dup.
                XCTAssertNotEqual(
                    final.trimmingCharacters(in: .whitespaces),
                    last + last,
                    "final doubles last compose → duplication",
                    file: file,
                    line: line
                )
            }
        }
    }

    func testFakeDocumentTelexTieengsExact() {
        let (doc, session, _, _) = makeDocumentSession()
        // t i e e→ê n g s→tiếng  (exact intermediate after each batch)
        let snaps = typeIntoDocument("tieengs", document: doc, session: session)
        XCTAssertEqual(snaps.last, "tiếng")
        XCTAssertEqual(doc.content, "tiếng")
        // No duplication of prefix letters.
        XCTAssertFalse(doc.content.contains("tieengs"))
        XCTAssertEqual(snaps, [
            "t", "ti", "tie", "tiê", "tiên", "tiêng", "tiếng",
        ])
    }

    func testFakeDocumentVniTie6ng1Exact() {
        let (doc, session, _, bridge) = makeDocumentSession()
        bridge.setMethod(DauMethod_Vni)
        session.setMethod(DauMethod_Vni)
        let snaps = typeIntoDocument("tie6ng1", document: doc, session: session)
        XCTAssertEqual(snaps.last, "tiếng")
        XCTAssertEqual(doc.content, "tiếng")
        XCTAssertEqual(snaps, [
            "t", "ti", "tie", "tiê", "tiên", "tiêng", "tiếng",
        ])
    }

    func testFakeDocumentTelexDduawExact() {
        let (doc, session, _, _) = makeDocumentSession()
        let snaps = typeIntoDocument("dduaw", document: doc, session: session)
        XCTAssertEqual(snaps.last, "đưa")
        XCTAssertEqual(doc.content, "đưa")
        // Expected progressive displays (suffix delta may rewrite only changed suffix).
        XCTAssertEqual(snaps, [
            "d", "đ", "đu", "đua", "đưa",
        ])
    }

    /// Same sequences under non-zero delay profile (destructive inject stays pre-return).
    func testFakeDocumentDeleteUnderSlowProfile() {
        let (doc, session, _, _) = makeDocumentSession()
        session.setDelays(.slow)
        session.setInjectionMethod(.backspaceSlow)
        let snaps = typeIntoDocument("delete", document: doc, session: session)
        XCTAssertEqual(snaps, ["d", "de", "del", "dele", "delet", "delete"])
        XCTAssertEqual(doc.content, "delete")
    }

    func testFakeDocumentNoDupOnSpaceCommit() {
        let (doc, session, _, _) = makeDocumentSession()
        _ = typeIntoDocument("delete", document: doc, session: session)
        let exp = expectation(description: "space")
        session.onInjectCompleted = { _ in exp.fulfill() }
        let d = session.handleKey(breakSpace())
        if d.injectScheduled {
            wait(for: [exp], timeout: 1.0)
        } else {
            exp.fulfill()
            wait(for: [exp], timeout: 0.1)
        }
        session.onInjectCompleted = nil
        if !d.consumeOriginal {
            doc.applyPhysicalKey(" ")
        }
        XCTAssertEqual(doc.content, "delete ")
    }

    /// Inject metadata path never logs typed content (session-level transform).
    func testSessionInjectMetadataExcludesTypedContent() {
        var logs: [String] = []
        injector.onMetadata = { logs.append($0) }
        session.setFrontmostBundleId("com.example.Chat")
        _ = handle(printable("a"))
        _ = handle(printable("a")) // transform â
        let joined = logs.joined(separator: "\n")
        XCTAssertFalse(joined.contains("â"), "must not log typed content")
        XCTAssertTrue(joined.contains("batch="), "batch id for repro")
        XCTAssertTrue(joined.contains("bundle=com.example.Chat") || joined.contains("textLen="))
    }
}
