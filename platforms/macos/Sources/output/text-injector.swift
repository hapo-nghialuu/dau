// Dấu macOS — TextInjector: replacement sequencing (WP-03 / TG-05).
// Posts Backspace + Unicode via a pluggable EventSink; never logs text content.
// Dead-key guard: sink reports post failures; session must fail-open (not consume) when inject cannot run.
// Declared-only methods fall back explicitly to an implemented path (no silent stubs).

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
///
/// TG-00: hot path reads a **cached** capability snapshot only.
/// `CGRequestPostEventAccess()` is allowed from setup/recovery UI via `refreshFromSystem(prompt:)`,
/// never from the keyboard EventTap callback.
enum SyntheticPostAccess {
    /// Hot-path check. Default reads `cachedGranted` only — never prompts, never preflights OS.
    /// Overridable in unit tests (including a blocking latch to prove EN bypass).
    static var check: () -> Bool = { cachedGranted }

    private static let lock = NSLock()
    /// Cached OS post-event capability. Refresh off the keyboard hot path.
    private static var _cachedGranted = false
    /// True after at least one UI-initiated `CGRequestPostEventAccess` this process.
    /// Used for onboarding copy only — does **not** block further UI re-prompts.
    private static var _didRequestThisProcess = false

    static var isGranted: Bool { check() }

    /// Thread-safe snapshot used by default `check`.
    static var cachedGranted: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _cachedGranted
    }

    /// Whether setup UI has already asked the OS for post-event access this process.
    static var didRequestThisProcess: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _didRequestThisProcess
    }

    /// Test / lifecycle hook to set the snapshot without touching OS APIs.
    static func setCachedGranted(_ value: Bool) {
        lock.lock()
        _cachedGranted = value
        lock.unlock()
    }

    /// Refresh cache from the OS.
    /// - Parameter prompt: when true, may call `CGRequestPostEventAccess()` (setup/recovery UI only).
    ///   Each explicit UI click may request again; hot path / poll always uses `prompt: false`.
    static func refreshFromSystem(prompt: Bool = false) {
        if #available(macOS 10.15, *) {
            if CGPreflightPostEventAccess() {
                setCachedGranted(true)
                return
            }
            if prompt {
                lock.lock()
                _didRequestThisProcess = true
                lock.unlock()
                // Explicit UI recovery may re-request. OS may still not re-show a dialog
                // after a prior denial — onboarding must guide the user to System Settings.
                fputs("[dau] post-event access denied; requesting (UI)\n", stderr)
                _ = CGRequestPostEventAccess()
                let granted = CGPreflightPostEventAccess()
                setCachedGranted(granted)
                if granted {
                    fputs("[dau] post-event access granted after request\n", stderr)
                } else {
                    fputs("[dau] post-event access denied after request\n", stderr)
                }
            } else {
                setCachedGranted(false)
                fputs("[dau] post-event access denied (cached, no prompt)\n", stderr)
            }
        } else {
            // Pre-10.15: no separate post-access API; Accessibility trust is the practical gate.
            setCachedGranted(true)
        }
    }

    static func resetToDefault() {
        lock.lock()
        _didRequestThisProcess = false
        _cachedGranted = false
        lock.unlock()
        check = { cachedGranted }
    }
}

// MARK: - Command plan

/// Ordered injector steps. Unit tests assert plan shape without posting real keys.
enum InjectorCommand: Equatable, Sendable {
    case backspace
    case unicodeChunk(String)
    case wait(microseconds: UInt32)
    /// Shift+Left once (legacy stub plan structure; delivery falls back before execute).
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
    /// Fail only the Nth post (1-based). `nil` = use `shouldSucceed` for every post.
    /// Used to prove mid-batch failure does not report false success (TG-05).
    var failAtCommandIndex: Int?

    private var postIndex = 0

    func reset() {
        commands.removeAll(keepingCapacity: true)
        postIndex = 0
    }

    private func recordAndResult(_ command: InjectorCommand) -> Bool {
        commands.append(command)
        postIndex += 1
        if let failAt = failAtCommandIndex, postIndex == failAt {
            return false
        }
        return shouldSucceed
    }

    @discardableResult
    func postBackspace() -> Bool {
        recordAndResult(.backspace)
    }

    @discardableResult
    func postUnicode(_ text: String) -> Bool {
        recordAndResult(.unicodeChunk(text))
    }

    @discardableResult
    func postShiftLeft() -> Bool {
        recordAndResult(.shiftLeft)
    }

    @discardableResult
    func postEmptyPrefix() -> Bool {
        recordAndResult(.emptyPrefix)
    }
}

/// In-memory target document for delivery tests (TG-05).
/// Models what a focused text field would contain after physical keys + synthetic inject.
final class FakeTargetDocument: InjectorEventSink {
    private(set) var content: String = ""
    /// When false, the next sink post fails (and is not applied).
    var shouldSucceed: Bool = true
    /// Fail only the Nth post (1-based). `nil` = use `shouldSucceed`.
    var failAtCommandIndex: Int?
    private var postIndex = 0

    func reset() {
        content = ""
        postIndex = 0
        shouldSucceed = true
        failAtCommandIndex = nil
    }

    /// Seed document content for unit tests (not used by production inject path).
    func seed(_ text: String) {
        content = text
        postIndex = 0
    }

    /// Apply a physical key that the EventTap passed through (not consumed).
    func applyPhysicalKey(_ text: String) {
        content.append(text)
    }

    /// Apply a physical Backspace that the EventTap passed through.
    func applyPhysicalBackspace() {
        guard !content.isEmpty else { return }
        content = String(content.unicodeScalars.dropLast())
    }

    private func beginPost() -> Bool {
        postIndex += 1
        if let failAt = failAtCommandIndex, postIndex == failAt {
            return false
        }
        return shouldSucceed
    }

    @discardableResult
    func postBackspace() -> Bool {
        guard beginPost() else { return false }
        applyPhysicalBackspace()
        return true
    }

    @discardableResult
    func postUnicode(_ text: String) -> Bool {
        guard beginPost() else { return false }
        content.append(text)
        return true
    }

    @discardableResult
    func postShiftLeft() -> Bool {
        // Selection stub is not a real delivery path; treat as no-op success for harness safety.
        beginPost()
    }

    @discardableResult
    func postEmptyPrefix() -> Bool {
        guard beginPost() else { return false }
        content.append("\u{202F}")
        return true
    }
}

/// Production sink: CGEvent keyboard posts with synthetic marker.
/// Primary: private event source posted at the session tap — synthetic events enter the
/// stream downstream of the keyboard tap, so ordering vs. physical keys is deterministic
/// (posting at the HID tap re-enters upstream and races repaint-heavy apps like terminals).
/// Injection strategy (post location + source) ported from Gõ Nhanh `RustBridge.swift`
/// (BSD-3-Clause — see NOTICE).
final class CGEventInjectorSink: InjectorEventSink {
    /// Virtual key code for Delete/Backspace (Carbon `kVK_Delete`).
    private static let backspaceKeyCode: CGKeyCode = 51
    /// Virtual key code for Left Arrow (`kVK_LeftArrow`).
    private static let leftArrowKeyCode: CGKeyCode = 123
    /// Narrow no-break space (U+202F) used by empty-char-prefix method.
    private static let emptyPrefixScalar: Unicode.Scalar = "\u{202F}"

    /// Reused event source: creating a source per event does WindowServer IPC and can
    /// blow the 12ms callback budget; Gõ Nhanh likewise reuses one source per batch.
    /// Sink calls are serialized by TextInjector's lock, so no extra locking here.
    private var cachedSource: CGEventSource?

    private func eventSource() -> CGEventSource? {
        if cachedSource == nil {
            cachedSource = CGEventSource(stateID: .privateState)
                ?? CGEventSource(stateID: .combinedSessionState)
        }
        return cachedSource
    }

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
        // Session tap: synthetic events enter downstream of the keyboard tap, so ordering
        // vs. physical keys is deterministic (HID posting re-enters upstream and races).
        guard let event = CGEvent(
            keyboardEventSource: eventSource(),
            virtualKey: keyCode,
            keyDown: keyDown
        ) else {
            return false
        }
        if !flags.isEmpty {
            event.flags = flags
        }
        SyntheticEventMarker.apply(to: event)
        event.post(tap: .cgSessionEventTap)
        return true
    }

    @discardableResult
    private func postUnicodeString(_ text: String) -> Bool {
        var utf16 = Array(text.utf16)
        let length = utf16.count
        guard length > 0 else { return true }

        // Both down+up must be created; partial post would leave stuck keys.
        let source = eventSource()
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
        else {
            return false
        }
        down.keyboardSetUnicodeString(stringLength: length, unicodeString: &utf16)
        up.keyboardSetUnicodeString(stringLength: length, unicodeString: &utf16)
        SyntheticEventMarker.apply(to: down)
        SyntheticEventMarker.apply(to: up)
        down.post(tap: .cgSessionEventTap)
        up.post(tap: .cgSessionEventTap)
        return true
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
/// Logs only method / lengths / delays / batch metadata — never raw key or text content.
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
    /// Always plans the **delivery** method (stubs rewritten to implemented path).
    func plan(
        backspace: Int,
        text: String,
        method: InjectionMethod,
        delays: DelayPreset
    ) -> [InjectorCommand] {
        guard backspace >= 0 else { return [] }
        let delivery = method.deliveryImplementation

        switch delivery {
        case .passthrough:
            return []

        case .backspaceFast, .backspaceSlow:
            return planBackspaceThenText(backspace: backspace, text: text, delays: delays, charByChar: false)

        case .charByChar:
            return planBackspaceThenText(backspace: backspace, text: text, delays: delays, charByChar: true)

        case .axDirect:
            // Plan inspects the synthetic fallback path (AX is attempted only at inject time).
            return planBackspaceThenText(backspace: backspace, text: text, delays: delays, charByChar: false)

        case .selection, .emptyCharPrefix, .syncProxy:
            // Unreachable: deliveryImplementation rewrites these to backspaceFast.
            return planBackspaceThenText(backspace: backspace, text: text, delays: delays, charByChar: false)
        }
    }

    /// Inject replacement. Safe for concurrent callers (serialized). Never logs `text`.
    /// Returns `.failure` when post access is denied or a sink post cannot create events.
    /// Mid-batch sink failure aborts remaining commands and returns `.failure` (no false success).
    @discardableResult
    func inject(
        backspace: Int,
        text: String,
        method: InjectionMethod,
        delays: DelayPreset,
        context: InjectionDeliveryContext = InjectionDeliveryContext()
    ) -> Result<Void, InjectionError> {
        guard backspace >= 0 else {
            return .failure(.invalidBackspaceCount)
        }

        lock.lock()
        defer { lock.unlock() }

        let requested = context.requestedMethod ?? method
        let delivery = method.deliveryImplementation
        if delivery != method || (context.requestedMethod.map { $0 != delivery } ?? false) {
            let line =
                "[dau] inject method fallback: \(context.metadataFragment) " +
                "requested=\(requested.rawValue) delivered=\(delivery.rawValue)\n"
            fputs(line, stderr)
            onMetadata?(line.trimmingCharacters(in: .newlines))
        }

        let textLen = text.unicodeScalars.count
        // Metadata only: method + counts + delays + batch context. No text content.
        let meta =
            "method=\(delivery.rawValue) bs=\(backspace) textLen=\(textLen) " +
            "delays=(\(delays.backspaceUs),\(delays.settleUs),\(delays.textUs)) " +
            context.metadataFragment
        onMetadata?("inject \(meta)")

        if delivery == .passthrough {
            logInjectResult(meta: meta, ok: true, detail: "passthrough")
            return .success(())
        }

        if delivery == .axDirect {
            // Attempt AX path; fall back to synthetic on any failure (no crash).
            let axResult = axAccessor.replaceFocusedText(
                deleteScalarCount: backspace,
                replacement: text
            )
            switch axResult {
            case .success:
                onMetadata?("inject axDirect=ok textLen=\(textLen) \(context.metadataFragment)")
                logInjectResult(meta: meta, ok: true, detail: "axDirect")
                return .success(())
            case .failure(let err):
                onMetadata?("inject axDirect=fallback error=\(err) \(context.metadataFragment)")
                // Fall through to synthetic plan.
            }
        }

        // Preflight before any destructive sequence (BS + text). Avoid partial wipe.
        guard SyntheticPostAccess.isGranted else {
            onMetadata?("inject postAccess=denied \(context.metadataFragment)")
            logInjectResult(meta: meta, ok: false, detail: "postAccessDenied")
            return .failure(.postAccessDenied)
        }

        let commands = plan(backspace: backspace, text: text, method: delivery, delays: delays)
        let executeStart = DispatchTime.now().uptimeNanoseconds
        let result = execute(commands)
        let executeMs = Double(DispatchTime.now().uptimeNanoseconds &- executeStart) / 1_000_000
        switch result {
        case .success:
            logInjectResult(meta: meta, ok: true, detail: "posted", durationMs: executeMs)
        case .failure(let err):
            logInjectResult(meta: meta, ok: false, detail: "\(err)", durationMs: executeMs)
        }
        return result
    }

    /// Stderr metadata only — never raw key or text content.
    private func logInjectResult(meta: String, ok: Bool, detail: String, durationMs: Double? = nil) {
        let dur = durationMs.map { String(format: " durMs=%.1f", $0) } ?? ""
        let line = "[dau] inject \(meta) post=\(ok ? "ok" : "fail") detail=\(detail)\(dur)\n"
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

    // MARK: Execution

    /// Execute commands in order. **First sink failure aborts** remaining steps and returns failure.
    /// Never reports success after a failed command (TG-05).
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
