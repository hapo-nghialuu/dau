// Unit tests for DauResultMapper (§2.4). No EventTap; pure provisional state.
import XCTest

final class DauResultMapperTests: XCTestCase {
    private var provisionalText = ""
    private var provisionalLength = 0

    override func setUp() {
        super.setUp()
        provisionalText = ""
        provisionalLength = 0
    }

    // MARK: - None

    func testNoneWithEmptyProvisionalForwards() {
        let r = DauResultMapper.map(
            action: DauAction_None,
            text: "ignored",
            provisionalText: &provisionalText,
            provisionalLength: &provisionalLength
        )
        XCTAssertEqual(r.backspace, 0)
        XCTAssertEqual(r.text, "")
        XCTAssertFalse(r.consumeOriginal)
        XCTAssertEqual(provisionalLength, 0)
    }

    /// P0: None while composing → wipe provisional (bs=oldLen), clear state, forward key.
    func testNoneWhileComposingWipesProvisional() {
        provisionalText = "đã"
        provisionalLength = 2
        let r = DauResultMapper.map(
            action: DauAction_None,
            text: "ignored",
            provisionalText: &provisionalText,
            provisionalLength: &provisionalLength
        )
        XCTAssertEqual(r.backspace, 2)
        XCTAssertEqual(r.text, "")
        XCTAssertFalse(r.consumeOriginal)
        XCTAssertEqual(provisionalText, "")
        XCTAssertEqual(provisionalLength, 0)
    }

    // MARK: - UpdatePreedit

    func testUpdatePreeditFirstChar() {
        let r = DauResultMapper.map(
            action: DauAction_UpdatePreedit,
            text: "a",
            provisionalText: &provisionalText,
            provisionalLength: &provisionalLength
        )
        XCTAssertEqual(r.backspace, 0)
        XCTAssertEqual(r.text, "a")
        XCTAssertTrue(r.consumeOriginal)
        XCTAssertEqual(provisionalText, "a")
        XCTAssertEqual(provisionalLength, 1)
    }

    func testUpdatePreeditReplacesPreviousProvisional() {
        provisionalText = "tieen"
        provisionalLength = 5
        let r = DauResultMapper.map(
            action: DauAction_UpdatePreedit,
            text: "tiên",
            provisionalText: &provisionalText,
            provisionalLength: &provisionalLength
        )
        XCTAssertEqual(r.backspace, 5)
        XCTAssertEqual(r.text, "tiên")
        XCTAssertTrue(r.consumeOriginal)
        XCTAssertEqual(provisionalText, "tiên")
        XCTAssertEqual(provisionalLength, "tiên".unicodeScalars.count)
    }

    func testUpdatePreeditCountsUnicodeScalarsNotUTF16() {
        // "🇺🇸" is two regional-indicator scalars (surrogate pairs in UTF-16).
        provisionalText = "x"
        provisionalLength = 1
        let flag = "🇺🇸"
        let r = DauResultMapper.map(
            action: DauAction_UpdatePreedit,
            text: flag,
            provisionalText: &provisionalText,
            provisionalLength: &provisionalLength
        )
        XCTAssertEqual(r.backspace, 1)
        XCTAssertEqual(provisionalLength, flag.unicodeScalars.count)
        XCTAssertEqual(provisionalLength, 2)
    }

    // MARK: - Commit

    func testCommitUnchangedSkipsRetype() {
        provisionalText = "tiếng"
        provisionalLength = "tiếng".unicodeScalars.count
        let r = DauResultMapper.map(
            action: DauAction_Commit,
            text: "tiếng",
            provisionalText: &provisionalText,
            provisionalLength: &provisionalLength
        )
        XCTAssertEqual(r.backspace, 0)
        XCTAssertEqual(r.text, "")
        XCTAssertFalse(r.consumeOriginal) // forward break
        XCTAssertEqual(provisionalText, "")
        XCTAssertEqual(provisionalLength, 0)
    }

    func testCommitChangedRewritesProvisional() {
        provisionalText = "hellô" // composed form that auto-restore may replace
        provisionalLength = provisionalText.unicodeScalars.count
        let r = DauResultMapper.map(
            action: DauAction_Commit,
            text: "hello",
            provisionalText: &provisionalText,
            provisionalLength: &provisionalLength
        )
        XCTAssertEqual(r.backspace, "hellô".unicodeScalars.count)
        XCTAssertEqual(r.text, "hello")
        XCTAssertFalse(r.consumeOriginal)
        XCTAssertEqual(provisionalLength, 0)
        XCTAssertEqual(provisionalText, "")
    }

    func testCommitEmptyWithProvisionalDeletesOnly() {
        provisionalText = "ab"
        provisionalLength = 2
        let r = DauResultMapper.map(
            action: DauAction_Commit,
            text: "",
            provisionalText: &provisionalText,
            provisionalLength: &provisionalLength
        )
        XCTAssertEqual(r.backspace, 2)
        XCTAssertEqual(r.text, "")
        XCTAssertFalse(r.consumeOriginal)
        XCTAssertEqual(provisionalLength, 0)
    }

    // MARK: - Restore

    func testRestoreUsesProvisionalLengthPlusRaw() {
        provisionalText = "tiếng"
        provisionalLength = "tiếng".unicodeScalars.count
        let r = DauResultMapper.map(
            action: DauAction_Restore,
            text: "tieengs",
            provisionalText: &provisionalText,
            provisionalLength: &provisionalLength
        )
        XCTAssertEqual(r.backspace, "tiếng".unicodeScalars.count)
        XCTAssertEqual(r.text, "tieengs")
        XCTAssertTrue(r.consumeOriginal)
        XCTAssertEqual(provisionalText, "")
        XCTAssertEqual(provisionalLength, 0)
    }

    func testRestoreEmptyForwardsEsc() {
        let r = DauResultMapper.map(
            action: DauAction_Restore,
            text: "",
            provisionalText: &provisionalText,
            provisionalLength: &provisionalLength
        )
        XCTAssertEqual(r.backspace, 0)
        XCTAssertEqual(r.text, "")
        XCTAssertFalse(r.consumeOriginal)
    }

    // MARK: - capitalize_next passthrough

    func testCapitalizeNextEchoedNotUsedAsState() {
        let r = DauResultMapper.map(
            action: DauAction_Commit,
            text: "A",
            capitalizeNext: true,
            provisionalText: &provisionalText,
            provisionalLength: &provisionalLength
        )
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
        XCTAssertEqual(r.text, "ơ")
        XCTAssertEqual(provisionalLength, 1)
    }
}
