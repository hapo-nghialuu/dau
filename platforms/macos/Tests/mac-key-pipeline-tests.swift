// Unit tests for MacKeyPipeline + DauCoreBridge against real libdau_core.
// No EventTap; feeds Unicode scalars directly.
import XCTest

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
        let r1 = pipeline.handlePrintable(sc("a"))
        XCTAssertTrue(r1.consumeOriginal)
        XCTAssertEqual(r1.backspace, 0)
        XCTAssertEqual(r1.text, "a")
        XCTAssertEqual(pipeline.provisionalLength, 1)

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

    // MARK: - Delete during compose (P0)

    func testDeleteWhileComposingWipesAndConsumes() {
        _ = typeASCII("tieengs")
        let len = pipeline.provisionalLength
        XCTAssertGreaterThan(len, 0)
        let r = pipeline.handleDelete()
        XCTAssertEqual(r.backspace, len)
        XCTAssertEqual(r.text, "")
        XCTAssertTrue(r.consumeOriginal)
        XCTAssertEqual(pipeline.provisionalLength, 0)
        XCTAssertEqual(pipeline.provisionalText, "")
        // Next printable starts fresh (no leftover core word).
        let next = pipeline.handlePrintable(sc("a"))
        XCTAssertEqual(next.backspace, 0)
        XCTAssertEqual(next.text, "a")
    }

    func testDeleteWithoutComposePassthrough() {
        let r = pipeline.handleDelete()
        XCTAssertEqual(r, .passthrough)
        XCTAssertFalse(r.consumeOriginal)
    }

    func testClassifiedDeleteUsesHandleDelete() {
        _ = typeASCII("aa")
        let key = ClassifiedKey(
            kind: .delete,
            keyCode: KeyClassifier.KeyCode.delete,
            isRepeat: false,
            shiftHeld: false
        )
        let r = pipeline.handleClassified(key)
        XCTAssertTrue(r.consumeOriginal)
        XCTAssertEqual(r.backspace, 1) // "â" is one scalar after aa in Telex
        XCTAssertEqual(pipeline.provisionalLength, 0)
    }

    // MARK: - DELETE-05: full-word wipe → retype → commit (P0 contract = whole provisional)

    /// P0 characterizes delete-during-compose as **whole-provisional wipe**, not per-character.
    func testTelexFullWordDeleteRetypeCommitOnce() {
        _ = typeASCII("tieengs")
        XCTAssertEqual(pipeline.provisionalText, "tiếng")
        let wipeLen = pipeline.provisionalLength
        XCTAssertEqual(wipeLen, "tiếng".unicodeScalars.count)

        let wipe = pipeline.handleDelete()
        XCTAssertEqual(wipe.backspace, wipeLen, "wipe every provisional scalar")
        XCTAssertEqual(wipe.text, "")
        XCTAssertTrue(wipe.consumeOriginal)
        XCTAssertEqual(pipeline.provisionalLength, 0)
        XCTAssertEqual(pipeline.provisionalText, "")

        // Retype full word after wipe — no leftover core / provisional.
        _ = typeASCII("tieengs")
        XCTAssertEqual(pipeline.provisionalText, "tiếng")
        XCTAssertEqual(pipeline.provisionalLength, wipeLen)

        let commit = pipeline.handleBreak(sc(" "))
        XCTAssertEqual(commit.backspace, 0, "matching provisional → no retype inject")
        XCTAssertEqual(commit.text, "")
        XCTAssertFalse(commit.consumeOriginal, "Space is forwarded once")
        XCTAssertEqual(pipeline.provisionalLength, 0)
        XCTAssertEqual(pipeline.provisionalText, "")
    }

    func testVniFullWordDeleteRetypeCommitOnce() {
        bridge.setMethod(DauMethod_Vni)
        _ = typeASCII("tie6ng1")
        XCTAssertEqual(pipeline.provisionalText, "tiếng")
        let wipeLen = pipeline.provisionalLength
        XCTAssertEqual(wipeLen, "tiếng".unicodeScalars.count)

        let wipe = pipeline.handleDelete()
        XCTAssertEqual(wipe.backspace, wipeLen)
        XCTAssertEqual(wipe.text, "")
        XCTAssertTrue(wipe.consumeOriginal)
        XCTAssertEqual(pipeline.provisionalLength, 0)
        XCTAssertEqual(pipeline.provisionalText, "")

        _ = typeASCII("tie6ng1")
        XCTAssertEqual(pipeline.provisionalText, "tiếng")

        let commit = pipeline.handleBreak(sc(" "))
        XCTAssertEqual(commit.backspace, 0)
        XCTAssertEqual(commit.text, "")
        XCTAssertFalse(commit.consumeOriginal)
        XCTAssertEqual(pipeline.provisionalLength, 0)
    }

    func testDeleteAfterCommitIsPassthroughAndCoreClean() {
        _ = typeASCII("tieengs")
        let commit = pipeline.handleBreak(sc(" "))
        XCTAssertEqual(pipeline.provisionalLength, 0)
        XCTAssertFalse(commit.consumeOriginal)

        // After commit, Delete is not a compose wipe — app receives the real key.
        let del = pipeline.handleDelete()
        XCTAssertEqual(del, .passthrough)
        XCTAssertFalse(del.consumeOriginal)
        XCTAssertEqual(del.backspace, 0)
        XCTAssertEqual(pipeline.provisionalLength, 0)

        // Core must not revive the previous word.
        let next = pipeline.handlePrintable(sc("a"))
        XCTAssertEqual(next.backspace, 0)
        XCTAssertEqual(next.text, "a")
        XCTAssertEqual(pipeline.provisionalText, "a")
    }

    func testForwardDeleteWhileComposingWipesSameAsBackspace() {
        _ = typeASCII("tieengs")
        let len = pipeline.provisionalLength
        let key = ClassifiedKey(
            kind: .delete,
            keyCode: KeyClassifier.KeyCode.forwardDelete,
            isRepeat: false,
            shiftHeld: false
        )
        let r = pipeline.handleClassified(key)
        XCTAssertTrue(r.consumeOriginal)
        XCTAssertEqual(r.backspace, len)
        XCTAssertEqual(r.text, "")
        XCTAssertEqual(pipeline.provisionalLength, 0)
    }

    func testDeleteRepeatAfterWipeIsPassthroughNoDoubleWipe() {
        _ = typeASCII("aa")
        XCTAssertEqual(pipeline.provisionalText, "â")
        let first = pipeline.handleClassified(
            ClassifiedKey(
                kind: .delete,
                keyCode: KeyClassifier.KeyCode.delete,
                isRepeat: false,
                shiftHeld: false
            )
        )
        XCTAssertTrue(first.consumeOriginal)
        XCTAssertEqual(first.backspace, 1)
        XCTAssertEqual(pipeline.provisionalLength, 0)

        // Autorepeat while holding Delete after wipe: no second provisional wipe inject.
        let repeated = pipeline.handleClassified(
            ClassifiedKey(
                kind: .delete,
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
        XCTAssertEqual(next.text, "a")
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

    func testDeleteThenMethodSwitchStartsFreshWord() {
        _ = typeASCII("tieengs")
        _ = pipeline.handleDelete()
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
        // Next key starts a fresh word.
        let next = pipeline.handlePrintable(sc("b"))
        XCTAssertEqual(next.text, "b")
        XCTAssertEqual(next.backspace, 0)
    }

    func testResetComposeClearsCoreAndState() {
        _ = typeASCII("aa")
        pipeline.resetCompose()
        XCTAssertEqual(pipeline.provisionalLength, 0)
        let r = pipeline.handlePrintable(sc("x"))
        XCTAssertEqual(r.backspace, 0)
        XCTAssertEqual(r.text, "x")
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
