// Dấu macOS — TextInjector: replacement sequencing (WP-03).
// Posts Backspace + Unicode via a pluggable EventSink; never logs text content.

import CoreGraphics
import Foundation

// MARK: - Synthetic event marker

/// Marker stamped on every synthetic CGEvent so the event-tap callback can ignore it.
enum SyntheticEventMarker {
    /// Stable non-zero value for `eventSourceUserData` (not a secret; just provenance).
    static let userData: Int64 = 0x0044_4155_494E_4A01 // "DAU" + "INJ" + revision

    static func apply(to event: CGEvent) {
        event.setIntegerValueField(.eventSourceUserData, value: userData)
    }

    static func matches(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.eventSourceUserData) == userData
    }
}

// MARK: - Command plan

/// Ordered injector steps. Unit tests assert plan shape without posting real keys.
enum InjectorCommand: Equatable, Sendable {
    case backspace
    case unicodeChunk(String)
    case wait(microseconds: UInt32)
    /// Shift+Left once (selection method; stub path may still emit for structure).
    case shiftLeft
    /// Narrow no-break space used to poke autocomplete (U+202F).
    case emptyPrefix
}

enum InjectionError: Error, Equatable, Sendable {
    case invalidBackspaceCount
    case unsupportedMethod(InjectionMethod)
    case sinkFailed(String)
}

// MARK: - Event sink (testable)

/// Abstraction over posting keyboard/text events. Production uses CGEvent; tests use a recorder.
protocol InjectorEventSink: AnyObject {
    func postBackspace()
    func postUnicode(_ text: String)
    func postShiftLeft()
    func postEmptyPrefix()
}

/// Records sink calls for unit tests (command ordering without CGEvent / Accessibility).
final class RecordingEventSink: InjectorEventSink {
    private(set) var commands: [InjectorCommand] = []

    func reset() {
        commands.removeAll(keepingCapacity: true)
    }

    func postBackspace() {
        commands.append(.backspace)
    }

    func postUnicode(_ text: String) {
        commands.append(.unicodeChunk(text))
    }

    func postShiftLeft() {
        commands.append(.shiftLeft)
    }

    func postEmptyPrefix() {
        commands.append(.emptyPrefix)
    }
}

/// Production sink: HID-level CGEvent keyboard posts with synthetic marker.
final class CGEventInjectorSink: InjectorEventSink {
    /// Virtual key code for Delete/Backspace (Carbon `kVK_Delete`).
    private static let backspaceKeyCode: CGKeyCode = 51
    /// Virtual key code for Left Arrow (`kVK_LeftArrow`).
    private static let leftArrowKeyCode: CGKeyCode = 123
    /// Narrow no-break space (U+202F) used by empty-char-prefix method.
    private static let emptyPrefixScalar: Unicode.Scalar = "\u{202F}"

    func postBackspace() {
        postKey(Self.backspaceKeyCode, keyDown: true)
        postKey(Self.backspaceKeyCode, keyDown: false)
    }

    func postUnicode(_ text: String) {
        guard !text.isEmpty else { return }
        postUnicodeString(text)
    }

    func postShiftLeft() {
        postKey(Self.leftArrowKeyCode, keyDown: true, flags: .maskShift)
        postKey(Self.leftArrowKeyCode, keyDown: false, flags: .maskShift)
    }

    func postEmptyPrefix() {
        postUnicodeString(String(Self.emptyPrefixScalar))
    }

    private func postKey(_ keyCode: CGKeyCode, keyDown: Bool, flags: CGEventFlags = []) {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: keyDown) else {
            return
        }
        if !flags.isEmpty {
            event.flags = flags
        }
        SyntheticEventMarker.apply(to: event)
        event.post(tap: .cghidEventTap)
    }

    private func postUnicodeString(_ text: String) {
        let source = CGEventSource(stateID: .hidSystemState)
        var utf16 = Array(text.utf16)
        let length = utf16.count
        guard length > 0 else { return }

        if let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true) {
            down.keyboardSetUnicodeString(stringLength: length, unicodeString: &utf16)
            SyntheticEventMarker.apply(to: down)
            down.post(tap: .cghidEventTap)
        }
        if let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) {
            up.keyboardSetUnicodeString(stringLength: length, unicodeString: &utf16)
            SyntheticEventMarker.apply(to: up)
            up.post(tap: .cghidEventTap)
        }
    }
}

// MARK: - Sleeper (testable delays)

protocol InjectorSleeper: AnyObject {
    func sleep(microseconds: UInt32)
}

final class SystemInjectorSleeper: InjectorSleeper {
    func sleep(microseconds: UInt32) {
        guard microseconds > 0 else { return }
        usleep(microseconds)
    }
}

/// Captures delay calls without sleeping (unit tests).
final class RecordingInjectorSleeper: InjectorSleeper {
    private(set) var sleeps: [UInt32] = []

    func reset() {
        sleeps.removeAll(keepingCapacity: true)
    }

    func sleep(microseconds: UInt32) {
        sleeps.append(microseconds)
    }
}

// MARK: - TextInjector

/// Executes replacement: N backspaces then text, ordered and serialized.
/// Logs only method / lengths / delays — never raw key or text content.
final class TextInjector {
    private let sink: InjectorEventSink
    private let sleeper: InjectorSleeper
    private let lock = NSLock()
    private let axAccessor: AXTextAccessor

    /// Optional metadata logger. Must not receive text content.
    var onMetadata: ((String) -> Void)?

    init(
        sink: InjectorEventSink = CGEventInjectorSink(),
        sleeper: InjectorSleeper = SystemInjectorSleeper(),
        axAccessor: AXTextAccessor = AXTextAccessor()
    ) {
        self.sink = sink
        self.sleeper = sleeper
        self.axAccessor = axAccessor
    }

    /// Build the ordered command plan without side effects (unit-test entry point).
    func plan(
        backspace: Int,
        text: String,
        method: InjectionMethod,
        delays: DelayPreset
    ) -> [InjectorCommand] {
        guard backspace >= 0 else { return [] }

        switch method {
        case .passthrough:
            return []

        case .backspaceFast, .backspaceSlow:
            return planBackspaceThenText(backspace: backspace, text: text, delays: delays, charByChar: false)

        case .charByChar:
            return planBackspaceThenText(backspace: backspace, text: text, delays: delays, charByChar: true)

        case .selection:
            // TODO(P3.1): full selection path for address bar / combobox / Excel-like.
            // Structured stub: Shift+Left × N then Unicode (or Backspace if text empty).
            return planSelectionStub(backspace: backspace, text: text, delays: delays)

        case .emptyCharPrefix:
            // TODO(P3.3): role-aware autocomplete break; structured stub plan only.
            return planEmptyCharPrefixStub(backspace: backspace, text: text, delays: delays)

        case .syncProxy:
            // TODO(P3.4): requires CGEventTapProxy from the tap callback.
            // Structured stub: same ordering as backspaceFast for plan inspection.
            return planBackspaceThenText(backspace: backspace, text: text, delays: delays, charByChar: false)

        case .axDirect:
            // TODO(P3.5): AX value/range write; plan falls back to synthetic BS+text.
            return planBackspaceThenText(backspace: backspace, text: text, delays: delays, charByChar: false)
        }
    }

    /// Inject replacement. Safe for concurrent callers (serialized). Never logs `text`.
    @discardableResult
    func inject(
        backspace: Int,
        text: String,
        method: InjectionMethod,
        delays: DelayPreset
    ) -> Result<Void, InjectionError> {
        guard backspace >= 0 else {
            return .failure(.invalidBackspaceCount)
        }

        lock.lock()
        defer { lock.unlock() }

        // Metadata only: method + counts + delay numbers. No text content.
        onMetadata?(
            "inject method=\(method.rawValue) bs=\(backspace) textLen=\(text.unicodeScalars.count) " +
            "delays=(\(delays.backspaceUs),\(delays.settleUs),\(delays.textUs))"
        )

        if method == .passthrough {
            return .success(())
        }

        if method == .axDirect {
            // Attempt AX path; fall back to synthetic on any failure (no crash).
            let axResult = axAccessor.replaceFocusedText(
                deleteScalarCount: backspace,
                replacement: text
            )
            switch axResult {
            case .success:
                onMetadata?("inject axDirect=ok textLen=\(text.unicodeScalars.count)")
                return .success(())
            case .failure(let err):
                onMetadata?("inject axDirect=fallback error=\(err)")
                // Fall through to synthetic plan.
            }
        }

        if method == .syncProxy {
            // TODO(P3.4): wire proxy from KeyboardEventTap; for now synthetic HID path.
            onMetadata?("inject syncProxy=stub_fallback")
        }

        let commands = plan(backspace: backspace, text: text, method: method, delays: delays)
        execute(commands)
        return .success(())
    }

    // MARK: Planning helpers

    private func planBackspaceThenText(
        backspace: Int,
        text: String,
        delays: DelayPreset,
        charByChar: Bool
    ) -> [InjectorCommand] {
        var cmds: [InjectorCommand] = []
        if backspace > 0 {
            for i in 0..<backspace {
                cmds.append(.backspace)
                if delays.backspaceUs > 0, i < backspace - 1 || delays.settleUs == 0 {
                    // Delay after each BS except we prefer settle after the last when settle > 0.
                    if i < backspace - 1 {
                        cmds.append(.wait(microseconds: delays.backspaceUs))
                    } else if delays.settleUs == 0 {
                        cmds.append(.wait(microseconds: delays.backspaceUs))
                    }
                }
            }
            if delays.settleUs > 0 {
                cmds.append(.wait(microseconds: delays.settleUs))
            } else if delays.backspaceUs > 0, backspace > 0 {
                // Last BS delay already handled above when settle is 0.
            }
        }

        if text.isEmpty {
            return cmds
        }

        if charByChar {
            for scalar in text.unicodeScalars {
                cmds.append(.unicodeChunk(String(scalar)))
                if delays.textUs > 0 {
                    cmds.append(.wait(microseconds: delays.textUs))
                }
            }
        } else {
            cmds.append(.unicodeChunk(text))
            if delays.textUs > 0 {
                cmds.append(.wait(microseconds: delays.textUs))
            }
        }
        return cmds
    }

    private func planSelectionStub(backspace: Int, text: String, delays: DelayPreset) -> [InjectorCommand] {
        var cmds: [InjectorCommand] = []
        if text.isEmpty {
            // Plan: real Backspace when replacement is empty.
            return planBackspaceThenText(backspace: backspace, text: "", delays: delays, charByChar: false)
        }
        for i in 0..<backspace {
            cmds.append(.shiftLeft)
            if delays.backspaceUs > 0, i < backspace - 1 {
                cmds.append(.wait(microseconds: delays.backspaceUs))
            }
        }
        if delays.settleUs > 0, backspace > 0 {
            cmds.append(.wait(microseconds: delays.settleUs))
        }
        cmds.append(.unicodeChunk(text))
        if delays.textUs > 0 {
            cmds.append(.wait(microseconds: delays.textUs))
        }
        return cmds
    }

    private func planEmptyCharPrefixStub(backspace: Int, text: String, delays: DelayPreset) -> [InjectorCommand] {
        var cmds: [InjectorCommand] = []
        cmds.append(.emptyPrefix)
        if delays.backspaceUs > 0 {
            cmds.append(.wait(microseconds: delays.backspaceUs))
        }
        // Extra delete for the prefix + provisional length.
        let totalDelete = backspace + 1
        cmds.append(contentsOf: planBackspaceThenText(
            backspace: totalDelete,
            text: text,
            delays: delays,
            charByChar: false
        ))
        return cmds
    }

    // MARK: Execution

    private func execute(_ commands: [InjectorCommand]) {
        for command in commands {
            switch command {
            case .backspace:
                sink.postBackspace()
            case .unicodeChunk(let chunk):
                sink.postUnicode(chunk)
            case .wait(let us):
                sleeper.sleep(microseconds: us)
            case .shiftLeft:
                sink.postShiftLeft()
            case .emptyPrefix:
                sink.postEmptyPrefix()
            }
        }
    }
}
