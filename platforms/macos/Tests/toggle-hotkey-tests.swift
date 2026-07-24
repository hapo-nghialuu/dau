// Dấu macOS — unit tests for ToggleHotkey model.

import Carbon
import XCTest

final class ToggleHotkeyTests: XCTestCase {
    func testDefaultIsCommandShiftE() {
        let hk = ToggleHotkey.default
        XCTAssertEqual(hk.keyCode, 14)
        XCTAssertTrue(hk.command)
        XCTAssertTrue(hk.shift)
        XCTAssertFalse(hk.control)
        XCTAssertFalse(hk.option)
        // Modifier glyphs follow macOS order: ⌃ ⌥ ⇧ ⌘
        XCTAssertEqual(hk.displayString, "⇧⌘E")
        XCTAssertEqual(hk.menuKeyEquivalent, "e")
        XCTAssertTrue(hk.menuModifierMask.contains(.command))
        XCTAssertTrue(hk.menuModifierMask.contains(.shift))
        XCTAssertTrue(hk.isValid)
    }

    func testDisplayOrderControlOptionShiftCommand() {
        let hk = ToggleHotkey(
            keyCode: 49,
            command: true,
            control: true,
            option: true,
            shift: true
        )
        XCTAssertEqual(hk.displayString, "⌃⌥⇧⌘Space")
    }

    func testMatchesExactModifiers() {
        let hk = ToggleHotkey.default
        XCTAssertTrue(
            hk.matches(keyCode: 14, command: true, control: false, option: false, shift: true)
        )
        XCTAssertFalse(
            hk.matches(keyCode: 14, command: true, control: false, option: false, shift: false),
            "missing Shift must not match"
        )
        XCTAssertFalse(
            hk.matches(keyCode: 15, command: true, control: false, option: false, shift: true),
            "wrong keyCode must not match"
        )
        XCTAssertFalse(
            hk.matches(keyCode: 14, command: true, control: true, option: false, shift: true),
            "extra Control must not match"
        )
    }

    func testBareLetterIsInvalid() {
        let bare = ToggleHotkey(
            keyCode: 14,
            command: false,
            control: false,
            option: false,
            shift: false
        )
        XCTAssertFalse(bare.isValid)
    }

    func testShiftOnlyIsInvalid() {
        let shiftOnly = ToggleHotkey(
            keyCode: 14,
            command: false,
            control: false,
            option: false,
            shift: true
        )
        XCTAssertFalse(shiftOnly.isValid)
    }

    func testControlSpaceIsValid() {
        let hk = ToggleHotkey(
            keyCode: 49,
            command: false,
            control: true,
            option: false,
            shift: false
        )
        XCTAssertTrue(hk.isValid)
        XCTAssertEqual(hk.displayString, "⌃Space")
        XCTAssertEqual(hk.menuKeyEquivalent, " ")
    }

    func testCodableRoundTrip() throws {
        let original = ToggleHotkey(
            keyCode: 31,
            command: true,
            control: false,
            option: true,
            shift: false
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ToggleHotkey.self, from: data)
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.displayString, "⌥⌘O")
    }

    func testPureModifierKeyCodeIsInvalidEvenWithCommand() {
        // Left Command key code with "command" flag still not a useful toggle.
        let pure = ToggleHotkey(
            keyCode: 55,
            command: true,
            control: false,
            option: false,
            shift: false
        )
        XCTAssertFalse(pure.isValid)
    }

    func testCarbonModifiersForDefault() {
        let mods = ToggleHotkey.default.carbonModifiers
        XCTAssertEqual(mods & UInt32(cmdKey), UInt32(cmdKey))
        XCTAssertEqual(mods & UInt32(shiftKey), UInt32(shiftKey))
        XCTAssertEqual(mods & UInt32(optionKey), 0)
        XCTAssertEqual(mods & UInt32(controlKey), 0)
    }

    func testCarbonModifiersControlSpace() {
        let hk = ToggleHotkey(
            keyCode: 49,
            command: false,
            control: true,
            option: false,
            shift: false
        )
        XCTAssertEqual(hk.carbonModifiers, UInt32(controlKey))
    }
}
