// Unit tests for DauResultMapper (§2.4 + TG-02). No EventTap; pure provisional state.
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

    private func map(
        action: DauAction,
        text: String,
        capitalizeNext: Bool = false
    ) -> BridgeResult {
        DauResultMapper.map(
            action: action,
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
        let r = map(action: DauAction_UpdatePreedit, text: "a")
        XCTAssertEqual(r.backspace, 0)
        XCTAssertEqual(r.text, "")
        XCTAssertFalse(r.consumeOriginal, "first scalar is plain append → pass physical key")
        XCTAssertEqual(provisionalText, "a")
        XCTAssertEqual(provisionalLength, 1)
    }

    func testUpdatePreeditEnglishDeleteStepwiseNoRewrite() {
        var doc = FakeDocument()
        let steps = ["d", "de", "del", "dele", "delet", "delete"]
        var expected = ""
        for (i, preedit) in steps.enumerated() {
            let key = String(preedit.suffix(1))
            let r = map(action: DauAction_UpdatePreedit, text: preedit)
            XCTAssertEqual(r.backspace, 0, "step \(i) (\(preedit)): no synthetic backspace")
            XCTAssertEqual(r.text, "", "step \(i): no synthetic retype")
            XCTAssertFalse(r.consumeOriginal, "step \(i): pass original key")
            doc.apply(result: r, originalKey: key)
            expected += key
            XCTAssertEqual(doc.text, expected, "document after \(preedit)")
            XCTAssertEqual(provisionalText, preedit)
            XCTAssertEqual(provisionalLength, preedit.unicodeScalars.count)
        }
        XCTAssertEqual(doc.text, "delete")
    }

    func testUpdatePreeditSimpleAppendVNLetterPassesOriginal() {
        provisionalText = "đ"
        provisionalLength = 1
        let r = map(action: DauAction_UpdatePreedit, text: "đu")
        XCTAssertEqual(r.backspace, 0)
        XCTAssertEqual(r.text, "")
        XCTAssertFalse(r.consumeOriginal)
        XCTAssertEqual(provisionalText, "đu")
        XCTAssertEqual(provisionalLength, 2)
    }

    // MARK: - UpdatePreedit: tone / mark transform (minimal suffix)

    func testUpdatePreeditToneTransformMinimalSuffix() {
        // "tieen" → "tiên": common prefix "ti", delete "een" (3), inject "ên".
        provisionalText = "tieen"
        provisionalLength = 5
        let r = map(action: DauAction_UpdatePreedit, text: "tiên")
        XCTAssertEqual(r.backspace, 3)
        XCTAssertEqual(r.text, "ên")
        XCTAssertTrue(r.consumeOriginal)
        XCTAssertEqual(provisionalText, "tiên")
        XCTAssertEqual(provisionalLength, "tiên".unicodeScalars.count)
    }

    func testUpdatePreeditAaToCircumflexMinimalRewrite() {
        provisionalText = "a"
        provisionalLength = 1
        let r = map(action: DauAction_UpdatePreedit, text: "â")
        XCTAssertEqual(r.backspace, 1)
        XCTAssertEqual(r.text, "â")
        XCTAssertTrue(r.consumeOriginal)
        XCTAssertEqual(provisionalText, "â")
        XCTAssertEqual(provisionalLength, 1)
    }

    func testUpdatePreeditToneOnLastVowelMinimalSuffix() {
        // "hoa" → "hoá": common "ho", replace "a" with "á".
        provisionalText = "hoa"
        provisionalLength = 3
        let r = map(action: DauAction_UpdatePreedit, text: "hoá")
        XCTAssertEqual(r.backspace, 1)
        XCTAssertEqual(r.text, "á")
        XCTAssertTrue(r.consumeOriginal)
        XCTAssertEqual(provisionalText, "hoá")
    }

    func testUpdatePreeditDoesNotWipeUnchangedPrefix() {
        // Full wipe would be backspace=5; delta must keep "ti" on screen.
        provisionalText = "tieen"
        provisionalLength = 5
        var doc = FakeDocument()
        doc.text = "tieen"
        let r = map(action: DauAction_UpdatePreedit, text: "tiên")
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
        let r = map(action: DauAction_UpdatePreedit, text: flag)
        // "x" vs flag: common 0 → full replace of one scalar with two.
        XCTAssertEqual(r.backspace, 1)
        XCTAssertEqual(r.text, flag)
        XCTAssertEqual(provisionalLength, flag.unicodeScalars.count)
        XCTAssertEqual(provisionalLength, 2)
    }

    func testUpdatePreeditSameTextConsumesWithoutRewrite() {
        provisionalText = "abc"
        provisionalLength = 3
        let r = map(action: DauAction_UpdatePreedit, text: "abc")
        XCTAssertEqual(r.backspace, 0)
        XCTAssertEqual(r.text, "")
        XCTAssertTrue(r.consumeOriginal, "no-op display still consumed (core owned the key)")
        XCTAssertEqual(provisionalText, "abc")
    }

    // MARK: - Fake document: transform sequences

    func testFakeDocumentToneSequenceAa() {
        var doc = FakeDocument()
        // a
        var r = map(action: DauAction_UpdatePreedit, text: "a")
        doc.apply(result: r, originalKey: "a")
        XCTAssertEqual(doc.text, "a")
        // second a → â
        r = map(action: DauAction_UpdatePreedit, text: "â")
        doc.apply(result: r, originalKey: "a")
        XCTAssertEqual(doc.text, "â")
        XCTAssertTrue(r.consumeOriginal)
        XCTAssertEqual(r.backspace, 1)
        XCTAssertEqual(r.text, "â")
    }

    func testFakeDocumentTieToTieCircumflex() {
        // Mock core transitions for Telex second-e: t→ti→tie→tiê
        var doc = FakeDocument()
        for (preedit, key) in [("t", "t"), ("ti", "i"), ("tie", "e")] {
            let r = map(action: DauAction_UpdatePreedit, text: preedit)
            doc.apply(result: r, originalKey: key)
            XCTAssertEqual(doc.text, preedit)
            XCTAssertFalse(r.consumeOriginal)
        }
        // Transform: "tie" → "tiê" (common "ti", replace "e" with "ê")
        let transform = map(action: DauAction_UpdatePreedit, text: "tiê")
        doc.apply(result: transform)
        XCTAssertEqual(doc.text, "tiê")
        XCTAssertTrue(transform.consumeOriginal)
        XCTAssertEqual(transform.backspace, 1)
        XCTAssertEqual(transform.text, "ê")
    }

    /// Mock dduaw-style suffix change: đua → đưa (common "đ", replace "ua" with "ưa").
    func testFakeDocumentDduawStyleSuffixDelta() {
        var doc = FakeDocument()
        doc.text = "đua"
        provisionalText = "đua"
        provisionalLength = 3
        let r = map(action: DauAction_UpdatePreedit, text: "đưa")
        doc.apply(result: r)
        XCTAssertEqual(doc.text, "đưa")
        XCTAssertEqual(r.backspace, 2)
        XCTAssertEqual(r.text, "ưa")
        XCTAssertTrue(r.consumeOriginal)
        XCTAssertLessThan(r.backspace, 3, "must not full-wipe three scalars when only suffix changes")
    }

    // MARK: - Commit

    func testCommitUnchangedSkipsRetype() {
        provisionalText = "tiếng"
        provisionalLength = "tiếng".unicodeScalars.count
        let r = map(action: DauAction_Commit, text: "tiếng")
        XCTAssertEqual(r.backspace, 0)
        XCTAssertEqual(r.text, "")
        XCTAssertFalse(r.consumeOriginal) // forward break
        XCTAssertEqual(provisionalText, "")
        XCTAssertEqual(provisionalLength, 0)
    }

    func testCommitChangedRewritesProvisional() {
        provisionalText = "hellô" // composed form that auto-restore may replace
        provisionalLength = provisionalText.unicodeScalars.count
        let r = map(action: DauAction_Commit, text: "hello")
        XCTAssertEqual(r.backspace, "hellô".unicodeScalars.count)
        XCTAssertEqual(r.text, "hello")
        XCTAssertFalse(r.consumeOriginal)
        XCTAssertEqual(provisionalLength, 0)
        XCTAssertEqual(provisionalText, "")
    }

    func testCommitEmptyWithProvisionalDeletesOnly() {
        provisionalText = "ab"
        provisionalLength = 2
        let r = map(action: DauAction_Commit, text: "")
        XCTAssertEqual(r.backspace, 2)
        XCTAssertEqual(r.text, "")
        XCTAssertFalse(r.consumeOriginal)
        XCTAssertEqual(provisionalLength, 0)
    }

    func testCommitAfterAppendEnglishDeleteForwardsSpaceOnce() {
        var doc = FakeDocument()
        for (preedit, key) in [
            ("d", "d"), ("de", "e"), ("del", "l"),
            ("dele", "e"), ("delet", "t"), ("delete", "e"),
        ] {
            let r = map(action: DauAction_UpdatePreedit, text: preedit)
            doc.apply(result: r, originalKey: key)
        }
        XCTAssertEqual(doc.text, "delete")
        let commit = map(action: DauAction_Commit, text: "delete")
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

        let result = map(action: DauAction_Commit, text: "tesst")
        doc.apply(result: result, originalKey: " ")

        XCTAssertEqual(doc.text, "tesst ")
    }

    func testCommitAutoRestoreRawShorterThanDisplayedReplacesDocumentOnce() {
        var doc = FakeDocument(text: "test")
        provisionalText = "test"
        provisionalLength = "test".unicodeScalars.count

        let result = map(action: DauAction_Commit, text: "tes")
        doc.apply(result: result, originalKey: " ")

        XCTAssertEqual(doc.text, "tes ")
    }

    func testCommitAutoRestoreEqualTextForwardsSpaceOnce() {
        var doc = FakeDocument(text: "test")
        provisionalText = "test"
        provisionalLength = "test".unicodeScalars.count

        let result = map(action: DauAction_Commit, text: "test")
        doc.apply(result: result, originalKey: " ")

        XCTAssertEqual(doc.text, "test ")
    }

    func testCommitAutoRestoreVietnameseRawUsesDisplayedScalarCount() {
        var doc = FakeDocument(text: "tiếng")
        provisionalText = "tiếng"
        provisionalLength = provisionalText.unicodeScalars.count

        let result = map(action: DauAction_Commit, text: "tieengs")
        doc.apply(result: result, originalKey: " ")

        XCTAssertEqual(doc.text, "tieengs ")
    }

    func testCommitAutoRestoreIgnoresStaleLengthAndUsesDisplayedText() {
        var doc = FakeDocument(text: "test")
        provisionalText = "test"
        provisionalLength = 3 // Reproduces the observed t + raw replacement.

        let result = map(action: DauAction_Commit, text: "tesst")
        doc.apply(result: result, originalKey: " ")

        XCTAssertEqual(doc.text, "tesst ")
    }

    // MARK: - Restore

    func testRestoreUsesProvisionalLengthPlusRaw() {
        var doc = FakeDocument(text: "tiếng")
        provisionalText = "tiếng"
        provisionalLength = "tiếng".unicodeScalars.count
        let r = map(action: DauAction_Restore, text: "tieengs")
        doc.apply(result: r)
        XCTAssertEqual(r.backspace, "tiếng".unicodeScalars.count)
        XCTAssertEqual(r.text, "tieengs")
        XCTAssertTrue(r.consumeOriginal)
        XCTAssertEqual(doc.text, "tieengs")
        XCTAssertEqual(provisionalText, "")
        XCTAssertEqual(provisionalLength, 0)
    }

    func testRestoreEmptyForwardsEsc() {
        let r = map(action: DauAction_Restore, text: "")
        XCTAssertEqual(r.backspace, 0)
        XCTAssertEqual(r.text, "")
        XCTAssertFalse(r.consumeOriginal)
    }

    // MARK: - capitalize_next passthrough

    func testCapitalizeNextEchoedNotUsedAsState() {
        let r = map(action: DauAction_Commit, text: "A", capitalizeNext: true)
        XCTAssertTrue(r.capitalizeNext)
        // Mapper must not invent second capitalization state beyond the flag.
        XCTAssertEqual(provisionalLength, 0)
    }

    // MARK: - CoreMappedResult convenience

    func testMapCoreMappedResult() {
        let core = CoreMappedResult(
            action: DauAction_UpdatePreedit,
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

    func testCommonPrefixScalarCount() {
        XCTAssertEqual(DauResultMapper.commonPrefixScalarCount("tieen", "tiên"), 2)
        XCTAssertEqual(DauResultMapper.commonPrefixScalarCount("", "a"), 0)
        XCTAssertEqual(DauResultMapper.commonPrefixScalarCount("abc", "abc"), 3)
        XCTAssertEqual(DauResultMapper.commonPrefixScalarCount("delet", "delete"), 5)
    }

    func testScalarSuffix() {
        XCTAssertEqual(DauResultMapper.scalarSuffix("tiên", droppingFirst: 2), "ên")
        XCTAssertEqual(DauResultMapper.scalarSuffix("a", droppingFirst: 0), "a")
        XCTAssertEqual(DauResultMapper.scalarSuffix("ab", droppingFirst: 2), "")
    }
}
