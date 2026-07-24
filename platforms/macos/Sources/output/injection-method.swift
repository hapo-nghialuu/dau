// Dấu macOS — InjectionMethod enum and DelayPreset (WP-03).
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
    case syncProxy
    /// Read/write AX value + selected range; fallback to synthetic keys.
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

    /// True when MVP implements a real synthetic key path (not only a stub).
    var isMVPImplemented: Bool {
        switch self {
        case .backspaceFast, .backspaceSlow, .charByChar, .passthrough:
            return true
        case .selection, .emptyCharPrefix, .syncProxy, .axDirect:
            return false
        }
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
}
