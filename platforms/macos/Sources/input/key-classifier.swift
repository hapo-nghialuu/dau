// Dấu macOS — pure key classification for the event-tap path (WP-04).
// No injection method choice; maps cleanly onto PipelineKeyKind (WP-02).

import CoreGraphics
import Foundation

// MARK: - Result types

/// High-level class of a keyboard event for the compose pipeline.
enum ClassifiedKeyKind: Equatable, Sendable {
    /// Single printable scalar to feed `dau_process_char`.
    case printable(Unicode.Scalar)
    /// Word boundary (space / punctuation / return / tab); forward after core break.
    case breakKey(Unicode.Scalar)
    /// Escape / restore path.
    case escape
    /// Delete / Backspace / ForwardDelete (key codes 51 / 117).
    case delete
    /// Pure modifier press or `flagsChanged` (forward; reset compose).
    case modifier
    /// Navigation, shortcuts with Cmd/Ctrl/Opt, unknown — forward; reset compose.
    case other
}

/// Classified key with metadata needed by the event-tap / pipeline.
struct ClassifiedKey: Equatable, Sendable {
    var kind: ClassifiedKeyKind
    var keyCode: UInt16
    var isRepeat: Bool
    /// Shift held on this event (for callers that pass `caps` into core).
    var shiftHeld: Bool

    /// Map to the WP-02 pipeline entry without depending on CGEvent.
    var pipelineKind: PipelineKeyKind {
        switch kind {
        case .printable: return .printable
        case .breakKey: return .breakKey
        case .escape: return .escape
        case .delete: return .delete
        case .modifier, .other: return .boundary
        }
    }

    /// UTF-32 code unit for printable/break; nil for escape/delete/modifier/other.
    var scalarValue: UInt32? {
        switch kind {
        case .printable(let s), .breakKey(let s):
            return s.value
        case .escape, .delete, .modifier, .other:
            return nil
        }
    }
}

// MARK: - Pure input snapshot (unit-test friendly)

/// Event snapshot independent of `CGEvent` / `NSEvent` so tests stay pure.
struct KeyClassifierInput: Equatable, Sendable {
    enum EventKind: Equatable, Sendable {
        case keyDown
        case flagsChanged
    }

    var eventKind: EventKind
    var keyCode: UInt16
    /// Unicode produced by the layout (may be empty for pure modifiers / arrows).
    var characters: String
    var command: Bool
    var control: Bool
    var option: Bool
    var shift: Bool
    var isRepeat: Bool

    init(
        eventKind: EventKind = .keyDown,
        keyCode: UInt16,
        characters: String = "",
        command: Bool = false,
        control: Bool = false,
        option: Bool = false,
        shift: Bool = false,
        isRepeat: Bool = false
    ) {
        self.eventKind = eventKind
        self.keyCode = keyCode
        self.characters = characters
        self.command = command
        self.control = control
        self.option = option
        self.shift = shift
        self.isRepeat = isRepeat
    }
}

// MARK: - Classifier

/// Classifies key events. Does **not** choose injection method or call core.
enum KeyClassifier {
    // Carbon virtual key codes (stable on Apple keyboards).
    enum KeyCode {
        static let returnKey: UInt16 = 36
        static let keypadEnter: UInt16 = 76
        static let tab: UInt16 = 48
        static let space: UInt16 = 49
        static let delete: UInt16 = 51
        static let forwardDelete: UInt16 = 117
        static let escape: UInt16 = 53
        static let command: UInt16 = 55
        static let shift: UInt16 = 56
        static let capsLock: UInt16 = 57
        static let option: UInt16 = 58
        static let control: UInt16 = 59
        static let rightCommand: UInt16 = 54
        static let rightShift: UInt16 = 60
        static let rightOption: UInt16 = 61
        static let rightControl: UInt16 = 62
        static let function: UInt16 = 63
        static let leftArrow: UInt16 = 123
        static let rightArrow: UInt16 = 124
        static let downArrow: UInt16 = 125
        static let upArrow: UInt16 = 126
        static let home: UInt16 = 115
        static let end: UInt16 = 119
        static let pageUp: UInt16 = 116
        static let pageDown: UInt16 = 121
    }

    /// Scalars that end a composing word (plan: space / punctuation / return).
    private static let breakScalars: Set<Unicode.Scalar> = [
        " ", "\t", "\n", "\r",
        ".", ",", "!", "?", ";", ":",
    ]

    private static let pureModifierCodes: Set<UInt16> = [
        KeyCode.command, KeyCode.rightCommand,
        KeyCode.shift, KeyCode.rightShift,
        KeyCode.option, KeyCode.rightOption,
        KeyCode.control, KeyCode.rightControl,
        KeyCode.capsLock, KeyCode.function,
    ]

    private static let deleteCodes: Set<UInt16> = [
        KeyCode.delete, KeyCode.forwardDelete,
    ]

    private static let navigationCodes: Set<UInt16> = [
        KeyCode.leftArrow, KeyCode.rightArrow, KeyCode.upArrow, KeyCode.downArrow,
        KeyCode.home, KeyCode.end, KeyCode.pageUp, KeyCode.pageDown,
    ]

    // MARK: Pure entry

    static func classify(_ input: KeyClassifierInput) -> ClassifiedKey {
        let base = ClassifiedKey(
            kind: .other,
            keyCode: input.keyCode,
            isRepeat: input.isRepeat,
            shiftHeld: input.shift
        )

        if input.eventKind == .flagsChanged {
            return ClassifiedKey(kind: .modifier, keyCode: input.keyCode, isRepeat: false, shiftHeld: input.shift)
        }

        if pureModifierCodes.contains(input.keyCode) {
            return ClassifiedKey(kind: .modifier, keyCode: input.keyCode, isRepeat: input.isRepeat, shiftHeld: input.shift)
        }

        if input.keyCode == KeyCode.escape {
            return ClassifiedKey(kind: .escape, keyCode: input.keyCode, isRepeat: input.isRepeat, shiftHeld: input.shift)
        }

        // Cmd / Ctrl / Opt: shortcuts or alternate layouts — never compose (MVP rule).
        // Includes Cmd+Delete → other (app-level word delete), not compose wipe.
        if input.command || input.control || input.option {
            return withKind(base, .other)
        }

        // First-class Delete/Backspace (P0): pipeline may wipe provisional and consume.
        if deleteCodes.contains(input.keyCode) {
            return ClassifiedKey(
                kind: .delete,
                keyCode: input.keyCode,
                isRepeat: input.isRepeat,
                shiftHeld: input.shift
            )
        }

        if navigationCodes.contains(input.keyCode) {
            return withKind(base, .other)
        }

        if let brk = breakScalar(forKeyCode: input.keyCode, characters: input.characters) {
            return withKind(base, .breakKey(brk))
        }

        if let scalar = singleScalar(from: input.characters) {
            if isBreakScalar(scalar) {
                return withKind(base, .breakKey(scalar))
            }
            if isPrintableScalar(scalar) {
                return withKind(base, .printable(scalar))
            }
        }

        return withKind(base, .other)
    }

    // MARK: CGEvent convenience (production path)

    /// Extract a pure snapshot from a live `CGEvent` and classify it.
    static func classify(event: CGEvent, type: CGEventType) -> ClassifiedKey {
        classify(snapshot(event: event, type: type))
    }

    static func snapshot(event: CGEvent, type: CGEventType) -> KeyClassifierInput {
        let flags = event.flags
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        let eventKind: KeyClassifierInput.EventKind =
            (type == .flagsChanged) ? .flagsChanged : .keyDown

        return KeyClassifierInput(
            eventKind: eventKind,
            keyCode: keyCode,
            characters: unicodeString(from: event) ?? "",
            command: flags.contains(.maskCommand),
            control: flags.contains(.maskControl),
            option: flags.contains(.maskAlternate),
            shift: flags.contains(.maskShift),
            isRepeat: isRepeat
        )
    }

    // MARK: Helpers

    private static func withKind(_ base: ClassifiedKey, _ kind: ClassifiedKeyKind) -> ClassifiedKey {
        var copy = base
        copy.kind = kind
        return copy
    }

    private static func singleScalar(from string: String) -> Unicode.Scalar? {
        var iterator = string.unicodeScalars.makeIterator()
        guard let first = iterator.next(), iterator.next() == nil else { return nil }
        return first
    }

    private static func isBreakScalar(_ scalar: Unicode.Scalar) -> Bool {
        if breakScalars.contains(scalar) { return true }
        // Additional Unicode punctuation commonly ending a word.
        if CharacterSet.punctuationCharacters.contains(scalar) { return true }
        return false
    }

    private static func isPrintableScalar(_ scalar: Unicode.Scalar) -> Bool {
        // Reject C0/C1 controls; allow letters, digits, combining marks, symbols used in Telex.
        if CharacterSet.controlCharacters.contains(scalar) { return false }
        if scalar.value == 0 { return false }
        return true
    }

    private static func breakScalar(forKeyCode keyCode: UInt16, characters: String) -> Unicode.Scalar? {
        switch keyCode {
        case KeyCode.returnKey, KeyCode.keypadEnter:
            if let s = singleScalar(from: characters), s == "\r" || s == "\n" {
                return s
            }
            return "\n"
        case KeyCode.tab:
            return "\t"
        case KeyCode.space:
            return " "
        default:
            return nil
        }
    }

    private static func unicodeString(from event: CGEvent) -> String? {
        var length = 0
        event.keyboardGetUnicodeString(maxStringLength: 0, actualStringLength: &length, unicodeString: nil)
        guard length > 0 else { return nil }
        var buffer = [UniChar](repeating: 0, count: Int(length))
        event.keyboardGetUnicodeString(
            maxStringLength: length,
            actualStringLength: &length,
            unicodeString: &buffer
        )
        guard length > 0 else { return nil }
        return String(utf16CodeUnits: buffer, count: Int(length))
    }
}
