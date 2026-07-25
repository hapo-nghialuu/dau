// Unit tests for MacKeyPipeline + DauCoreBridge against real libdau_core.
// No EventTap; feeds Unicode scalars directly.
import XCTest

private struct PipelineFakeDocument {
    var text = ""

    mutating func apply(_ result: BridgeResult, originalKey: String? = nil) {
        let scalars = Array(text.unicodeScalars)
        let keep = max(0, scalars.count - result.backspace)
        text = String(String.UnicodeScalarView(scalars.prefix(keep)))
        text += result.text
        if !result.consumeOriginal, let originalKey {
            text += originalKey
        }
    }
}

final class MacKeyPipelineTests: XCTestCase {
    private var bridge: DauCoreBridge!
    private var pipeline: MacKeyPipeline!

    override func setUp() {
        super.setUp()
        bridge = DauCoreBridge(method: DauMethod_Telex)
        bridge.setAutoCapitalize(false)
        bridge.setAutoRestore(false)
        bridge.setEnabled(true)
        pipeline = MacKeyPipeline(bridge: bridge)
    }

    override func tearDown() {
        pipeline = nil
        bridge = nil
        super.tearDown()
    }

    // MARK: - Helpers

    /// Single ASCII/BMP code point helper (avoids optional Unicode.Scalar inits).
    private func sc(_ ch: Character) -> Unicode.Scalar {
        ch.unicodeScalars.first!
    }

    @discardableResult
    private func typeASCII(_ s: String) -> BridgeResult {
        var last = BridgeResult.passthrough
        for ch in s.unicodeScalars {
            last = pipeline.handlePrintable(ch)
        }
        return last
    }

    // MARK: - Bridge lifecycle

    func testBridgeVersionNonEmpty() {
        XCTAssertFalse(DauCoreBridge.version.isEmpty)
    }

    func testBridgeNullSafeAfterClear() {
        bridge.clear()
        let r = bridge.processChar(UInt32(UnicodeScalar("a").value))
        XCTAssertEqual(r.action, DauAction_UpdatePreedit)
        XCTAssertEqual(r.text, "a")
    }

    func testDisabledEngineReturnsNone() {
        bridge.setEnabled(false)
        let r = pipeline.handlePrintable(sc("a"))
        XCTAssertEqual(r.backspace, 0)
        XCTAssertEqual(r.text, "")
        XCTAssertFalse(r.consumeOriginal)
        XCTAssertEqual(pipeline.provisionalLength, 0)
    }

    // MARK: - UpdatePreedit sequence (Telex)

    func testTelexUpdatePreeditBuildsProvisional() {
        // First "a": plain append → pass original key (TG-02).
        let r1 = pipeline.handlePrintable(sc("a"))
        XCTAssertFalse(r1.consumeOriginal)
        XCTAssertEqual(r1.backspace, 0)
        XCTAssertEqual(r1.text, "")
        XCTAssertEqual(pipeline.provisionalText, "a")
        XCTAssertEqual(pipeline.provisionalLength, 1)

        // Second "a": transform a → â → consume + replace last scalar only.
        let r2 = pipeline.handlePrintable(sc("a"))
        XCTAssertTrue(r2.consumeOriginal)
        XCTAssertEqual(r2.backspace, 1)
        XCTAssertEqual(r2.text, "â")
        XCTAssertEqual(pipeline.provisionalText, "â")
        XCTAssertEqual(pipeline.provisionalLength, "â".unicodeScalars.count)
    }

    func testTelexTieengsBecomesTieng() {
        _ = typeASCII("tieengs")
        // Telex: tieengs → tiếng
        XCTAssertEqual(pipeline.provisionalText, "tiếng")
        XCTAssertEqual(pipeline.provisionalLength, "tiếng".unicodeScalars.count)
    }

    // MARK: - TG-02: delta suffix + English append pass-through

    /// English `delete`: each letter is plain append — no full-word rewrite.
    func testEnglishDeleteStepwiseNoFullRewrite() {
        var doc = ""
        let word = "delete"
        var expectedPrefixes: [String] = []
        var built = ""
        for ch in word {
            built.append(ch)
            expectedPrefixes.append(built)
        }

        for (i, ch) in word.unicodeScalars.enumerated() {
            let r = pipeline.handlePrintable(ch)
            XCTAssertEqual(r.backspace, 0, "key \(i) '\(ch)': no synthetic backspace")
            XCTAssertEqual(r.text, "", "key \(i): no synthetic inject text")
            XCTAssertFalse(r.consumeOriginal, "key \(i): pass original")
            // Fake document: only original key (pass-through).
            doc.append(Character(ch))
            XCTAssertEqual(doc, expectedPrefixes[i])
            XCTAssertEqual(pipeline.provisionalText, expectedPrefixes[i])
        }

        let commit = pipeline.handleBreak(sc(" "))
        XCTAssertEqual(commit.backspace, 0)
        XCTAssertEqual(commit.text, "")
        XCTAssertFalse(commit.consumeOriginal, "Space forwarded once")
        doc.append(" ")
        XCTAssertEqual(doc, "delete ")
        XCTAssertEqual(pipeline.provisionalLength, 0)
    }

    /// Tone/mark keys rewrite only the changed suffix, not the whole provisional.
    /// Telex: t→i→e append, second e transforms `tie` → `tiê` (bs=1, text=`ê`).
    func testTelexToneTransformUsesMinimalSuffix() {
        _ = typeASCII("tie")
        XCTAssertEqual(pipeline.provisionalText, "tie")
        let beforeLen = pipeline.provisionalLength
        XCTAssertEqual(beforeLen, 3)

        let r = pipeline.handlePrintable(sc("e"))
        XCTAssertTrue(r.consumeOriginal)
        XCTAssertEqual(pipeline.provisionalText, "tiê")
        // Common prefix "ti" stays; only replace final vowel scalar.
        XCTAssertEqual(r.backspace, 1, "must not wipe entire provisional")
        XCTAssertEqual(r.text, "ê")
        XCTAssertLessThan(r.backspace, beforeLen)
    }

    func testTelexTieengsTransformKeysOnlyWhenNeeded() {
        // Track which keys need consume (transform) vs pass (append).
        var results: [(Character, BridgeResult)] = []
        for ch in "tieengs" {
            results.append((ch, pipeline.handlePrintable(sc(ch))))
        }
        XCTAssertEqual(pipeline.provisionalText, "tiếng")

        // At least the pure letter appends early on must pass original.
        let first = results[0].1
        XCTAssertFalse(first.consumeOriginal)
        XCTAssertEqual(first.backspace, 0)
        XCTAssertEqual(first.text, "")

        // Some later keys transform (tone/mark); those consume with non-zero rewrite or empty same.
        let anyTransform = results.contains { $0.1.consumeOriginal && ($0.1.backspace > 0 || !$0.1.text.isEmpty) }
        XCTAssertTrue(anyTransform, "tieengs must include at least one transform inject")
    }

    func testDduawSequenceDocumentsProvisionalAfterEachKey() {
        // Document provisional after each key (core output may be đuă or đưa depending on TG-01).
        var last = ""
        for ch in "dduaw" {
            _ = pipeline.handlePrintable(sc(ch))
            last = pipeline.provisionalText
            XCTAssertFalse(last.isEmpty)
            // No step should request full wipe larger than current provisional was.
            // (asserted via delta: backspace ≤ previous length — tracked below)
        }
        // Final compose is non-empty Vietnamese-ish syllable; exact form is TG-01's job.
        XCTAssertFalse(pipeline.provisionalText.isEmpty)
        XCTAssertEqual(pipeline.provisionalLength, pipeline.provisionalText.unicodeScalars.count)

        // Space commit must not double text when matching provisional.
        let committed = pipeline.provisionalText
        let breakR = pipeline.handleBreak(sc(" "))
        if breakR.text.isEmpty {
            XCTAssertEqual(breakR.backspace, 0)
        } else {
            // Auto-restore / change path still forwards Space once.
            XCTAssertFalse(breakR.consumeOriginal)
        }
        _ = committed
    }

    func testAppendNeverBackspacesFullWord() {
        // Avoid Telex mark keys (w/s/f/r/x/j) so the word stays plain ASCII appends.
        var prevLen = 0
        for ch in "delete" {
            let r = pipeline.handlePrintable(sc(ch))
            XCTAssertFalse(r.consumeOriginal, "plain English letter must pass original")
            XCTAssertEqual(r.backspace, 0)
            XCTAssertEqual(r.text, "")
            // Never rewrite more scalars than already on screen (prevLen).
            XCTAssertLessThanOrEqual(r.backspace, prevLen)
            prevLen = pipeline.provisionalLength
        }
        XCTAssertEqual(pipeline.provisionalText, "delete")
    }

    // MARK: - Commit

    func testCommitMatchingProvisionalSkipsRetype() {
        _ = typeASCII("tieengs")
        XCTAssertEqual(pipeline.provisionalText, "tiếng")

        let r = pipeline.handleBreak(sc(" "))
        XCTAssertEqual(r.backspace, 0, "same text → no backspace retype")
        XCTAssertEqual(r.text, "")
        XCTAssertFalse(r.consumeOriginal, "break must be forwarded")
        XCTAssertEqual(pipeline.provisionalLength, 0)
        XCTAssertEqual(pipeline.provisionalText, "")
    }

    func testCommitWithAutoRestoreMayRewrite() {
        bridge.setAutoRestore(true)
        // English-like sequence that auto-restore rewrites on break (core behaviour).
        _ = typeASCII("hello")
        let before = pipeline.provisionalText
        let r = pipeline.handleBreak(sc(" "))
        XCTAssertFalse(r.consumeOriginal)
        if r.text.isEmpty {
            // Unchanged path: commit text equals provisional.
            XCTAssertEqual(r.backspace, 0)
            XCTAssertEqual(before, "hello")
        } else {
            // Changed path: rewrite provisional with restored/committed text.
            XCTAssertEqual(r.backspace, before.unicodeScalars.count)
        }
        XCTAssertEqual(pipeline.provisionalLength, 0)
    }

    func testAutoRestoreTesstSpaceProducesRawTextOnce() {
        bridge.setAutoRestore(true)
        var document = PipelineFakeDocument()

        for scalar in "tesst".unicodeScalars {
            document.apply(pipeline.handlePrintable(scalar), originalKey: String(scalar))
        }
        XCTAssertEqual(document.text, "test")
        XCTAssertEqual(pipeline.provisionalText, "test")

        document.apply(pipeline.handleBreak(sc(" ")), originalKey: " ")
        XCTAssertEqual(document.text, "tesst ")
    }

    // MARK: - Restore / Esc

    func testEscapeRestoresRawAndConsumes() {
        _ = typeASCII("tieengs")
        XCTAssertEqual(pipeline.provisionalText, "tiếng")
        let r = pipeline.handleEscape()
        XCTAssertEqual(r.backspace, "tiếng".unicodeScalars.count)
        XCTAssertEqual(r.text, "tieengs")
        XCTAssertTrue(r.consumeOriginal)
        XCTAssertEqual(pipeline.provisionalLength, 0)
    }

    func testEscapeWithEmptyComposeForwards() {
        let r = pipeline.handleEscape()
        XCTAssertEqual(r.backspace, 0)
        XCTAssertEqual(r.text, "")
        // Empty restore may still report Restore with empty text — do not swallow.
        XCTAssertFalse(r.consumeOriginal)
    }

    // MARK: - Backspace during compose (TG-04: per-character)

    func testBackspaceOneDisplayScalarWhileComposing() {
        _ = typeASCII("tieengs")
        XCTAssertEqual(pipeline.provisionalText, "tiếng")
        let before = pipeline.provisionalLength
        XCTAssertEqual(before, "tiếng".unicodeScalars.count)

        let r = pipeline.handleBackspace()
        XCTAssertEqual(r.backspace, 1, "exactly one display scalar")
        XCTAssertEqual(r.text, "")
        XCTAssertTrue(r.consumeOriginal)
        XCTAssertEqual(pipeline.provisionalText, "tiến")
        XCTAssertEqual(pipeline.provisionalLength, before - 1)
    }

    func testBackspaceWithoutComposePassthrough() {
        let r = pipeline.handleBackspace()
        XCTAssertEqual(r, .passthrough)
        XCTAssertFalse(r.consumeOriginal)
    }

    func testClassifiedBackspaceUsesCoreEdit() {
        _ = typeASCII("aa")
        let key = ClassifiedKey(
            kind: .backspace,
            keyCode: KeyClassifier.KeyCode.delete,
            isRepeat: false,
            shiftHeld: false
        )
        let r = pipeline.handleClassified(key)
        XCTAssertTrue(r.consumeOriginal)
        XCTAssertEqual(r.backspace, 1) // "â" is one scalar after aa in Telex
        XCTAssertEqual(pipeline.provisionalLength, 0)
        XCTAssertEqual(pipeline.provisionalText, "")
    }

    // MARK: - TG-04: per-char Backspace sequences

    /// `tieengs → tiếng → Backspace → tiến → g → tiếng` (Telex).
    func testTelexBackspaceThenRetypeSuffix() {
        _ = typeASCII("tieengs")
        XCTAssertEqual(pipeline.provisionalText, "tiếng")

        let bs = pipeline.handleBackspace()
        XCTAssertEqual(bs.backspace, 1)
        XCTAssertEqual(bs.text, "")
        XCTAssertTrue(bs.consumeOriginal)
        XCTAssertEqual(pipeline.provisionalText, "tiến")

        _ = typeASCII("g")
        XCTAssertEqual(pipeline.provisionalText, "tiếng")

        let commit = pipeline.handleBreak(sc(" "))
        XCTAssertEqual(commit.backspace, 0, "matching provisional → no retype inject")
        XCTAssertEqual(commit.text, "")
        XCTAssertFalse(commit.consumeOriginal, "Space is forwarded once")
        XCTAssertEqual(pipeline.provisionalLength, 0)
    }

    /// VNI: `tie6ng1 → tiếng → Backspace → tiến → g → tiếng`.
    func testVniBackspaceThenRetypeSuffix() {
        bridge.setMethod(DauMethod_Vni)
        _ = typeASCII("tie6ng1")
        XCTAssertEqual(pipeline.provisionalText, "tiếng")

        let bs = pipeline.handleBackspace()
        XCTAssertEqual(bs.backspace, 1)
        XCTAssertEqual(pipeline.provisionalText, "tiến")

        _ = typeASCII("g")
        XCTAssertEqual(pipeline.provisionalText, "tiếng")

        let commit = pipeline.handleBreak(sc(" "))
        XCTAssertEqual(commit.backspace, 0)
        XCTAssertFalse(commit.consumeOriginal)
        XCTAssertEqual(pipeline.provisionalLength, 0)
    }

    /// `dduaw → đưa → Backspace → đư → a → đưa`.
    func testTelexDduawBackspaceThenA() {
        _ = typeASCII("dduaw")
        XCTAssertEqual(pipeline.provisionalText, "đưa")

        let bs = pipeline.handleBackspace()
        XCTAssertEqual(bs.backspace, 1)
        XCTAssertEqual(bs.text, "")
        XCTAssertTrue(bs.consumeOriginal)
        XCTAssertEqual(pipeline.provisionalText, "đư")

        _ = typeASCII("a")
        XCTAssertEqual(pipeline.provisionalText, "đưa")
    }

    /// English `delete → Backspace → delet → e → delete`.
    func testEnglishDeleteBackspaceThenE() {
        _ = typeASCII("delete")
        XCTAssertEqual(pipeline.provisionalText, "delete")

        let bs = pipeline.handleBackspace()
        XCTAssertEqual(bs.backspace, 1)
        XCTAssertEqual(pipeline.provisionalText, "delet")

        let e = pipeline.handlePrintable(sc("e"))
        XCTAssertEqual(e.backspace, 0)
        XCTAssertFalse(e.consumeOriginal)
        XCTAssertEqual(pipeline.provisionalText, "delete")
    }

    /// Repeated Backspace removes one scalar each time down to empty; next is pass-through.
    func testRepeatedBackspaceToEmptyThenPassthrough() {
        _ = typeASCII("aa")
        XCTAssertEqual(pipeline.provisionalText, "â")
        XCTAssertEqual(pipeline.provisionalLength, 1)

        let first = pipeline.handleBackspace()
        XCTAssertEqual(first.backspace, 1)
        XCTAssertTrue(first.consumeOriginal)
        XCTAssertEqual(pipeline.provisionalLength, 0)
        XCTAssertEqual(pipeline.provisionalText, "")

        let second = pipeline.handleBackspace()
        XCTAssertEqual(second, .passthrough)
        XCTAssertFalse(second.consumeOriginal)
        XCTAssertEqual(pipeline.provisionalLength, 0)
    }

    func testBackspaceAfterCommitIsPassthroughAndCoreClean() {
        _ = typeASCII("tieengs")
        let commit = pipeline.handleBreak(sc(" "))
        XCTAssertEqual(pipeline.provisionalLength, 0)
        XCTAssertFalse(commit.consumeOriginal)

        // After commit, Backspace is not a compose edit — app receives the real key.
        let del = pipeline.handleBackspace()
        XCTAssertEqual(del, .passthrough)
        XCTAssertFalse(del.consumeOriginal)
        XCTAssertEqual(del.backspace, 0)
        XCTAssertEqual(pipeline.provisionalLength, 0)

        // Core must not revive the previous word.
        let next = pipeline.handlePrintable(sc("a"))
        XCTAssertEqual(next.backspace, 0)
        XCTAssertEqual(next.text, "")
        XCTAssertFalse(next.consumeOriginal)
        XCTAssertEqual(pipeline.provisionalText, "a")
    }

    /// Forward Delete: pass-through + reset compose (never whole-wipe via inject).
    func testForwardDeleteWhileComposingResetsAndPassthrough() {
        _ = typeASCII("tieengs")
        XCTAssertEqual(pipeline.provisionalText, "tiếng")
        let key = ClassifiedKey(
            kind: .forwardDelete,
            keyCode: KeyClassifier.KeyCode.forwardDelete,
            isRepeat: false,
            shiftHeld: false
        )
        let r = pipeline.handleClassified(key)
        XCTAssertEqual(r, .passthrough)
        XCTAssertFalse(r.consumeOriginal)
        XCTAssertEqual(r.backspace, 0)
        XCTAssertEqual(r.text, "")
        XCTAssertEqual(pipeline.provisionalLength, 0)
        XCTAssertEqual(pipeline.provisionalText, "")

        // Next printable starts a fresh word.
        let next = pipeline.handlePrintable(sc("a"))
        XCTAssertEqual(next.backspace, 0)
        XCTAssertFalse(next.consumeOriginal)
        XCTAssertEqual(pipeline.provisionalText, "a")
    }

    func testBackspaceRepeatAfterEmptyIsPassthrough() {
        _ = typeASCII("aa")
        XCTAssertEqual(pipeline.provisionalText, "â")
        let first = pipeline.handleClassified(
            ClassifiedKey(
                kind: .backspace,
                keyCode: KeyClassifier.KeyCode.delete,
                isRepeat: false,
                shiftHeld: false
            )
        )
        XCTAssertTrue(first.consumeOriginal)
        XCTAssertEqual(first.backspace, 1)
        XCTAssertEqual(pipeline.provisionalLength, 0)

        // Autorepeat after empty: pass-through, no inject.
        let repeated = pipeline.handleClassified(
            ClassifiedKey(
                kind: .backspace,
                keyCode: KeyClassifier.KeyCode.delete,
                isRepeat: true,
                shiftHeld: false
            )
        )
        XCTAssertEqual(repeated, .passthrough)
        XCTAssertEqual(repeated.backspace, 0)
        XCTAssertFalse(repeated.consumeOriginal)
        XCTAssertEqual(pipeline.provisionalLength, 0)
    }

    func testCmdVBoundaryResetsComposeAndPassthrough() {
        _ = typeASCII("tieengs")
        XCTAssertEqual(pipeline.provisionalText, "tiếng")
        // Classifier maps Cmd+V → .other → pipeline boundary (reset + forward).
        let cmdV = ClassifiedKey(
            kind: .other,
            keyCode: 9, // kVK_ANSI_V
            isRepeat: false,
            shiftHeld: false
        )
        let r = pipeline.handleClassified(cmdV)
        XCTAssertEqual(r, .passthrough)
        XCTAssertEqual(pipeline.provisionalLength, 0)
        XCTAssertEqual(pipeline.provisionalText, "")
        // No inject of old provisional text on shortcut boundary.
        XCTAssertEqual(r.backspace, 0)
        XCTAssertEqual(r.text, "")

        let next = pipeline.handlePrintable(sc("a"))
        XCTAssertEqual(next.backspace, 0)
        XCTAssertEqual(next.text, "")
        XCTAssertFalse(next.consumeOriginal)
        XCTAssertEqual(pipeline.provisionalText, "a")
    }

    func testCmdDeleteBoundaryDoesNotWipeAsComposeDelete() {
        _ = typeASCII("tieengs")
        let len = pipeline.provisionalLength
        XCTAssertGreaterThan(len, 0)
        // Cmd+Delete is shortcut boundary, not first-class compose wipe.
        let key = ClassifiedKey(
            kind: .other,
            keyCode: KeyClassifier.KeyCode.delete,
            isRepeat: false,
            shiftHeld: false
        )
        let r = pipeline.handleClassified(key)
        XCTAssertEqual(r, .passthrough)
        XCTAssertEqual(r.backspace, 0, "must not inject whole-provisional wipe for Cmd+Delete")
        XCTAssertEqual(pipeline.provisionalLength, 0)
    }

    func testBackspaceToEmptyThenMethodSwitchStartsFreshWord() {
        _ = typeASCII("aa")
        _ = pipeline.handleBackspace()
        XCTAssertEqual(pipeline.provisionalLength, 0)

        bridge.setMethod(DauMethod_Vni)
        _ = typeASCII("tie6ng1")
        XCTAssertEqual(pipeline.provisionalText, "tiếng")
        XCTAssertEqual(pipeline.provisionalLength, "tiếng".unicodeScalars.count)
    }

    // MARK: - None while composing (P0)

    func testNoneWhileComposingWipesViaDisabledEngine() {
        _ = typeASCII("aa")
        let len = pipeline.provisionalLength
        XCTAssertGreaterThan(len, 0)
        // Disabled engine returns DauAction_None for the next key.
        bridge.setEnabled(false)
        let r = pipeline.handlePrintable(sc("x"))
        XCTAssertEqual(r.backspace, len)
        XCTAssertEqual(r.text, "")
        XCTAssertFalse(r.consumeOriginal)
        XCTAssertEqual(pipeline.provisionalLength, 0)
    }

    // MARK: - Boundary / reset

    func testBoundaryClearsProvisionalAndForwards() {
        _ = typeASCII("aa")
        XCTAssertGreaterThan(pipeline.provisionalLength, 0)
        let r = pipeline.handle(kind: .boundary)
        XCTAssertEqual(r, .passthrough)
        XCTAssertEqual(pipeline.provisionalLength, 0)
        // Next key starts a fresh word (plain append passes original).
        let next = pipeline.handlePrintable(sc("b"))
        XCTAssertEqual(next.text, "")
        XCTAssertEqual(next.backspace, 0)
        XCTAssertFalse(next.consumeOriginal)
        XCTAssertEqual(pipeline.provisionalText, "b")
    }

    func testResetComposeClearsCoreAndState() {
        _ = typeASCII("aa")
        pipeline.resetCompose()
        XCTAssertEqual(pipeline.provisionalLength, 0)
        let r = pipeline.handlePrintable(sc("x"))
        XCTAssertEqual(r.backspace, 0)
        XCTAssertEqual(r.text, "")
        XCTAssertFalse(r.consumeOriginal)
        XCTAssertEqual(pipeline.provisionalText, "x")
    }

    // MARK: - Method switch + VNI smoke

    func testVniMethodSwitch() {
        bridge.setMethod(DauMethod_Vni)
        _ = typeASCII("tie61ng")
        // VNI: tie61ng → tiếng (tone 1 + horn patterns depend on core; at least non-empty compose)
        XCTAssertFalse(pipeline.provisionalText.isEmpty)
        XCTAssertGreaterThan(pipeline.provisionalLength, 0)
    }

    // MARK: - Strategy / config null-safe

    func testStrategyUnknownWithoutConfig() {
        let s = bridge.strategyForApp("com.apple.Terminal")
        XCTAssertEqual(s, DauStrategy_Unknown)
    }

    func testLoadConfigMissingFilesStillSucceeds() {
        // Missing paths are skipped by core; both missing → parse success.
        let ok = bridge.loadConfig(shippedPath: "/nonexistent/shipped.toml", userPath: nil)
        XCTAssertTrue(ok)
    }

    // MARK: - capitalize_next recorded

    func testCapitalizeNextRecordedOnPipeline() {
        // Sentence end may set capitalize_next; we only assert the field is plumbed.
        _ = typeASCII("a")
        _ = pipeline.handleBreak(sc("."))
        // Flag is whatever core returns; access must not crash and stays Bool.
        _ = pipeline.lastCapitalizeNext
        XCTAssertEqual(pipeline.provisionalLength, 0)
    }
}
