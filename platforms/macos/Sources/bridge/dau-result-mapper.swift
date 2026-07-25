// Dấu macOS — map core DauResult → BridgeResult using provisional compose state.
// WP-02 / plan §2.4. Backspace count is bridge-owned (not a core ABI field).
// TG-02: UpdatePreedit uses minimal suffix delta; pure single-scalar append passes the original key.

import Foundation

/// Injection plan for TextInjector (method/delays added by WP-03).
/// `backspace` is the number of Unicode scalars to delete before inserting `text`.
struct BridgeResult: Equatable {
    var backspace: Int
    var text: String
    /// When true, the original keyDown should be suppressed (consumed).
    /// When false, forward the original event (e.g. break / empty Esc / plain append).
    var consumeOriginal: Bool
    /// Echo of core `capitalize_next` for tests / diagnostics (not used for re-casing).
    var capitalizeNext: Bool

    static let passthrough = BridgeResult(
        backspace: 0,
        text: "",
        consumeOriginal: false,
        capitalizeNext: false
    )
}

/// Pure mapping of core action + text against provisional state (§2.4 table).
enum DauResultMapper {
    /// Map one core outcome and update provisional state in place.
    ///
    /// - Parameters:
    ///   - action: `DauAction` from core (imported via bridging header).
    ///   - text: UTF-32 result already converted to `String`.
    ///   - capitalizeNext: core flag; stored on `BridgeResult` only.
    ///   - provisionalText: last injected compose text (not yet committed).
    ///   - provisionalLength: `provisionalText.unicodeScalars.count`.
    /// - Returns: `BridgeResult` for the injector / event-tap consumer.
    ///
    /// ## UpdatePreedit contract (TG-02)
    /// - **Plain append** (`new == old + one Unicode scalar`): update provisional, return
    ///   `backspace = 0`, `text = ""`, `consumeOriginal = false` so the physical key reaches
    ///   the app once (no synthetic Backspace N + full rewrite).
    /// - **Transform** (tone/mark/shape changes earlier chars): delete only the changed
    ///   suffix of provisional (`oldLen - commonPrefix`), inject only the new suffix.
    /// - Multi-scalar pure append (rare): `backspace = 0`, inject new suffix, consume key.
    static func map(
        action: DauAction,
        text: String,
        capitalizeNext: Bool = false,
        provisionalText: inout String,
        provisionalLength: inout Int
    ) -> BridgeResult {
        switch action {
        case DauAction_None:
            // P0: if we still have on-screen provisional text, wipe it then forward the key.
            // consumeOriginal=false so the original key still reaches the app after inject.
            let displayedLength = provisionalText.unicodeScalars.count
            if displayedLength > 0 {
                let wipe = displayedLength
                provisionalText = ""
                provisionalLength = 0
                return BridgeResult(
                    backspace: wipe,
                    text: "",
                    consumeOriginal: false,
                    capitalizeNext: capitalizeNext
                )
            }
            return BridgeResult(
                backspace: 0,
                text: "",
                consumeOriginal: false,
                capitalizeNext: capitalizeNext
            )

        case DauAction_UpdatePreedit:
            return mapUpdatePreedit(
                text: text,
                capitalizeNext: capitalizeNext,
                provisionalText: &provisionalText,
                provisionalLength: &provisionalLength
            )

        case DauAction_Commit:
            // If committed text equals what is already on screen, skip delete/retype.
            let unchanged = text == provisionalText
            let displayedLength = provisionalText.unicodeScalars.count
            let result = BridgeResult(
                backspace: unchanged ? 0 : displayedLength,
                text: unchanged ? "" : text,
                consumeOriginal: false, // break key is always forwarded after inject
                capitalizeNext: capitalizeNext
            )
            provisionalText = ""
            provisionalLength = 0
            return result

        case DauAction_Restore:
            // Swallow Esc when there was compose or raw text to inject; empty Esc forwards.
            let displayedLength = provisionalText.unicodeScalars.count
            let hadCompose = displayedLength > 0 || !text.isEmpty
            let result = BridgeResult(
                backspace: displayedLength,
                text: text,
                consumeOriginal: hadCompose,
                capitalizeNext: capitalizeNext
            )
            provisionalText = ""
            provisionalLength = 0
            return result

        default:
            return BridgeResult(
                backspace: 0,
                text: "",
                consumeOriginal: false,
                capitalizeNext: capitalizeNext
            )
        }
    }

    /// Convenience: map a `CoreMappedResult` from `DauCoreBridge`.
    static func map(
        _ core: CoreMappedResult,
        provisionalText: inout String,
        provisionalLength: inout Int
    ) -> BridgeResult {
        map(
            action: core.action,
            text: core.text,
            capitalizeNext: core.capitalizeNext,
            provisionalText: &provisionalText,
            provisionalLength: &provisionalLength
        )
    }

    // MARK: - UpdatePreedit delta

    private static func mapUpdatePreedit(
        text: String,
        capitalizeNext: Bool,
        provisionalText: inout String,
        provisionalLength: inout Int
    ) -> BridgeResult {
        let oldText = provisionalText
        let oldLen = oldText.unicodeScalars.count
        let newLen = text.unicodeScalars.count
        let common = commonPrefixScalarCount(oldText, text)

        // Pure single-scalar append: pass original key; document gets the physical char once.
        if newLen == oldLen + 1, common == oldLen {
            provisionalText = text
            provisionalLength = newLen
            return BridgeResult(
                backspace: 0,
                text: "",
                consumeOriginal: false,
                capitalizeNext: capitalizeNext
            )
        }

        // Multi-scalar pure append (core grew display without rewriting prefix).
        if newLen > oldLen, common == oldLen {
            let suffix = scalarSuffix(text, droppingFirst: common)
            provisionalText = text
            provisionalLength = newLen
            return BridgeResult(
                backspace: 0,
                text: suffix,
                consumeOriginal: true,
                capitalizeNext: capitalizeNext
            )
        }

        // Transform / rewrite: only replace the changed suffix (not full provisional wipe).
        let backspace = oldLen - common
        let suffix = scalarSuffix(text, droppingFirst: common)
        provisionalText = text
        provisionalLength = newLen
        return BridgeResult(
            backspace: backspace,
            text: suffix,
            consumeOriginal: true,
            capitalizeNext: capitalizeNext
        )
    }

    /// Count of leading Unicode scalars shared by `a` and `b`.
    static func commonPrefixScalarCount(_ a: String, _ b: String) -> Int {
        let aScalars = a.unicodeScalars
        let bScalars = b.unicodeScalars
        var ai = aScalars.startIndex
        var bi = bScalars.startIndex
        var count = 0
        while ai < aScalars.endIndex, bi < bScalars.endIndex, aScalars[ai] == bScalars[bi] {
            count += 1
            ai = aScalars.index(after: ai)
            bi = bScalars.index(after: bi)
        }
        return count
    }

    /// Drop the first `n` Unicode scalars of `s` and return the remainder as `String`.
    static func scalarSuffix(_ s: String, droppingFirst n: Int) -> String {
        if n <= 0 { return s }
        let scalars = s.unicodeScalars
        if n >= scalars.count { return "" }
        var idx = scalars.startIndex
        for _ in 0..<n {
            idx = scalars.index(after: idx)
        }
        return String(String.UnicodeScalarView(scalars[idx...]))
    }
}
