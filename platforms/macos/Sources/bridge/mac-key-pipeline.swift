// Dấu macOS — compose / provisional state machine over DauCoreBridge + DauResultMapper.
// WP-02 + P0 review: delete-during-compose wipe, None-while-composing wipe.

import Foundation

/// Classifies input for the pipeline without depending on CGEvent (WP-04 owns real classifier).
enum PipelineKeyKind: Equatable {
    case printable
    case breakKey
    case escape
    /// Delete/Backspace while composing: wipe provisional and consume OS key.
    case delete
    case boundary  // navigation / modifier / other — reset compose, forward
}

/// Owns provisional compose state and routes keys through core + §2.4 mapping.
final class MacKeyPipeline {
    private let bridge: DauCoreBridge

    /// Last text injected into the target while composing (not yet committed).
    private(set) var provisionalText: String = ""
    /// Unicode scalar count of `provisionalText` (source of backspace count).
    private(set) var provisionalLength: Int = 0
    /// Last `capitalize_next` from core (diagnostic; core keeps real state).
    private(set) var lastCapitalizeNext: Bool = false

    init(bridge: DauCoreBridge = DauCoreBridge()) {
        self.bridge = bridge
    }

    var core: DauCoreBridge { bridge }

    // MARK: - Key handling

    /// Process a printable Unicode scalar through `dau_process_char`.
    @discardableResult
    func handlePrintable(_ ch: UInt32, caps: Bool = false) -> BridgeResult {
        apply(bridge.processChar(ch, caps: caps))
    }

    @discardableResult
    func handlePrintable(_ scalar: Unicode.Scalar, caps: Bool = false) -> BridgeResult {
        handlePrintable(scalar.value, caps: caps)
    }

    /// End word via `dau_on_break`. Break character is not part of committed text.
    /// `consumeOriginal` is false so the caller forwards the original break key.
    @discardableResult
    func handleBreak(_ brk: UInt32) -> BridgeResult {
        apply(bridge.onBreak(brk))
    }

    @discardableResult
    func handleBreak(_ scalar: Unicode.Scalar) -> BridgeResult {
        handleBreak(scalar.value)
    }

    /// Esc / restore path via `dau_escape`.
    @discardableResult
    func handleEscape() -> BridgeResult {
        apply(bridge.escape())
    }

    /// Delete / Backspace during compose: wipe all provisional scalars and consume OS delete.
    /// When not composing, passthrough so the app receives the real Delete key.
    @discardableResult
    func handleDelete() -> BridgeResult {
        if provisionalLength <= 0 {
            return .passthrough
        }
        let wipe = provisionalLength
        resetCompose()
        return BridgeResult(
            backspace: wipe,
            text: "",
            consumeOriginal: true,
            capitalizeNext: false
        )
    }

    /// Unified entry used by EventTap / TypingSession wiring.
    @discardableResult
    func handle(kind: PipelineKeyKind, ch: UInt32 = 0, caps: Bool = false) -> BridgeResult {
        switch kind {
        case .printable:
            return handlePrintable(ch, caps: caps)
        case .breakKey:
            return handleBreak(ch)
        case .escape:
            return handleEscape()
        case .delete:
            return handleDelete()
        case .boundary:
            resetCompose()
            return .passthrough
        }
    }

    /// Handle a classifier result (including `.delete`).
    @discardableResult
    func handleClassified(_ key: ClassifiedKey) -> BridgeResult {
        switch key.kind {
        case .printable(let scalar):
            // Shift held → uppercase for auto-cap / Telex capital letters.
            return handlePrintable(scalar, caps: key.shiftHeld)
        case .breakKey(let scalar):
            return handleBreak(scalar)
        case .escape:
            return handleEscape()
        case .delete:
            return handleDelete()
        case .modifier, .other:
            resetCompose()
            return .passthrough
        }
    }

    /// Clear provisional state and core buffer (focus change, toggle EN, tap restart).
    func resetCompose() {
        provisionalText = ""
        provisionalLength = 0
        lastCapitalizeNext = false
        bridge.clear()
    }

    /// Clear provisional tracking only (when document was already rewritten externally).
    func clearProvisionalOnly() {
        provisionalText = ""
        provisionalLength = 0
    }

    // MARK: - Private

    private func apply(_ core: CoreMappedResult) -> BridgeResult {
        lastCapitalizeNext = core.capitalizeNext
        // Snapshot before mapper may clear provisional on None-while-composing.
        let hadProvisional = provisionalLength > 0
        let result = DauResultMapper.map(
            core,
            provisionalText: &provisionalText,
            provisionalLength: &provisionalLength
        )
        // Core must not keep a stale word when None wiped provisional.
        if core.action == DauAction_None, hadProvisional, result.backspace > 0 {
            bridge.clear()
        }
        return result
    }
}
