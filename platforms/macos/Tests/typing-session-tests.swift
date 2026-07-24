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

    private func deleteKey() -> ClassifiedKey {
        ClassifiedKey(
            kind: .delete,
            keyCode: KeyClassifier.KeyCode.delete,
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
}
