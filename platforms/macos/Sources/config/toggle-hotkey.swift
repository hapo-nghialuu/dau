// Dấu macOS — configurable VI/EN toggle hotkey (keyCode + modifiers).
// Registered globally via Carbon (ToggleHotkeyRegistrar); menu keyEquivalent is secondary.

import AppKit
import Foundation

/// User-configurable global shortcut that toggles Vietnamese typing (VI/EN).
struct ToggleHotkey: Equatable, Sendable, Codable {
    var keyCode: UInt16
    var command: Bool
    var control: Bool
    var option: Bool
    var shift: Bool

    /// Product default: Cmd+Shift+E (Carbon key code 14 = E). Display: `⇧⌘E`.
    static let `default` = ToggleHotkey(
        keyCode: 14,
        command: true,
        control: false,
        option: false,
        shift: true
    )

    /// At least one of ⌘/⌃/⌥ so bare letters never steal typing.
    var isValid: Bool {
        (command || control || option) && !Self.isPureModifier(keyCode)
    }

    /// Human display (macOS modifier order ⌃⌥⇧⌘), e.g. `⇧⌘E`, `⌃Space`.
    var displayString: String {
        var s = ""
        if control { s += "⌃" }
        if option { s += "⌥" }
        if shift { s += "⇧" }
        if command { s += "⌘" }
        s += Self.keyLabel(keyCode)
        return s
    }

    /// `NSMenuItem.keyEquivalent` when representable; otherwise `nil` (EventTap still works).
    var menuKeyEquivalent: String? {
        Self.menuEquivalentCharacter(keyCode)
    }

    var menuModifierMask: NSEvent.ModifierFlags {
        var mask: NSEvent.ModifierFlags = []
        if command { mask.insert(.command) }
        if control { mask.insert(.control) }
        if option { mask.insert(.option) }
        if shift { mask.insert(.shift) }
        return mask
    }

    func matches(
        keyCode: UInt16,
        command: Bool,
        control: Bool,
        option: Bool,
        shift: Bool
    ) -> Bool {
        self.keyCode == keyCode
            && self.command == command
            && self.control == control
            && self.option == option
            && self.shift == shift
    }

    /// Build from a key-down event; returns `nil` if invalid for a global toggle.
    static func fromKeyDownEvent(_ event: NSEvent) -> ToggleHotkey? {
        guard event.type == .keyDown else { return nil }
        let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
        let hotkey = ToggleHotkey(
            keyCode: UInt16(event.keyCode),
            command: flags.contains(.command),
            control: flags.contains(.control),
            option: flags.contains(.option),
            shift: flags.contains(.shift)
        )
        return hotkey.isValid ? hotkey : nil
    }

    // MARK: - Labels / menu chars

    private static func isPureModifier(_ keyCode: UInt16) -> Bool {
        // Carbon left/right Cmd/Shift/Opt/Ctrl, Caps, Fn.
        switch keyCode {
        case 54, 55, 56, 57, 58, 59, 60, 61, 62, 63:
            return true
        default:
            return false
        }
    }

    private static func keyLabel(_ keyCode: UInt16) -> String {
        if let letter = letterMap[keyCode] {
            return letter.uppercased()
        }
        if let special = specialLabels[keyCode] {
            return special
        }
        if let digit = digitMap[keyCode] {
            return digit
        }
        return "Key\(keyCode)"
    }

    private static func menuEquivalentCharacter(_ keyCode: UInt16) -> String? {
        if let letter = letterMap[keyCode] {
            return letter
        }
        if let digit = digitMap[keyCode] {
            return digit
        }
        switch keyCode {
        case 49: return " " // Space
        case 36: return "\r" // Return
        case 48: return "\t"
        case 51: return "\u{8}" // Delete
        case 53: return "\u{1b}" // Escape
        default: return nil
        }
    }

    private static let letterMap: [UInt16: String] = [
        0: "a", 11: "b", 8: "c", 2: "d", 14: "e", 3: "f", 5: "g", 4: "h",
        34: "i", 38: "j", 40: "k", 37: "l", 46: "m", 45: "n", 31: "o", 35: "p",
        12: "q", 15: "r", 1: "s", 17: "t", 32: "u", 9: "v", 13: "w", 7: "x",
        16: "y", 6: "z",
    ]

    private static let digitMap: [UInt16: String] = [
        18: "1", 19: "2", 20: "3", 21: "4", 23: "5",
        22: "6", 26: "7", 28: "8", 25: "9", 29: "0",
    ]

    private static let specialLabels: [UInt16: String] = [
        49: "Space",
        36: "↩",
        76: "Enter",
        48: "⇥",
        51: "⌫",
        117: "⌦",
        53: "Esc",
        123: "←",
        124: "→",
        125: "↓",
        126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4",
        96: "F5", 97: "F6", 98: "F7", 100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]
}
