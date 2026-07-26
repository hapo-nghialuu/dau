// Unit tests for DauResultMapper (core-owned display delta + TG-02).
// Fake document asserts final text after each key, not only BridgeResult tuples.
import XCTest

/// Applies `BridgeResult` (+ optional original key on pass-through) to a document buffer.
private struct FakeDocument {
    var text: String = ""

    mutating func apply(result: BridgeResult, originalKey: String? = nil) {
        if result.backspace > 0 {
            let scalars = Array(text.unicodeScalars)
            let keep = max(0, scalars.count - result.backspace)
            text = String(String.UnicodeScalarView(scalars.prefix(keep)))
        }
        if !result.text.isEmpty {
            text += result.text
        }
        // Plain append: original key reaches the app (consumeOriginal = false).
        if !result.consumeOriginal, let key = originalKey, !key.isEmpty {
            text += key
        }
    }
}

final class DauResultMapperTests: XCTestCase {
    private var provisionalText = ""
    private var provisionalLength = 0

    override func setUp() {
        super.setUp()
        provisionalText = ""
        provisionalLength = 0
    }

    /// Map a core-style **delta** (not full preedit).
    private func map(
        action: DauAction,
        backspace: Int = 0,
        text: String,
        capitalizeNext: Bool = false
    ) -> BridgeResult {
        DauResultMapper.map(
            action: action,
            backspace: backspace,
            text: text,
            capitalizeNext: capitalizeNext,
            provisionalText: &provisionalText,
            provisionalLength: &provisionalLength
        )
    }

    // MARK: - None

    func testNoneWithEmptyProvisionalForwards() {
        let r = map(action: DauAction_None, text: "ignored")
        XCTAssertEqual(r.backspace, 0)
        XCTAssertEqual(r.text, "")
        XCTAssertFalse(r.consumeOriginal)
        XCTAssertEqual(provisionalLength, 0)
    }

    /// P0: None while composing → wipe provisional (bs=oldLen), clear state, forward key.
    func testNoneWhileComposingWipesProvisional() {
        provisionalText = "đã"
        provisionalLength = 2
        let r = map(action: DauAction_None, text: "ignored")
        XCTAssertEqual(r.backspace, 2)
        XCTAssertEqual(r.text, "")
        XCTAssertFalse(r.consumeOriginal)
        XCTAssertEqual(provisionalText, "")
        XCTAssertEqual(provisionalLength, 0)
    }

    // MARK: - UpdatePreedit: plain append (TG-02)

    func testUpdatePreeditFirstCharPassesOriginal() {
        let r = map(action: DauAction_UpdatePreedit, backspace: 0, text: "a")
        XCTAssertEqual(r.backspace, 0)
        XCTAssertEqual(r.text, "")
        XCTAssertFalse(r.consumeOriginal, "first scalar is plain append → pass physical key")
        XCTAssertEqual(provisionalText, "a")
        XCTAssertEqual(provisionalLength, 1)
    }

    func testUpdatePreeditEnglishDeleteStepwiseNoRewrite() {
        var doc = FakeDocument()
        let keys = ["d", "e", "l", "e", "t", "e"]
        var expected = ""
        for (i, key) in keys.enumerated() {
            let r = map(action: DauAction_UpdatePreedit, backspace: 0, text: key)
            XCTAssertEqual(r.backspace, 0, "step \(i) (\(key)): no synthetic backspace")
            XCTAssertEqual(r.text, "", "step \(i): no synthetic retype")
            XCTAssertFalse(r.consumeOriginal, "step \(i): pass original key")
            doc.apply(result: r, originalKey: key)
            expected += key
            XCTAssertEqual(doc.text, expected, "document after \(expected)")
            XCTAssertEqual(provisionalText, expected)
            XCTAssertEqual(provisionalLength, expected.unicodeScalars.count)
        }
        XCTAssertEqual(doc.text, "delete")
    }

    func testUpdatePreeditSimpleAppendVNLetterPassesOriginal() {
        provisionalText = "đ"
        provisionalLength = 1
        let r = map(action: DauAction_UpdatePreedit, backspace: 0, text: "u")
        XCTAssertEqual(r.backspace, 0)
        XCTAssertEqual(r.text, "")
        XCTAssertFalse(r.consumeOriginal)
        XCTAssertEqual(provisionalText, "đu")
        XCTAssertEqual(provisionalLength, 2)
    }

    // MARK: - UpdatePreedit: tone / mark transform (core delta)

    func testUpdatePreeditToneTransformMinimalSuffix() {
        // "tieen" → "tiên": core delta backspace=3, insert "ên".
        provisionalText = "tieen"
        provisionalLength = 5
        let r = map(action: DauAction_UpdatePreedit, backspace: 3, text: "ên")
        XCTAssertEqual(r.backspace, 3)
        XCTAssertEqual(r.text, "ên")
        XCTAssertTrue(r.consumeOriginal)
        XCTAssertEqual(provisionalText, "tiên")
        XCTAssertEqual(provisionalLength, "tiên".unicodeScalars.count)
    }

    func testUpdatePreeditAaToCircumflexMinimalRewrite() {
        provisionalText = "a"
        provisionalLength = 1
        let r = map(action: DauAction_UpdatePreedit, backspace: 1, text: "â")
        XCTAssertEqual(r.backspace, 1)
        XCTAssertEqual(r.text, "â")
        XCTAssertTrue(r.consumeOriginal)
        XCTAssertEqual(provisionalText, "â")
        XCTAssertEqual(provisionalLength, 1)
    }

    func testUpdatePreeditToneOnLastVowelMinimalSuffix() {
        // "hoa" → "hoá": backspace=1, insert "á".
        provisionalText = "hoa"
        provisionalLength = 3
        let r = map(action: DauAction_UpdatePreedit, backspace: 1, text: "á")
        XCTAssertEqual(r.backspace, 1)
        XCTAssertEqual(r.text, "á")
        XCTAssertTrue(r.consumeOriginal)
        XCTAssertEqual(provisionalText, "hoá")
    }

    func testUpdatePreeditDoesNotWipeUnchangedPrefix() {
        provisionalText = "tieen"
        provisionalLength = 5
        var doc = FakeDocument()
        doc.text = "tieen"
        let r = map(action: DauAction_UpdatePreedit, backspace: 3, text: "ên")
        doc.apply(result: r)
        XCTAssertEqual(doc.text, "tiên")
        XCTAssertLessThan(r.backspace, 5)
        XCTAssertEqual(r.backspace, 3)
    }

    func testUpdatePreeditCountsUnicodeScalarsNotUTF16() {
        // "🇺🇸" is two regional-indicator scalars (surrogate pairs in UTF-16).
        provisionalText = "x"
        provisionalLength = 1
        let flag = "🇺🇸"
        let r = map(action: DauAction_UpdatePreedit, backspace: 1, text: flag)
        XCTAssertEqual(r.backspace, 1)
        XCTAssertEqual(r.text, flag)
        XCTAssertEqual(provisionalLength, flag.unicodeScalars.count)
        XCTAssertEqual(provisionalLength, 2)
    }

    func testUpdatePreeditSameTextConsumesWithoutRewrite() {
        provisionalText = "abc"
        provisionalLength = 3
        let r = map(action: DauAction_UpdatePreedit, backspace: 0, text: "")
        XCTAssertEqual(r.backspace, 0)
        XCTAssertEqual(r.text, "")
        XCTAssertTrue(r.consumeOriginal, "no-op display still consumed (core owned the key)")
        XCTAssertEqual(provisionalText, "abc")
    }

    func testUpdatePreeditMultiScalarAppendConsumesAndInjectsSuffix() {
        provisionalText = "ab"
        provisionalLength = 2
        let r = map(action: DauAction_UpdatePreedit, backspace: 0, text: "cd")
        XCTAssertEqual(r.backspace, 0)
        XCTAssertEqual(r.text, "cd")
        XCTAssertTrue(r.consumeOriginal, "multi-scalar append injects suffix and consumes key")
        XCTAssertEqual(provisionalText, "abcd")
        XCTAssertEqual(provisionalLength, 4)
    }

    // MARK: - Fake document: transform sequences

    func testFakeDocumentToneSequenceAa() {
        var doc = FakeDocument()
        // a
        var r = map(action: DauAction_UpdatePreedit, backspace: 0, text: "a")
        doc.apply(result: r, originalKey: "a")
        XCTAssertEqual(doc.text, "a")
        // second a → â
        r = map(action: DauAction_UpdatePreedit, backspace: 1, text: "â")
        doc.apply(result: r, originalKey: "a")
        XCTAssertEqual(doc.text, "â")
        XCTAssertTrue(r.consumeOriginal)
        XCTAssertEqual(r.backspace, 1)
        XCTAssertEqual(r.text, "â")
    }

    func testFakeDocumentTieToTieCircumflex() {
        // Mock core deltas for Telex second-e: t→ti→tie→tiê
        var doc = FakeDocument()
        for key in ["t", "i", "e"] {
            let r = map(action: DauAction_UpdatePreedit, backspace: 0, text: key)
            doc.apply(result: r, originalKey: key)
            XCTAssertFalse(r.consumeOriginal)
        }
        XCTAssertEqual(doc.text, "tie")
        // Transform: "tie" → "tiê" (backspace 1, insert ê)
        let transform = map(action: DauAction_UpdatePreedit, backspace: 1, text: "ê")
        doc.apply(result: transform)
        XCTAssertEqual(doc.text, "tiê")
        XCTAssertTrue(transform.consumeOriginal)
        XCTAssertEqual(transform.backspace, 1)
        XCTAssertEqual(transform.text, "ê")
    }

    /// Mock dduaw-style suffix change: đua → đưa (backspace 2, insert ưa).
    func testFakeDocumentDduawStyleSuffixDelta() {
        var doc = FakeDocument()
        doc.text = "đua"
        provisionalText = "đua"
        provisionalLength = 3
        let r = map(action: DauAction_UpdatePreedit, backspace: 2, text: "ưa")
        doc.apply(result: r)
        XCTAssertEqual(doc.text, "đưa")
        XCTAssertEqual(r.backspace, 2)
        XCTAssertEqual(r.text, "ưa")
        XCTAssertTrue(r.consumeOriginal)
        XCTAssertLessThan(r.backspace, 3, "must not full-wipe three scalars when only suffix changes")
    }

    // MARK: - Commit (core delta)

    func testCommitUnchangedSkipsRetype() {
        provisionalText = "tiếng"
        provisionalLength = "tiếng".unicodeScalars.count
        // Core: commit equals compose → empty delta.
        let r = map(action: DauAction_Commit, backspace: 0, text: "")
        XCTAssertEqual(r.backspace, 0)
        XCTAssertEqual(r.text, "")
        XCTAssertFalse(r.consumeOriginal) // forward break
        XCTAssertEqual(provisionalText, "")
        XCTAssertEqual(provisionalLength, 0)
    }

    func testCommitChangedRewritesProvisional() {
        provisionalText = "hellô"
        provisionalLength = provisionalText.unicodeScalars.count
        // Common prefix "hell", replace "ô" with "o" — or full replace.
        let r = map(action: DauAction_Commit, backspace: 1, text: "o")
        XCTAssertEqual(r.backspace, 1)
        XCTAssertEqual(r.text, "o")
        XCTAssertFalse(r.consumeOriginal)
        XCTAssertEqual(provisionalLength, 0)
        XCTAssertEqual(provisionalText, "")
    }

    func testCommitEmptyWithProvisionalDeletesOnly() {
        provisionalText = "ab"
        provisionalLength = 2
        let r = map(action: DauAction_Commit, backspace: 2, text: "")
        XCTAssertEqual(r.backspace, 2)
        XCTAssertEqual(r.text, "")
        XCTAssertFalse(r.consumeOriginal)
        XCTAssertEqual(provisionalLength, 0)
    }

    func testCommitAfterAppendEnglishDeleteForwardsSpaceOnce() {
        var doc = FakeDocument()
        for key in ["d", "e", "l", "e", "t", "e"] {
            let r = map(action: DauAction_UpdatePreedit, backspace: 0, text: key)
            doc.apply(result: r, originalKey: key)
        }
        XCTAssertEqual(doc.text, "delete")
        let commit = map(action: DauAction_Commit, backspace: 0, text: "")
        doc.apply(result: commit, originalKey: " ")
        XCTAssertEqual(commit.backspace, 0)
        XCTAssertEqual(commit.text, "")
        XCTAssertFalse(commit.consumeOriginal)
        XCTAssertEqual(doc.text, "delete ")
        XCTAssertEqual(provisionalLength, 0)
    }

    func testCommitAutoRestoreRawLongerThanDisplayedReplacesDocumentOnce() {
        var doc = FakeDocument(text: "test")
        provisionalText = "test"
        provisionalLength = "test".unicodeScalars.count

        // "test" → "tesst": common "tes", backspace 1, insert "st"
        let result = map(action: DauAction_Commit, backspace: 1, text: "st")
        doc.apply(result: result, originalKey: " ")

        XCTAssertEqual(doc.text, "tesst ")
    }

    func testCommitAutoRestoreRawShorterThanDisplayedReplacesDocumentOnce() {
        var doc = FakeDocument(text: "test")
        provisionalText = "test"
        provisionalLength = "test".unicodeScalars.count

        // "test" → "tes": backspace 1, empty insert
        let result = map(action: DauAction_Commit, backspace: 1, text: "")
        doc.apply(result: result, originalKey: " ")

        XCTAssertEqual(doc.text, "tes ")
    }

    func testCommitAutoRestoreEqualTextForwardsSpaceOnce() {
        var doc = FakeDocument(text: "test")
        provisionalText = "test"
        provisionalLength = "test".unicodeScalars.count

        let result = map(action: DauAction_Commit, backspace: 0, text: "")
        doc.apply(result: result, originalKey: " ")

        XCTAssertEqual(doc.text, "test ")
    }

    func testCommitAutoRestoreVietnameseRawUsesDisplayedScalarCount() {
        var doc = FakeDocument(text: "tiếng")
        provisionalText = "tiếng"
        provisionalLength = provisionalText.unicodeScalars.count

        // "tiếng" → "tieengs": common "ti", backspace 3, insert "eengs"
        let result = map(action: DauAction_Commit, backspace: 3, text: "eengs")
        doc.apply(result: result, originalKey: " ")

        XCTAssertEqual(doc.text, "tieengs ")
    }

    func testCommitAutoRestoreIgnoresStaleLengthAndUsesDisplayedText() {
        var doc = FakeDocument(text: "test")
        provisionalText = "test"
        provisionalLength = 3 // stale host length; core delta is authoritative

        let result = map(action: DauAction_Commit, backspace: 1, text: "st")
        doc.apply(result: result, originalKey: " ")

        XCTAssertEqual(doc.text, "tesst ")
    }

    // MARK: - Restore

    func testRestoreUsesCoreDeltaAndKeepsProvisionalInSync() {
        var doc = FakeDocument(text: "tiếng")
        provisionalText = "tiếng"
        provisionalLength = "tiếng".unicodeScalars.count
        // "tiếng" → "tieengs": common "ti", backspace 3, insert "eengs"
        let r = map(action: DauAction_Restore, backspace: 3, text: "eengs")
        doc.apply(result: r)
        XCTAssertEqual(r.backspace, 3)
        XCTAssertEqual(r.text, "eengs")
        XCTAssertTrue(r.consumeOriginal)
        XCTAssertEqual(doc.text, "tieengs")
        // Keep provisional in sync with core pass-through buffer (delta contract).
        XCTAssertEqual(provisionalText, "tieengs")
        XCTAssertEqual(provisionalLength, "tieengs".unicodeScalars.count)
    }

    func testRestoreEmptyForwardsEsc() {
        let r = map(action: DauAction_Restore, backspace: 0, text: "")
        XCTAssertEqual(r.backspace, 0)
        XCTAssertEqual(r.text, "")
        XCTAssertFalse(r.consumeOriginal)
    }

    // MARK: - capitalize_next passthrough

    func testCapitalizeNextEchoedNotUsedAsState() {
        let r = map(action: DauAction_Commit, backspace: 0, text: "A", capitalizeNext: true)
        XCTAssertTrue(r.capitalizeNext)
        XCTAssertEqual(provisionalLength, 0)
    }

    // MARK: - CoreMappedResult convenience

    func testMapCoreMappedResult() {
        let core = CoreMappedResult(
            action: DauAction_UpdatePreedit,
            backspace: 0,
            text: "ơ",
            capitalizeNext: false
        )
        let r = DauResultMapper.map(
            core,
            provisionalText: &provisionalText,
            provisionalLength: &provisionalLength
        )
        // First scalar: pass-through append.
        XCTAssertEqual(r.text, "")
        XCTAssertFalse(r.consumeOriginal)
        XCTAssertEqual(provisionalText, "ơ")
        XCTAssertEqual(provisionalLength, 1)
    }

    // MARK: - Helpers

    func testApplyDelta() {
        XCTAssertEqual(
            DauResultMapper.applyDelta(to: "tieen", backspace: 3, insert: "ên"),
            "tiên"
        )
        XCTAssertEqual(
            DauResultMapper.applyDelta(to: "a", backspace: 1, insert: "â"),
            "â"
        )
        XCTAssertEqual(
            DauResultMapper.applyDelta(to: "delet", backspace: 0, insert: "e"),
            "delete"
        )
        XCTAssertEqual(
            DauResultMapper.applyDelta(to: "ab", backspace: 2, insert: ""),
            ""
        )
    }
}
