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

    func testCommandShiftAIsValid() {
        let hk = ToggleHotkey(keyCode: 0, command: true, control: false, option: false, shift: true)
        XCTAssertTrue(hk.isValid)
        XCTAssertEqual(hk.displayString, "⇧⌘A")
    }


    func testCommandShiftOnlyIsValid() {
        let hk = ToggleHotkey.commandShiftOnly
        XCTAssertTrue(hk.isModifierOnly)
        XCTAssertTrue(hk.isValid)
        XCTAssertEqual(hk.displayString, "⇧⌘")
        XCTAssertNil(hk.menuKeyEquivalent)
        XCTAssertTrue(hk.matchesModifiers(command: true, control: false, option: false, shift: true))
        XCTAssertFalse(hk.matchesModifiers(command: true, control: false, option: false, shift: false))
    }

    func testSingleModifierOnlyIsInvalid() {
        let shiftOnly = ToggleHotkey(keyCode: nil, command: false, control: false, option: false, shift: true)
        XCTAssertFalse(shiftOnly.isValid)
        let cmdOnly = ToggleHotkey(keyCode: nil, command: true, control: false, option: false, shift: false)
        XCTAssertFalse(cmdOnly.isValid)
    }

    func testDefaultKeyCodeNonNil() {
        XCTAssertEqual(ToggleHotkey.default.keyCode, 14)
        XCTAssertFalse(ToggleHotkey.default.isModifierOnly)
    }

    // MARK: - Registrar registration state / retry

    func testRegistrarTracksFailureThenRetrySuccess() {
        let reg = ToggleHotkeyRegistrar()
        defer { reg.unregister() }
        let chord = ToggleHotkey.commandShiftOnly

        reg.testForceRegistrationResult = false
        reg.register(chord)
        XCTAssertFalse(reg.isRegistered)
        XCTAssertTrue(reg.lastRegisterAttemptFailed)
        let genAfterFail = reg.registrationGeneration

        reg.testForceRegistrationResult = true
        let ok = reg.registerIfNeeded(chord)
        XCTAssertTrue(ok)
        XCTAssertTrue(reg.isRegistered)
        XCTAssertFalse(reg.lastRegisterAttemptFailed)
        XCTAssertEqual(reg.registrationGeneration, genAfterFail &+ 1)
    }

    func testRegisterIfNeededDoesNotTearDownWhenAlreadyRegistered() {
        let reg = ToggleHotkeyRegistrar()
        defer { reg.unregister() }
        let chord = ToggleHotkey.commandShiftOnly

        reg.testForceRegistrationResult = true
        reg.register(chord)
        XCTAssertTrue(reg.isRegistered)
        let gen = reg.registrationGeneration

        // Would flip to failed if register() were re-entered (clear + forced fail).
        reg.testForceRegistrationResult = false
        reg.registerIfNeeded(chord)
        reg.registerIfNeeded(chord)
        reg.registerIfNeeded(chord)

        XCTAssertTrue(reg.isRegistered, "live registration must survive repeated ensure")
        XCTAssertEqual(reg.registrationGeneration, gen, "must not tear down / recreate")
        XCTAssertFalse(reg.lastRegisterAttemptFailed)
    }

    func testRegisterForceRebindAlwaysReinstalls() {
        let reg = ToggleHotkeyRegistrar()
        defer { reg.unregister() }

        reg.testForceRegistrationResult = true
        reg.register(ToggleHotkey.commandShiftOnly)
        let gen = reg.registrationGeneration
        XCTAssertTrue(reg.isRegistered)

        // Settings-style force rebind must reinstall even when already live.
        reg.register(ToggleHotkey.commandShiftOnly)
        XCTAssertTrue(reg.isRegistered)
        XCTAssertEqual(reg.registrationGeneration, gen &+ 1)
    }

    func testCarbonBranchTracksForcedFailureAndSuccess() {
        let reg = ToggleHotkeyRegistrar()
        defer { reg.unregister() }
        let key = ToggleHotkey.default

        reg.testForceRegistrationResult = false
        reg.register(key)
        XCTAssertFalse(reg.isRegistered)
        XCTAssertTrue(reg.lastRegisterAttemptFailed)

        reg.testForceRegistrationResult = true
        reg.registerIfNeeded(key)
        XCTAssertTrue(reg.isRegistered)
        XCTAssertFalse(reg.lastRegisterAttemptFailed)
    }

}
