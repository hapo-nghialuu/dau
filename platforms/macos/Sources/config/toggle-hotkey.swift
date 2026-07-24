// Dấu macOS — configurable VI/EN toggle hotkey (keyCode + modifiers).
// Keyed combos: Carbon RegisterEventHotKey.
// Modifier-only chords (e.g. ⌘⇧): EventTap flagsChanged (see ToggleHotkeyRegistrar).

import AppKit
import Foundation

/// User-configurable global shortcut that toggles Vietnamese typing (VI/EN).
struct ToggleHotkey: Equatable, Sendable, Codable {
    /// Virtual key code. `nil` / omitted = **modifier-only** chord (⌘⇧, ⌃⌥, …).
    var keyCode: UInt16?
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

    /// ⌘⇧ only (no letter) — user-requested two-key style.
    static let commandShiftOnly = ToggleHotkey(
        keyCode: nil,
        command: true,
        control: false,
        option: false,
        shift: true
    )

    private enum CodingKeys: String, CodingKey {
        case keyCode, command, control, option, shift
    }

    init(keyCode: UInt16?, command: Bool, control: Bool, option: Bool, shift: Bool) {
        self.keyCode = keyCode
        self.command = command
        self.control = control
        self.option = option
        self.shift = shift
    }

    /// Backward-compatible decode: missing keyCode treated as 0 only if present as number;
    /// explicit null / absent with only mods = modifier-only.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if c.contains(.keyCode) {
            if try c.decodeNil(forKey: .keyCode) {
                keyCode = nil
            } else {
                keyCode = try c.decode(UInt16.self, forKey: .keyCode)
            }
        } else {
            keyCode = nil
        }
        command = try c.decode(Bool.self, forKey: .command)
        control = try c.decode(Bool.self, forKey: .control)
        option = try c.decode(Bool.self, forKey: .option)
        shift = try c.decode(Bool.self, forKey: .shift)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(keyCode, forKey: .keyCode)
        try c.encode(command, forKey: .command)
        try c.encode(control, forKey: .control)
        try c.encode(option, forKey: .option)
        try c.encode(shift, forKey: .shift)
    }

    var isModifierOnly: Bool {
        keyCode == nil
    }

    var modifierCount: Int {
        [command, control, option, shift].filter(\.self).count
    }

    /// Valid if:
    /// - key + at least one of ⌘/⌃/⌥, or
    /// - **modifier-only** with ≥2 modifiers (e.g. ⌘⇧), no bare key.
    var isValid: Bool {
        if let code = keyCode {
            return (command || control || option) && !Self.isPureModifier(code)
        }
        // Modifier-only: need at least two modifiers so a single Shift/Cmd isn't a toggle.
        return modifierCount >= 2
    }

    /// Human display (macOS modifier order ⌃⌥⇧⌘), e.g. `⇧⌘E`, `⇧⌘`, `⌃Space`.
    var displayString: String {
        var s = ""
        if control { s += "⌃" }
        if option { s += "⌥" }
        if shift { s += "⇧" }
        if command { s += "⌘" }
        if let code = keyCode {
            s += Self.keyLabel(code)
        }
        return s.isEmpty ? "?" : s
    }

    var menuKeyEquivalent: String? {
        guard let code = keyCode else { return nil }
        return Self.menuEquivalentCharacter(code)
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
        keyCode: UInt16?,
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

    /// Exact match of the four modifier flags (for modifier-only chords).
    func matchesModifiers(
        command: Bool,
        control: Bool,
        option: Bool,
        shift: Bool
    ) -> Bool {
        self.command == command
            && self.control == control
            && self.option == option
            && self.shift == shift
    }

    /// Build from a key-down event; returns `nil` if invalid for a global toggle.
    static func fromKeyDownEvent(_ event: NSEvent) -> ToggleHotkey? {
        guard event.type == .keyDown else { return nil }
        if isPureModifier(UInt16(event.keyCode)) {
            return nil
        }
        let flags = Self.deviceFlags(event)
        let hotkey = ToggleHotkey(
            keyCode: UInt16(event.keyCode),
            command: flags.contains(.command),
            control: flags.contains(.control),
            option: flags.contains(.option),
            shift: flags.contains(.shift)
        )
        return hotkey.isValid ? hotkey : nil
    }

    /// Build modifier-only chord from flagsChanged when ≥2 modifiers are down.
    static func fromFlagsChangedEvent(_ event: NSEvent) -> ToggleHotkey? {
        guard event.type == .flagsChanged else { return nil }
        let flags = Self.deviceFlags(event)
        let hotkey = ToggleHotkey(
            keyCode: nil,
            command: flags.contains(.command),
            control: flags.contains(.control),
            option: flags.contains(.option),
            shift: flags.contains(.shift)
        )
        return hotkey.isValid ? hotkey : nil
    }

    /// Live preview while recording (modifiers and/or incomplete).
    static func modifiersDisplay(from event: NSEvent) -> String {
        let flags = Self.deviceFlags(event)
        var s = ""
        if flags.contains(.control) { s += "⌃" }
        if flags.contains(.option) { s += "⌥" }
        if flags.contains(.shift) { s += "⇧" }
        if flags.contains(.command) { s += "⌘" }
        return s.isEmpty ? "…" : s
    }

    static func deviceFlags(_ event: NSEvent) -> NSEvent.ModifierFlags {
        event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .intersection([.command, .control, .option, .shift])
    }

    // MARK: - Labels / menu chars

    private static func isPureModifier(_ keyCode: UInt16) -> Bool {
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
        case 49: return " "
        case 36: return "\r"
        case 48: return "\t"
        case 51: return "\u{8}"
        case 53: return "\u{1b}"
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
