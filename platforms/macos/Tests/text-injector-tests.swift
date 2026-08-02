// Dấu macOS — TextInjector unit tests (WP-03 / TG-05).
// Uses RecordingEventSink / RecordingInjectorSleeper / FakeTargetDocument; no real CGEvent posts.

import XCTest

final class TextInjectorTests: XCTestCase {
    private var sink: RecordingEventSink!
    private var sleeper: RecordingInjectorSleeper!
    private var injector: TextInjector!

    override func setUp() {
        super.setUp()
        SyntheticPostAccess.check = { true }
        sink = RecordingEventSink()
        sleeper = RecordingInjectorSleeper()
        injector = TextInjector(sink: sink, sleeper: sleeper, axAccessor: AXTextAccessor())
    }

    override func tearDown() {
        injector = nil
        sleeper = nil
        sink = nil
        SyntheticPostAccess.resetToDefault()
        super.tearDown()
    }

    private func assertSuccess(
        _ result: Result<Void, InjectionError>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        if case .failure(let err) = result {
            XCTFail("expected success, got \(err)", file: file, line: line)
        }
    }

    private func assertFailure(
        _ result: Result<Void, InjectionError>,
        _ expected: InjectionError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        switch result {
        case .success:
            XCTFail("expected failure \(expected)", file: file, line: line)
        case .failure(let err):
            XCTAssertEqual(err, expected, file: file, line: line)
        }
    }

    // MARK: - Plan ordering (BS then text)

    func testPlanBackspaceFastOrdersBSThenText() {
        let delays = DelayPreset(backspaceUs: 10, settleUs: 20, textUs: 30)
        let plan = injector.plan(
            backspace: 3,
            text: "á",
            method: .backspaceFast,
            delays: delays
        )

        // Three BS, settle, one unicode chunk, text delay.
        let nonWait = plan.filter {
            if case .wait = $0 { return false }
            return true
        }
        XCTAssertEqual(nonWait, [
            .backspace, .backspace, .backspace,
            .unicodeChunk("á"),
        ])

        // First non-text actions must be backspaces before any unicode.
        var sawText = false
        for cmd in plan {
            if case .unicodeChunk = cmd {
                sawText = true
            }
            if case .backspace = cmd {
                XCTAssertFalse(sawText, "backspace must come before text")
            }
        }
        XCTAssertTrue(sawText)
    }

    func testPlanBackspaceSlowUsesSameOrderAsFast() {
        let delays = DelayPreset.slow
        let fast = injector.plan(backspace: 2, text: "ok", method: .backspaceFast, delays: delays)
        let slow = injector.plan(backspace: 2, text: "ok", method: .backspaceSlow, delays: delays)
        XCTAssertEqual(fast, slow, "fast/slow share plan shape; only caller delays differ")
    }

    func testPlanCharByCharSplitsScalars() {
        let plan = injector.plan(
            backspace: 1,
            text: "ab",
            method: .charByChar,
            delays: .zero
        )
        XCTAssertEqual(plan, [
            .backspace,
            .unicodeChunk("a"),
            .unicodeChunk("b"),
        ])
    }

    func testPlanPassthroughIsEmpty() {
        let plan = injector.plan(
            backspace: 5,
            text: "ignored",
            method: .passthrough,
            delays: .fast
        )
        XCTAssertTrue(plan.isEmpty)
    }

    func testPlanBackspaceOnlyWhenTextEmpty() {
        let plan = injector.plan(
            backspace: 2,
            text: "",
            method: .backspaceFast,
            delays: .zero
        )
        XCTAssertEqual(plan, [.backspace, .backspace])
    }

    func testPlanIncludesDelays() {
        let delays = DelayPreset(backspaceUs: 1, settleUs: 2, textUs: 3)
        let plan = injector.plan(
            backspace: 2,
            text: "x",
            method: .backspaceFast,
            delays: delays
        )
        XCTAssertTrue(plan.contains(.wait(microseconds: 1)))
        XCTAssertTrue(plan.contains(.wait(microseconds: 2)))
        XCTAssertTrue(plan.contains(.wait(microseconds: 3)))
    }

    // MARK: - Execute via sink

    func testInjectPostsBSThenTextToSink() {
        let result = injector.inject(
            backspace: 2,
            text: "vi",
            method: .backspaceFast,
            delays: .zero
        )
        assertSuccess(result)
        XCTAssertEqual(sink.commands, [
            .backspace, .backspace,
            .unicodeChunk("vi"),
        ])
    }

    func testInjectRecordsSleepsWithoutWallClock() {
        let delays = DelayPreset(backspaceUs: 5, settleUs: 7, textUs: 9)
        _ = injector.inject(
            backspace: 2,
            text: "z",
            method: .backspaceSlow,
            delays: delays
        )
        XCTAssertFalse(sleeper.sleeps.isEmpty)
        XCTAssertTrue(sleeper.sleeps.contains(5) || sleeper.sleeps.contains(7))
        XCTAssertTrue(sleeper.sleeps.contains(9))
    }

    func testInjectPassthroughDoesNotTouchSink() {
        _ = injector.inject(
            backspace: 3,
            text: "nope",
            method: .passthrough,
            delays: .fast
        )
        XCTAssertTrue(sink.commands.isEmpty)
    }

    func testInjectRejectsNegativeBackspace() {
        let result = injector.inject(
            backspace: -1,
            text: "x",
            method: .backspaceFast,
            delays: .zero
        )
        assertFailure(result, .invalidBackspaceCount)
        XCTAssertTrue(sink.commands.isEmpty)
    }

    // MARK: - Implemented methods (selection / emptyCharPrefix real, syncProxy stub fallback)

    func testSelectionPlansShiftLeftThenText() {
        let plan = injector.plan(backspace: 2, text: "hi", method: .selection, delays: .zero)
        XCTAssertEqual(plan, [
            .shiftLeft, .shiftLeft,
            .wait(microseconds: 1000), // settle floor before replacement
            .unicodeChunk("hi"),
        ])
        let result = injector.inject(backspace: 2, text: "hi", method: .selection, delays: .zero)
        assertSuccess(result)
        XCTAssertEqual(sink.commands, [.shiftLeft, .shiftLeft, .unicodeChunk("hi")])
    }

    func testSelectionWithEmptyTextUsesBackspace() {
        let plan = injector.plan(backspace: 2, text: "", method: .selection, delays: .zero)
        XCTAssertEqual(plan, [.backspace, .backspace])
        let result = injector.inject(backspace: 2, text: "", method: .selection, delays: .zero)
        assertSuccess(result)
        XCTAssertEqual(sink.commands, [.backspace, .backspace])
        XCTAssertFalse(sink.commands.contains(.shiftLeft), "empty wipe must not Shift+Left-select whitespace")
    }

    func testSelectionPreservesNonzeroSettle() {
        // Nonzero user settleUs is preserved unchanged — no 1000us floor override.
        let delays = DelayPreset(backspaceUs: 0, settleUs: 3000, textUs: 0)
        let plan = injector.plan(backspace: 1, text: "x", method: .selection, delays: delays)
        XCTAssertEqual(plan, [
            .shiftLeft,
            .wait(microseconds: 3000),
            .unicodeChunk("x"),
        ])
    }

    func testSelectionKeepsExactSubMillisecondSettle() {
        // Gõ Nhanh conditional semantics: settle > 0 ? settle : 1000. A 500us
        // configured settle must NOT be raised to the 1000us floor.
        let delays = DelayPreset(backspaceUs: 0, settleUs: 500, textUs: 0)
        let plan = injector.plan(backspace: 1, text: "x", method: .selection, delays: delays)
        XCTAssertEqual(plan, [
            .shiftLeft,
            .wait(microseconds: 500),
            .unicodeChunk("x"),
        ])
    }

    func testSelectionZeroSettleAddsFloorOnceNotPerScalar() {
        // Floor is exactly one 1000us wait for the batch — never one per selected scalar.
        let plan = injector.plan(backspace: 3, text: "xyz", method: .selection, delays: .zero)
        let waits = plan.compactMap { cmd -> UInt32? in
            if case .wait(let us) = cmd { return us }
            return nil
        }
        XCTAssertEqual(waits, [1000], "exactly one 1000us floor for the whole Shift+Left batch")
        XCTAssertEqual(plan, [
            .shiftLeft, .shiftLeft, .shiftLeft,
            .wait(microseconds: 1000),
            .unicodeChunk("xyz"),
        ])
    }

    func testEmptyCharPrefixPlansPrefixThenBackspacesThenText() {
        let plan = injector.plan(backspace: 1, text: "a", method: .emptyCharPrefix, delays: .zero)
        XCTAssertEqual(plan, [
            .emptyPrefix,
            .wait(microseconds: 1000), // floor after prefix before deletions
            .backspace, .backspace,
            .unicodeChunk("a"),
        ])
        let result = injector.inject(backspace: 1, text: "a", method: .emptyCharPrefix, delays: .zero)
        assertSuccess(result)
        XCTAssertEqual(sink.commands, [.emptyPrefix, .backspace, .backspace, .unicodeChunk("a")])
    }

    func testEmptyCharPrefixEmptyTextStillPostsPrefixAndWipes() {
        let plan = injector.plan(backspace: 1, text: "", method: .emptyCharPrefix, delays: .zero)
        XCTAssertEqual(plan, [
            .emptyPrefix,
            .wait(microseconds: 1000),
            .backspace, .backspace,
        ])
        let result = injector.inject(backspace: 1, text: "", method: .emptyCharPrefix, delays: .zero)
        assertSuccess(result)
        XCTAssertEqual(sink.commands, [.emptyPrefix, .backspace, .backspace])
    }

    func testEmptyCharPrefixKeepsExactSubMillisecondBackspaceDelay() {
        // Gõ Nhanh conditional semantics: backspace delay > 0 ? delay : 1000.
        // A 500us configured delay must NOT be raised to the 1000us floor.
        let delays = DelayPreset(backspaceUs: 500, settleUs: 0, textUs: 0)
        let plan = injector.plan(backspace: 1, text: "a", method: .emptyCharPrefix, delays: delays)
        XCTAssertEqual(plan, [
            .emptyPrefix,
            .wait(microseconds: 500),
            .backspace,
            .wait(microseconds: 500), // per-backspace wait (backspaceUs > 0)
            .backspace,
            .wait(microseconds: 500),
            .unicodeChunk("a"),
        ])
    }

    func testEmptyCharPrefixPreservesNonzeroBackspaceDelay() {
        // Nonzero user backspaceUs is preserved unchanged — the 1000us floor does not
        // override it (per-backspace waits are also retained, as in backspaceFast).
        let delays = DelayPreset(backspaceUs: 2000, settleUs: 0, textUs: 0)
        let plan = injector.plan(backspace: 1, text: "a", method: .emptyCharPrefix, delays: delays)
        XCTAssertEqual(plan, [
            .emptyPrefix,
            .wait(microseconds: 2000), // floor = nonzero user delay, not 1000
            .backspace,
            .wait(microseconds: 2000), // per-backspace wait (backspaceUs > 0)
            .backspace,
            .wait(microseconds: 2000),
            .unicodeChunk("a"),
        ])
    }

    func testEmptyCharPrefixFloorAddedOnceNotPerBackspace() {
        // Zero delays → floor is exactly one 1000us wait after the prefix, plus
        // backspaces and text (no per-backspace waits).
        let plan = injector.plan(backspace: 3, text: "", method: .emptyCharPrefix, delays: .zero)
        let waits = plan.compactMap { cmd -> UInt32? in
            if case .wait(let us) = cmd { return us }
            return nil
        }
        XCTAssertEqual(waits, [1000], "exactly one 1000us floor after prefix, none per backspace")
        XCTAssertEqual(plan, [
            .emptyPrefix,
            .wait(microseconds: 1000),
            .backspace, .backspace, .backspace, .backspace, // prefix + 3 composed scalars
        ])
    }

    func testSyncProxyFallsBackToBackspaceFast() {
        let result = injector.inject(
            backspace: 1,
            text: "b",
            method: .syncProxy,
            delays: .zero
        )
        assertSuccess(result)
        XCTAssertEqual(sink.commands, [.backspace, .unicodeChunk("b")])
    }

    func testSelectionSinkFailureDoesNotReportSuccess() {
        // Plan: shiftLeft, shiftLeft, unicode — fail on the second shiftLeft.
        sink.failAtCommandIndex = 2
        let result = injector.inject(backspace: 2, text: "hi", method: .selection, delays: .zero)
        switch result {
        case .success:
            XCTFail("must not report success after selection batch failure")
        case .failure(let err):
            if case .sinkFailed = err {
                // expected
            } else {
                XCTFail("expected sinkFailed, got \(err)")
            }
        }
        XCTAssertEqual(sink.commands, [.shiftLeft, .shiftLeft], "must stop after failed command")
    }

    func testEmptyCharPrefixSinkFailureDoesNotReportSuccess() {
        // Plan: emptyPrefix, BS, BS, unicode — fail on the first backspace.
        sink.failAtCommandIndex = 2
        let result = injector.inject(backspace: 1, text: "a", method: .emptyCharPrefix, delays: .zero)
        switch result {
        case .success:
            XCTFail("must not report success after empty-prefix batch failure")
        case .failure(let err):
            if case .sinkFailed = err {
                // expected
            } else {
                XCTFail("expected sinkFailed, got \(err)")
            }
        }
        XCTAssertEqual(sink.commands, [.emptyPrefix, .backspace], "must stop after failed command")
    }

    func testAxDirectFallbackWhenAXUnavailable() {
        // Without Accessibility trust / focused field, AX path fails → synthetic fallback.
        let result = injector.inject(
            backspace: 1,
            text: "c",
            method: .axDirect,
            delays: .zero
        )
        assertSuccess(result)
        XCTAssertEqual(sink.commands, [.backspace, .unicodeChunk("c")])
    }

    // MARK: - Per-command failure (TG-05)

    func testMidBatchBackspaceFailureDoesNotReportSuccess() {
        // Plan: BS, BS, unicode — fail on 2nd BS.
        sink.failAtCommandIndex = 2
        let result = injector.inject(
            backspace: 2,
            text: "x",
            method: .backspaceFast,
            delays: .zero
        )
        switch result {
        case .success:
            XCTFail("must not report success after mid-batch failure")
        case .failure(let err):
            if case .sinkFailed = err {
                // ok
            } else {
                XCTFail("expected sinkFailed, got \(err)")
            }
        }
        XCTAssertEqual(sink.commands, [.backspace, .backspace], "must stop after failed command")
    }

    func testTextChunkFailureDoesNotReportSuccess() {
        sink.failAtCommandIndex = 2 // BS then fail on unicode
        let result = injector.inject(
            backspace: 1,
            text: "z",
            method: .backspaceFast,
            delays: .zero
        )
        if case .success = result {
            XCTFail("must not report success when text post fails")
        }
        XCTAssertEqual(sink.commands.count, 2)
    }

    func testFirstCommandFailureLeavesNoFurtherPosts() {
        sink.failAtCommandIndex = 1
        let result = injector.inject(
            backspace: 3,
            text: "abc",
            method: .backspaceFast,
            delays: .zero
        )
        if case .success = result {
            XCTFail("expected failure")
        }
        XCTAssertEqual(sink.commands, [.backspace])
    }

    // MARK: - Metadata logging never includes text

    func testMetadataCallbackDoesNotContainTextContent() {
        var logs: [String] = []
        injector.onMetadata = { logs.append($0) }
        let secret = "SECRET_PAYLOAD_XYZ"
        _ = injector.inject(
            backspace: 1,
            text: secret,
            method: .backspaceFast,
            delays: .zero,
            context: InjectionDeliveryContext(
                batchId: 42,
                bundleId: "com.example.App",
                mode: .sync,
                requestedMethod: .backspaceFast
            )
        )
        XCTAssertFalse(logs.isEmpty)
        for line in logs {
            XCTAssertFalse(line.contains(secret), "log must not contain text content: \(line)")
            XCTAssertTrue(line.contains("textLen="))
            XCTAssertTrue(line.contains("method="))
        }
        let joined = logs.joined(separator: "\n")
        XCTAssertTrue(joined.contains("batch=42"))
        XCTAssertTrue(joined.contains("bundle=com.example.App"))
        XCTAssertTrue(joined.contains("mode=sync"))
    }

    // MARK: - Marker

    func testSyntheticMarkerConstantIsNonZero() {
        XCTAssertNotEqual(SyntheticEventMarker.userData, 0)
    }

    // MARK: - DelayPreset / method defaults

    func testMethodDefaultDelays() {
        XCTAssertEqual(InjectionMethod.backspaceFast.defaultDelays, .fast)
        XCTAssertEqual(InjectionMethod.backspaceSlow.defaultDelays, .slow)
        XCTAssertEqual(InjectionMethod.passthrough.defaultDelays, .zero)
        XCTAssertTrue(InjectionMethod.backspaceFast.isMVPImplemented)
        XCTAssertTrue(InjectionMethod.axDirect.isMVPImplemented)
        XCTAssertTrue(InjectionMethod.selection.isMVPImplemented)
        XCTAssertTrue(InjectionMethod.emptyCharPrefix.isMVPImplemented)
        XCTAssertFalse(InjectionMethod.syncProxy.isMVPImplemented)
        XCTAssertEqual(InjectionMethod.selection.deliveryImplementation, .selection)
        XCTAssertEqual(InjectionMethod.emptyCharPrefix.deliveryImplementation, .emptyCharPrefix)
        XCTAssertEqual(InjectionMethod.syncProxy.deliveryImplementation, .backspaceFast)
        XCTAssertEqual(InjectionMethod.backspaceSlow.deliveryImplementation, .backspaceSlow)
    }

    // MARK: - AX timeout helpers

    func testAXTimeoutClamp() {
        XCTAssertEqual(AXTextAccessor.clampTimeout(-1), AXTextAccessor.defaultTimeoutSeconds)
        XCTAssertEqual(AXTextAccessor.clampTimeout(Float.nan), AXTextAccessor.defaultTimeoutSeconds)
        XCTAssertEqual(AXTextAccessor.clampTimeout(10), AXTextAccessor.maxTimeoutSeconds)
        XCTAssertEqual(AXTextAccessor.clampTimeout(0.02), 0.02)
    }

    func testAXAccessorReplaceNegativeCountFails() {
        let ax = AXTextAccessor()
        let result = ax.replaceFocusedText(deleteScalarCount: -1, replacement: "")
        switch result {
        case .success:
            XCTFail("expected failure for negative delete count")
        case .failure(let err):
            XCTAssertEqual(err, .messagingFailed("negative delete count"))
        }
    }

    // MARK: - Dead-key inject guards

    func testInjectFailsWhenPostAccessDenied() {
        SyntheticPostAccess.check = { false }
        let result = injector.inject(
            backspace: 1,
            text: "a",
            method: .backspaceFast,
            delays: .zero
        )
        assertFailure(result, .postAccessDenied)
        XCTAssertTrue(sink.commands.isEmpty, "must not post partial sequence without access")
    }

    func testInjectPropagatesSinkFailure() {
        sink.shouldSucceed = false
        let result = injector.inject(
            backspace: 0,
            text: "a",
            method: .backspaceFast,
            delays: .zero
        )
        switch result {
        case .success:
            XCTFail("expected sink failure")
        case .failure(let err):
            if case .sinkFailed = err {
                // ok
            } else {
                XCTFail("expected sinkFailed, got \(err)")
            }
        }
        XCTAssertEqual(sink.commands, [.unicodeChunk("a")])
    }

    // MARK: - Fake target document (injector-level)

    func testFakeDocumentAppliesBackspaceThenText() {
        let doc = FakeTargetDocument()
        doc.seed("ab")
        let inj = TextInjector(sink: doc, sleeper: sleeper, axAccessor: AXTextAccessor())
        let result = inj.inject(backspace: 1, text: "X", method: .backspaceFast, delays: .zero)
        assertSuccess(result)
        XCTAssertEqual(doc.content, "aX")
    }

    func testFakeDocumentMidBatchFailureStopsMutation() {
        let doc = FakeTargetDocument()
        doc.seed("hello")
        doc.failAtCommandIndex = 2 // first BS ok, second BS fails
        let inj = TextInjector(sink: doc, sleeper: sleeper, axAccessor: AXTextAccessor())
        let result = inj.inject(backspace: 3, text: "Z", method: .backspaceFast, delays: .zero)
        if case .success = result {
            XCTFail("expected failure")
        }
        // Only one successful BS applied before fail.
        XCTAssertEqual(doc.content, "hell")
    }

    // MARK: - Developer-surface contract → plan ordering (gap-6 matrix)

    /// Locks the plan shape each developer surface resolves to. Ordering prevents
    /// lost/duplicated characters: combo/search = Shift+Left selection before text;
    /// address bar = empty-prefix guard before deletions; terminal/textField =
    /// backspaceFast; editor/textarea = per-scalar delivery.
    func testDeveloperSurfaceContractPlans() {
        // comboBox / search → selection: Shift+Left then text, no backspace.
        let combo = injector.plan(backspace: 2, text: "vi", method: .selection, delays: .zero)
        XCTAssertEqual(
            combo.filter { if case .wait = $0 { return false }; return true },
            [.shiftLeft, .shiftLeft, .unicodeChunk("vi")]
        )

        // addressBar → emptyCharPrefix: prefix guard, floor, deletions, then text.
        let bar = injector.plan(backspace: 1, text: "a", method: .emptyCharPrefix, delays: .zero)
        XCTAssertEqual(bar, [
            .emptyPrefix,
            .wait(microseconds: 1000), // floor after prefix before deletions
            .backspace, .backspace,
            .unicodeChunk("a"),
        ])

        // terminal / textField → backspaceFast: backspaces then bulk text.
        let field = injector.plan(backspace: 2, text: "vi", method: .backspaceFast, delays: .zero)
        XCTAssertEqual(field, [.backspace, .backspace, .unicodeChunk("vi")])

        // editor / textarea → charByChar: one unicode chunk per scalar.
        let editor = injector.plan(backspace: 1, text: "vi", method: .charByChar, delays: .zero)
        XCTAssertEqual(editor, [.backspace, .unicodeChunk("v"), .unicodeChunk("i")])
    }
}
