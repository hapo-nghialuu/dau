// Dấu macOS — map core DauDeltaResult → BridgeResult using provisional compose state.
// Core already returns display delta (backspace + insert). Mapper:
// - keeps provisional in sync by applying that delta
// - keeps TG-02 plain single-scalar append pass-through
// - maps Commit / Restore / None against provisional
//
// Delta contract derived from Gõ Nhanh (BSD-3-Clause,
// Copyright (c) 2025 Gõ Nhanh Contributors). See repo root NOTICE.

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

/// Pure mapping of core delta + action against provisional state.
enum DauResultMapper {
    /// Map one core outcome and update provisional state in place.
    ///
    /// - Parameters:
    ///   - action: `DauAction` from core (imported via bridging header).
    ///   - backspace: core delete count (Unicode scalars).
    ///   - text: core **insert-only** payload (not full preedit).
    ///   - capitalizeNext: core flag; stored on `BridgeResult` only.
    ///   - provisionalText: last injected compose text (not yet committed).
    ///   - provisionalLength: `provisionalText.unicodeScalars.count`.
    /// - Returns: `BridgeResult` for the injector / event-tap consumer.
    ///
    /// ## UpdatePreedit contract (TG-02, core-owned delta)
    /// - **Plain append** (core `backspace == 0`, single-scalar insert that grows
    ///   provisional by one): update provisional, return `backspace = 0`,
    ///   `text = ""`, `consumeOriginal = false` so the physical key reaches the app.
    /// - **Transform / multi-scalar insert**: forward core `backspace` + `text`,
    ///   consume the key, update provisional by applying the same delta.
    static func map(
        action: DauAction,
        backspace: Int,
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
                backspace: backspace,
                text: text,
                capitalizeNext: capitalizeNext,
                provisionalText: &provisionalText,
                provisionalLength: &provisionalLength
            )

        case DauAction_Commit:
            // Core already computed delta from previous composing display → commit text.
            let result = BridgeResult(
                backspace: max(0, backspace),
                text: text,
                consumeOriginal: false, // break key is always forwarded after inject
                capitalizeNext: capitalizeNext
            )
            provisionalText = ""
            provisionalLength = 0
            return result

        case DauAction_Restore:
            // Apply core delta; keep provisional in sync with core pass-through buffer
            // so subsequent keys under the delta contract stay correct.
            let applied = applyDelta(
                to: provisionalText,
                backspace: backspace,
                insert: text
            )
            let displayedLength = provisionalText.unicodeScalars.count
            let hadCompose = displayedLength > 0 || !text.isEmpty || backspace > 0
            let result = BridgeResult(
                backspace: max(0, backspace),
                text: text,
                consumeOriginal: hadCompose,
                capitalizeNext: capitalizeNext
            )
            provisionalText = applied
            provisionalLength = applied.unicodeScalars.count
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
            backspace: core.backspace,
            text: core.text,
            capitalizeNext: core.capitalizeNext,
            provisionalText: &provisionalText,
            provisionalLength: &provisionalLength
        )
    }

    // MARK: - UpdatePreedit

    private static func mapUpdatePreedit(
        backspace: Int,
        text: String,
        capitalizeNext: Bool,
        provisionalText: inout String,
        provisionalLength: inout Int
    ) -> BridgeResult {
        let oldLen = provisionalText.unicodeScalars.count
        let insertCount = text.unicodeScalars.count
        let newText = applyDelta(to: provisionalText, backspace: backspace, insert: text)
        let newLen = newText.unicodeScalars.count

        // Pure single-scalar append: pass original key; document gets the physical char once.
        if backspace == 0, insertCount == 1, newLen == oldLen + 1 {
            provisionalText = newText
            provisionalLength = newLen
            return BridgeResult(
                backspace: 0,
                text: "",
                consumeOriginal: false,
                capitalizeNext: capitalizeNext
            )
        }

        // Multi-scalar pure append (core grew display without rewriting prefix).
        if backspace == 0, insertCount > 0 {
            provisionalText = newText
            provisionalLength = newLen
            return BridgeResult(
                backspace: 0,
                text: text,
                consumeOriginal: true,
                capitalizeNext: capitalizeNext
            )
        }

        // No-op display (e.g. absorbed key): still consume; no inject.
        if backspace == 0, insertCount == 0 {
            provisionalText = newText
            provisionalLength = newLen
            return BridgeResult(
                backspace: 0,
                text: "",
                consumeOriginal: true,
                capitalizeNext: capitalizeNext
            )
        }

        // Transform / rewrite: forward core delta.
        provisionalText = newText
        provisionalLength = newLen
        return BridgeResult(
            backspace: max(0, backspace),
            text: text,
            consumeOriginal: true,
            capitalizeNext: capitalizeNext
        )
    }

    /// Apply host delta: delete `backspace` trailing scalars, then append `insert`.
    static func applyDelta(to base: String, backspace: Int, insert: String) -> String {
        var scalars = Array(base.unicodeScalars)
        let drop = min(max(0, backspace), scalars.count)
        if drop > 0 {
            scalars.removeLast(drop)
        }
        var view = String.UnicodeScalarView(scalars)
        for s in insert.unicodeScalars {
            view.append(s)
        }
        return String(view)
    }
}
