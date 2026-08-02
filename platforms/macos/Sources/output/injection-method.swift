// Dấu macOS — InjectionMethod enum and DelayPreset (WP-03 / TG-05).
// Bridge-owned injection vocabulary; not Telex/VNI (those are engine methods).

import Foundation

/// How the bridge replaces provisional text in the focused app.
/// Names match plan §2.5 (`backspaceFast` / `backspaceSlow`, not engine `DauMethod`).
enum InjectionMethod: String, Codable, CaseIterable, Sendable, Equatable {
    /// Backspace then Unicode string; low delay (safe default).
    case backspaceFast
    /// Same sequence as `backspaceFast` with higher delays (slow render / Electron).
    case backspaceSlow
    /// Shift+Left selection then replace; empty text uses real Backspace.
    case selection
    /// Backspace then post text one Unicode scalar/chunk at a time.
    case charByChar
    /// Empty/narrow prefix to break autocomplete, then replace.
    case emptyCharPrefix
    /// Post via `CGEventTapProxy` for strict in-callback ordering.
    /// Declared-only for MVP — resolve/inject must fall back explicitly.
    case syncProxy
    /// Read/write AX value + selected range; falls back to synthetic keys on failure.
    case axDirect
    /// Do not inject; keys pass through to the app.
    case passthrough

    /// Default delay preset for this method when profile does not override.
    var defaultDelays: DelayPreset {
        switch self {
        case .backspaceFast:
            return .fast
        case .backspaceSlow:
            return .slow
        case .charByChar:
            return .charByChar
        case .selection, .emptyCharPrefix, .syncProxy, .axDirect:
            return .fast
        case .passthrough:
            return .zero
        }
    }

    /// True when a real delivery path is implemented (not a declared-only stub).
    ///
    /// - `backspaceFast` / `backspaceSlow` / `charByChar` / `passthrough`: full synthetic path.
    /// - `selection` / `emptyCharPrefix`: real Shift+Left select + empty-prefix plans.
    /// - `axDirect`: real AX attempt with explicit synthetic fallback.
    /// - `syncProxy`: declared-only stub — resolves/injects must fall back explicitly.
    var isMVPImplemented: Bool {
        switch self {
        case .backspaceFast, .backspaceSlow, .charByChar, .passthrough, .axDirect,
             .selection, .emptyCharPrefix:
            return true
        case .syncProxy:
            return false
        }
    }

    /// Delivery method that is actually implemented.
    /// The declared-only `syncProxy` stub maps explicitly to `backspaceFast`
    /// (never silent stub plans); every other method is delivered as itself.
    var deliveryImplementation: InjectionMethod {
        switch self {
        case .backspaceFast, .backspaceSlow, .charByChar, .passthrough, .axDirect,
             .selection, .emptyCharPrefix:
            return self
        case .syncProxy:
            return .backspaceFast
        }
    }

    /// Whether this method was rewritten away from a declared-only stub.
    var requiresDeliveryFallback: Bool {
        self != deliveryImplementation
    }
}

/// Microsecond delays for injection sequencing.
/// Tuple contract from plan: `(backspace_us, settle_us, text_us)` — no raw literals in injector call sites.
struct DelayPreset: Equatable, Sendable, Codable {
    /// Pause after each Backspace event (microseconds).
    var backspaceUs: UInt32
    /// Pause after all Backspaces before posting text (microseconds).
    var settleUs: UInt32
    /// Pause after text (or between char-by-char chunks) (microseconds).
    var textUs: UInt32

    static let zero = DelayPreset(backspaceUs: 0, settleUs: 0, textUs: 0)

    /// Low-latency path for responsive native text fields / terminals.
    static let fast = DelayPreset(backspaceUs: 200, settleUs: 500, textUs: 200)

    /// Higher settle for slow repaint (Electron, some terminals).
    static let slow = DelayPreset(backspaceUs: 1_000, settleUs: 3_000, textUs: 1_000)

    /// Char-by-char needs a bit more text spacing than bulk Unicode post.
    static let charByChar = DelayPreset(backspaceUs: 200, settleUs: 500, textUs: 800)

    init(backspaceUs: UInt32, settleUs: UInt32, textUs: UInt32) {
        self.backspaceUs = backspaceUs
        self.settleUs = settleUs
        self.textUs = textUs
    }

    /// True when inject must sleep (cannot complete as pure zero-delay posts).
    var requiresSleep: Bool {
        backspaceUs > 0 || settleUs > 0 || textUs > 0
    }
}

// MARK: - Delivery context (TG-05 metadata; never includes typed content)

/// Sync vs async inject scheduling (repro metadata only).
enum InjectionDeliveryMode: String, Equatable, Sendable {
    case sync
    case async
}

/// Metadata attached to one inject batch for repro / logs.
/// **Never** carry raw typed text or key codes that can reconstruct content.
struct InjectionDeliveryContext: Equatable, Sendable {
    /// Monotonic batch id from the typing session (0 when injector called standalone).
    var batchId: UInt64
    /// Frontmost app bundle id when known (may be nil in unit tests).
    var bundleId: String?
    /// Whether this inject runs before the EventTap decision returns (`sync`) or after (`async`).
    var mode: InjectionDeliveryMode
    /// Method requested by profile before stub fallback (for logs).
    var requestedMethod: InjectionMethod?

    init(
        batchId: UInt64 = 0,
        bundleId: String? = nil,
        mode: InjectionDeliveryMode = .sync,
        requestedMethod: InjectionMethod? = nil
    ) {
        self.batchId = batchId
        self.bundleId = bundleId
        self.mode = mode
        self.requestedMethod = requestedMethod
    }

    /// Metadata-only log fragment (no typed content).
    var metadataFragment: String {
        let bundle = bundleId ?? "-"
        let requested = requestedMethod.map(\.rawValue) ?? "-"
        return "batch=\(batchId) bundle=\(bundle) mode=\(mode.rawValue) requested=\(requested)"
    }
}
