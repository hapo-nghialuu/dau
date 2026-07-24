// Dấu macOS — Carbon TIS input-source gating (WP-06 / P2.2).
// Blocks typing when the active source is a Vietnamese IME or non-Latin script.

import Carbon
import Foundation

/// Observes keyboard input source changes and reports whether Dấu should stand down.
final class InputSourceObserver {
    /// Called on the main queue when blocked state flips.
    var onBlockedChange: ((_ blocked: Bool, _ sourceID: String?) -> Void)?

    private(set) var isBlocked: Bool = false
    private(set) var currentSourceID: String?
    private var observer: Any?
    private(set) var isRunning = false

    deinit {
        stop()
    }

    func start() {
        guard !isRunning else { return }
        observer = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refresh()
        }
        isRunning = true
        refresh()
    }

    func stop() {
        if let observer {
            DistributedNotificationCenter.default().removeObserver(observer)
            self.observer = nil
        }
        isRunning = false
    }

    /// Re-read the current input source and update `isBlocked`.
    @discardableResult
    func refresh() -> Bool {
        let id = Self.currentInputSourceID()
        let blocked = Self.shouldBlock(sourceID: id)
        let changed = blocked != isBlocked || id != currentSourceID
        currentSourceID = id
        isBlocked = blocked
        if changed {
            onBlockedChange?(blocked, id)
        }
        return blocked
    }

    // MARK: - Classification (testable)

    /// Returns true when Dấu must not inject for this source.
    static func shouldBlock(sourceID: String?) -> Bool {
        guard let sourceID, !sourceID.isEmpty else {
            // Unknown: fail open so Latin layouts without a clear id still work.
            return false
        }
        let lower = sourceID.lowercased()

        // Unicode Hex Input and similar.
        if lower.contains("unicodehex") || lower.contains("unicode hex") {
            return true
        }

        // Vietnamese IME / third-party IME markers (not raw Latin keylayouts).
        let imeMarkers = [
            "vietnamese", "vi-t9", "unikey", "bogo", "evkey",
            "openvietnamese", "gotiengviet", "simple telex",
        ]
        for marker in imeMarkers {
            if lower.contains(marker) {
                return true
            }
        }
        // Generic input-method plugins (Apple SCIM, Kotoeri, etc.).
        if lower.contains("inputmethod") || lower.contains(".ime") {
            return true
        }

        // Non-Latin / non-European scripts that conflict with Vietnamese compose.
        let nonLatinLayouts = [
            "keylayout.russian", "keylayout.ukrainian", "keylayout.bulgarian",
            "keylayout.greek", "keylayout.hebrew", "keylayout.arabic",
            "keylayout.korean", "keylayout.japanese", "keylayout.chinese",
            "keylayout.thai", "keylayout.hindi", "keylayout.devanagari",
            "keylayout.persian", "keylayout.armenian", "keylayout.georgian",
        ]
        for marker in nonLatinLayouts {
            if lower.contains(marker) {
                return true
            }
        }

        // Known Latin keylayouts: allow.
        if lower.contains("keylayout.") {
            return false
        }

        // Unknown non-keylayout source: be conservative and block.
        return true
    }

    static func currentInputSourceID() -> String? {
        guard let unmanaged = TISCopyCurrentKeyboardInputSource() else {
            return nil
        }
        let source = unmanaged.takeRetainedValue()
        guard let cf = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else {
            return nil
        }
        return Unmanaged<CFString>.fromOpaque(cf).takeUnretainedValue() as String
    }
}
