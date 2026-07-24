// Dấu macOS — TextInjector: replacement sequencing (WP-03).
// Posts Backspace + Unicode via a pluggable EventSink; never logs text content.
// Dead-key guard: sink reports post failures; session must fail-open (not consume) when inject cannot run.

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

// MARK: - Post-event access (dead-key preflight)

/// Gate for synthetic keyboard posts. When false, TypingSession must not consume originals.
enum SyntheticPostAccess {
    /// Production: `CGPreflightPostEventAccess()` (+ one optional `CGRequestPostEventAccess`).
    /// Overridable in unit tests.
    static var check: () -> Bool = defaultCheck

    private static let requestLock = NSLock()
    /// At most one OS request prompt per process lifetime.
    private static var didRequestOnce = false

    static var isGranted: Bool { check() }

    static func resetToDefault() {
        check = defaultCheck
        requestLock.lock()
        didRequestOnce = false
        requestLock.unlock()
    }

    private static func defaultCheck() -> Bool {
        if #available(macOS 10.15, *) {
            if CGPreflightPostEventAccess() {
                return true
            }
            requestLock.lock()
            let shouldRequest = !didRequestOnce
            if shouldRequest {
                didRequestOnce = true
            }
            requestLock.unlock()
            if shouldRequest {
                fputs("[dau] post-event access denied; requesting once\n", stderr)
                _ = CGRequestPostEventAccess()
                if CGPreflightPostEventAccess() {
                    fputs("[dau] post-event access granted after request\n", stderr)
                    return true
                }
            }
            fputs("[dau] post-event access denied\n", stderr)
            return false
        }
        // Pre-10.15: no separate post-access API; Accessibility trust is the practical gate.
        return true
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
    /// OS denied synthetic keyboard posts (`CGPreflightPostEventAccess` false).
    case postAccessDenied
}

// MARK: - Event sink (testable)

/// Abstraction over posting keyboard/text events. Production uses CGEvent; tests use a recorder.
/// Return `false` when the OS event could not be created/posted so callers can fail-open.
protocol InjectorEventSink: AnyObject {
    @discardableResult
    func postBackspace() -> Bool
    @discardableResult
    func postUnicode(_ text: String) -> Bool
    @discardableResult
    func postShiftLeft() -> Bool
    @discardableResult
    func postEmptyPrefix() -> Bool
}

/// Records sink calls for unit tests (command ordering without CGEvent / Accessibility).
final class RecordingEventSink: InjectorEventSink {
    private(set) var commands: [InjectorCommand] = []
    /// When false, posts still record but report failure (dead-key regression tests).
    var shouldSucceed: Bool = true

    func reset() {
        commands.removeAll(keepingCapacity: true)
    }

    @discardableResult
    func postBackspace() -> Bool {
        commands.append(.backspace)
        return shouldSucceed
    }

    @discardableResult
    func postUnicode(_ text: String) -> Bool {
        commands.append(.unicodeChunk(text))
        return shouldSucceed
    }

    @discardableResult
    func postShiftLeft() -> Bool {
        commands.append(.shiftLeft)
        return shouldSucceed
    }

    @discardableResult
    func postEmptyPrefix() -> Bool {
        commands.append(.emptyPrefix)
        return shouldSucceed
    }
}

/// Production sink: CGEvent keyboard posts with synthetic marker.
/// Prefer HID; fall back to session tap when event creation for HID path fails.
final class CGEventInjectorSink: InjectorEventSink {
    /// Virtual key code for Delete/Backspace (Carbon `kVK_Delete`).
    private static let backspaceKeyCode: CGKeyCode = 51
    /// Virtual key code for Left Arrow (`kVK_LeftArrow`).
    private static let leftArrowKeyCode: CGKeyCode = 123
    /// Narrow no-break space (U+202F) used by empty-char-prefix method.
    private static let emptyPrefixScalar: Unicode.Scalar = "\u{202F}"

    @discardableResult
    func postBackspace() -> Bool {
        let down = postKey(Self.backspaceKeyCode, keyDown: true)
        let up = postKey(Self.backspaceKeyCode, keyDown: false)
        return down && up
    }

    @discardableResult
    func postUnicode(_ text: String) -> Bool {
        guard !text.isEmpty else { return true }
        return postUnicodeString(text)
    }

    @discardableResult
    func postShiftLeft() -> Bool {
        let down = postKey(Self.leftArrowKeyCode, keyDown: true, flags: .maskShift)
        let up = postKey(Self.leftArrowKeyCode, keyDown: false, flags: .maskShift)
        return down && up
    }

    @discardableResult
    func postEmptyPrefix() -> Bool {
        postUnicodeString(String(Self.emptyPrefixScalar))
    }

    @discardableResult
    private func postKey(_ keyCode: CGKeyCode, keyDown: Bool, flags: CGEventFlags = []) -> Bool {
        // HID first; session state as create fallback (some environments fail HID source).
        let attempts: [(CGEventSourceStateID, CGEventTapLocation)] = [
            (.hidSystemState, .cghidEventTap),
            (.combinedSessionState, .cgSessionEventTap),
        ]
        for (state, location) in attempts {
            let source = CGEventSource(stateID: state)
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: keyDown) else {
                continue
            }
            if !flags.isEmpty {
                event.flags = flags
            }
            SyntheticEventMarker.apply(to: event)
            event.post(tap: location)
            return true
        }
        return false
    }

    @discardableResult
    private func postUnicodeString(_ text: String) -> Bool {
        var utf16 = Array(text.utf16)
        let length = utf16.count
        guard length > 0 else { return true }

        let attempts: [(CGEventSourceStateID, CGEventTapLocation)] = [
            (.hidSystemState, .cghidEventTap),
            (.combinedSessionState, .cgSessionEventTap),
        ]
        for (state, location) in attempts {
            let source = CGEventSource(stateID: state)
            // Both down+up must be created; partial post would leave stuck keys.
            guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            else {
                continue
            }
            down.keyboardSetUnicodeString(stringLength: length, unicodeString: &utf16)
            up.keyboardSetUnicodeString(stringLength: length, unicodeString: &utf16)
            SyntheticEventMarker.apply(to: down)
            SyntheticEventMarker.apply(to: up)
            down.post(tap: location)
            up.post(tap: location)
            return true
        }
        return false
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
    /// Returns `.failure` when post access is denied or a sink post cannot create events.
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

        let textLen = text.unicodeScalars.count
        // Metadata only: method + counts + delay numbers. No text content.
        let meta =
            "method=\(method.rawValue) bs=\(backspace) textLen=\(textLen) " +
            "delays=(\(delays.backspaceUs),\(delays.settleUs),\(delays.textUs))"
        onMetadata?("inject \(meta)")

        if method == .passthrough {
            logInjectResult(meta: meta, ok: true, detail: "passthrough")
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
                onMetadata?("inject axDirect=ok textLen=\(textLen)")
                logInjectResult(meta: meta, ok: true, detail: "axDirect")
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

        // Preflight before any destructive sequence (BS + text). Avoid partial wipe.
        guard SyntheticPostAccess.isGranted else {
            onMetadata?("inject postAccess=denied")
            logInjectResult(meta: meta, ok: false, detail: "postAccessDenied")
            return .failure(.postAccessDenied)
        }

        let commands = plan(backspace: backspace, text: text, method: method, delays: delays)
        let result = execute(commands)
        switch result {
        case .success:
            logInjectResult(meta: meta, ok: true, detail: "posted")
        case .failure(let err):
            logInjectResult(meta: meta, ok: false, detail: "\(err)")
        }
        return result
    }

    /// Stderr metadata only — never raw key or text content.
    private func logInjectResult(meta: String, ok: Bool, detail: String) {
        let line = "[dau] inject \(meta) post=\(ok ? "ok" : "fail") detail=\(detail)\n"
        fputs(line, stderr)
        onMetadata?(line.trimmingCharacters(in: .newlines))
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

    private func execute(_ commands: [InjectorCommand]) -> Result<Void, InjectionError> {
        for command in commands {
            let ok: Bool
            switch command {
            case .backspace:
                ok = sink.postBackspace()
            case .unicodeChunk(let chunk):
                ok = sink.postUnicode(chunk)
            case .wait(let us):
                sleeper.sleep(microseconds: us)
                ok = true
            case .shiftLeft:
                ok = sink.postShiftLeft()
            case .emptyPrefix:
                ok = sink.postEmptyPrefix()
            }
            if !ok {
                onMetadata?("inject sink_failed command=\(commandLabel(command))")
                return .failure(.sinkFailed(commandLabel(command)))
            }
        }
        return .success(())
    }

    /// Metadata-safe label (no text content).
    private func commandLabel(_ command: InjectorCommand) -> String {
        switch command {
        case .backspace: return "backspace"
        case .unicodeChunk(let s): return "unicodeChunk(len=\(s.unicodeScalars.count))"
        case .wait(let us): return "wait(\(us))"
        case .shiftLeft: return "shiftLeft"
        case .emptyPrefix: return "emptyPrefix"
        }
    }
}
