// Dấu macOS — KeyClassifier unit tests (WP-04).
// Pure snapshot inputs only; no real CGEventTap / Accessibility.

import XCTest

final class KeyClassifierTests: XCTestCase {

    /// Single-scalar helper (avoids non-optional `Unicode.Scalar` force-unwrap noise).
    private func sc(_ ch: Character) -> Unicode.Scalar {
        ch.unicodeScalars.first!
    }

    // MARK: - Printable

    func testPrintableLetter() {
        let key = KeyClassifier.classify(
            KeyClassifierInput(keyCode: 0, characters: "a")
        )
        XCTAssertEqual(key.kind, .printable(sc("a")))
        XCTAssertEqual(key.pipelineKind, .printable)
        XCTAssertEqual(key.scalarValue, sc("a").value)
        XCTAssertFalse(key.isRepeat)
    }

    func testPrintableVietnamese() {
        let key = KeyClassifier.classify(
            KeyClassifierInput(keyCode: 0, characters: "ế")
        )
        XCTAssertEqual(key.kind, .printable(sc("ế")))
        XCTAssertEqual(key.pipelineKind, .printable)
    }

    func testPrintableWithShiftStillPrintable() {
        // Shift alone does not make the key a boundary; character is already cased.
        let key = KeyClassifier.classify(
            KeyClassifierInput(keyCode: 0, characters: "A", shift: true)
        )
        XCTAssertEqual(key.kind, .printable(sc("A")))
        XCTAssertTrue(key.shiftHeld)
    }

    func testKeyRepeatFlagPreserved() {
        let key = KeyClassifier.classify(
            KeyClassifierInput(keyCode: 0, characters: "a", isRepeat: true)
        )
        XCTAssertEqual(key.kind, .printable(sc("a")))
        XCTAssertTrue(key.isRepeat)
    }

    // MARK: - Break

    func testSpaceIsBreak() {
        let byCode = KeyClassifier.classify(
            KeyClassifierInput(keyCode: KeyClassifier.KeyCode.space, characters: " ")
        )
        XCTAssertEqual(byCode.kind, .breakKey(sc(" ")))
        XCTAssertEqual(byCode.pipelineKind, .breakKey)

        let byChar = KeyClassifier.classify(
            KeyClassifierInput(keyCode: 0, characters: " ")
        )
        XCTAssertEqual(byChar.kind, .breakKey(sc(" ")))
    }

    func testReturnIsBreak() {
        let key = KeyClassifier.classify(
            KeyClassifierInput(keyCode: KeyClassifier.KeyCode.returnKey, characters: "\r")
        )
        XCTAssertEqual(key.kind, .breakKey(sc("\r")))
        XCTAssertEqual(key.pipelineKind, .breakKey)
    }

    func testReturnWithoutCharactersDefaultsToNewline() {
        let key = KeyClassifier.classify(
            KeyClassifierInput(keyCode: KeyClassifier.KeyCode.returnKey, characters: "")
        )
        XCTAssertEqual(key.kind, .breakKey(sc("\n")))
    }

    func testTabIsBreak() {
        let key = KeyClassifier.classify(
            KeyClassifierInput(keyCode: KeyClassifier.KeyCode.tab, characters: "\t")
        )
        XCTAssertEqual(key.kind, .breakKey(sc("\t")))
    }

    func testPunctuationIsBreak() {
        for ch in [".", ",", "!", "?", ";", ":"] as [Character] {
            let key = KeyClassifier.classify(
                KeyClassifierInput(keyCode: 0, characters: String(ch))
            )
            XCTAssertEqual(key.kind, .breakKey(sc(ch)), "expected break for \(ch)")
            XCTAssertEqual(key.pipelineKind, .breakKey)
        }
    }

    // MARK: - Escape

    func testEscape() {
        let key = KeyClassifier.classify(
            KeyClassifierInput(keyCode: KeyClassifier.KeyCode.escape, characters: "\u{1b}")
        )
        XCTAssertEqual(key.kind, .escape)
        XCTAssertEqual(key.pipelineKind, .escape)
        XCTAssertNil(key.scalarValue)
    }

    // MARK: - Modifier / flagsChanged

    func testFlagsChangedIsModifier() {
        let key = KeyClassifier.classify(
            KeyClassifierInput(
                eventKind: .flagsChanged,
                keyCode: KeyClassifier.KeyCode.shift,
                shift: true
            )
        )
        XCTAssertEqual(key.kind, .modifier)
        XCTAssertEqual(key.pipelineKind, .boundary)
    }

    func testPureModifierKeyDown() {
        let codes: [UInt16] = [
            KeyClassifier.KeyCode.command,
            KeyClassifier.KeyCode.control,
            KeyClassifier.KeyCode.option,
            KeyClassifier.KeyCode.shift,
            KeyClassifier.KeyCode.capsLock,
        ]
        for code in codes {
            let key = KeyClassifier.classify(KeyClassifierInput(keyCode: code))
            XCTAssertEqual(key.kind, .modifier, "keyCode \(code)")
            XCTAssertEqual(key.pipelineKind, .boundary)
        }
    }

    // MARK: - Shortcuts / navigation → other (boundary)

    func testCommandShortcutIsOther() {
        let key = KeyClassifier.classify(
            KeyClassifierInput(keyCode: 0, characters: "c", command: true)
        )
        XCTAssertEqual(key.kind, .other)
        XCTAssertEqual(key.pipelineKind, .boundary)
    }

    func testControlShortcutIsOther() {
        let key = KeyClassifier.classify(
            KeyClassifierInput(keyCode: 0, characters: "c", control: true)
        )
        XCTAssertEqual(key.kind, .other)
        XCTAssertEqual(key.pipelineKind, .boundary)
    }

    func testOptionHeldIsOtherMVP() {
        // MVP: Option shortcuts / alt-layouts forward and reset compose.
        let key = KeyClassifier.classify(
            KeyClassifierInput(keyCode: 0, characters: "a", option: true)
        )
        XCTAssertEqual(key.kind, .other)
        XCTAssertEqual(key.pipelineKind, .boundary)
    }

    func testArrowKeysAreOther() {
        let arrows: [UInt16] = [
            KeyClassifier.KeyCode.leftArrow,
            KeyClassifier.KeyCode.rightArrow,
            KeyClassifier.KeyCode.upArrow,
            KeyClassifier.KeyCode.downArrow,
        ]
        for code in arrows {
            let key = KeyClassifier.classify(KeyClassifierInput(keyCode: code))
            XCTAssertEqual(key.kind, .other, "arrow \(code)")
            XCTAssertEqual(key.pipelineKind, .boundary)
        }
    }

    func testDeleteIsFirstClass() {
        let key = KeyClassifier.classify(
            KeyClassifierInput(keyCode: KeyClassifier.KeyCode.delete)
        )
        XCTAssertEqual(key.kind, .delete)
        XCTAssertEqual(key.pipelineKind, .delete)
        XCTAssertNil(key.scalarValue)
    }

    func testForwardDeleteIsFirstClass() {
        let key = KeyClassifier.classify(
            KeyClassifierInput(keyCode: KeyClassifier.KeyCode.forwardDelete)
        )
        XCTAssertEqual(key.kind, .delete)
        XCTAssertEqual(key.pipelineKind, .delete)
    }

    func testCommandDeleteRemainsOther() {
        let key = KeyClassifier.classify(
            KeyClassifierInput(keyCode: KeyClassifier.KeyCode.delete, command: true)
        )
        XCTAssertEqual(key.kind, .other)
        XCTAssertEqual(key.pipelineKind, .boundary)
    }

    // MARK: - Edge cases

    func testEmptyCharactersNonSpecialIsOther() {
        let key = KeyClassifier.classify(KeyClassifierInput(keyCode: 100, characters: ""))
        XCTAssertEqual(key.kind, .other)
    }

    func testMultiScalarCharactersIsOther() {
        let key = KeyClassifier.classify(
            KeyClassifierInput(keyCode: 0, characters: "ab")
        )
        XCTAssertEqual(key.kind, .other)
    }

    func testDigitIsPrintable() {
        let key = KeyClassifier.classify(
            KeyClassifierInput(keyCode: 18, characters: "1")
        )
        XCTAssertEqual(key.kind, .printable(sc("1")))
    }
}
