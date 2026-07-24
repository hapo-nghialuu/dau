// Dấu macOS — map core DauResult → BridgeResult using provisional compose state.
// WP-02 / plan §2.4. Backspace count is bridge-owned (not a core ABI field).

import Foundation

/// Injection plan for TextInjector (method/delays added by WP-03).
/// `backspace` is the number of Unicode scalars to delete before inserting `text`.
struct BridgeResult: Equatable {
    var backspace: Int
    var text: String
    /// When true, the original keyDown should be suppressed (consumed).
    /// When false, forward the original event (e.g. break / empty Esc).
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
            if provisionalLength > 0 {
                let wipe = provisionalLength
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
            let result = BridgeResult(
                backspace: provisionalLength,
                text: text,
                consumeOriginal: true,
                capitalizeNext: capitalizeNext
            )
            provisionalText = text
            provisionalLength = text.unicodeScalars.count
            return result

        case DauAction_Commit:
            // If committed text equals what is already on screen, skip delete/retype.
            let unchanged = text == provisionalText
            let result = BridgeResult(
                backspace: unchanged ? 0 : provisionalLength,
                text: unchanged ? "" : text,
                consumeOriginal: false, // break key is always forwarded after inject
                capitalizeNext: capitalizeNext
            )
            provisionalText = ""
            provisionalLength = 0
            return result

        case DauAction_Restore:
            // Swallow Esc when there was compose or raw text to inject; empty Esc forwards.
            let hadCompose = provisionalLength > 0 || !text.isEmpty
            let result = BridgeResult(
                backspace: provisionalLength,
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
}
