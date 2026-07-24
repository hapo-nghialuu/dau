// Dấu macOS — AXTextAccessor: bounded Accessibility helpers (WP-03).
// Timeout-first; full AX injection is P3 — stubs + synthetic fallback must not crash.

import ApplicationServices
import Foundation

// MARK: - Errors

enum AXAccessError: Error, Equatable, Sendable {
    case notTrusted
    case noFocusedElement
    case unsupportedAttribute
    case typeMismatch
    case messagingFailed(String)
    case timeout
    case notImplemented
}

// MARK: - Snapshot types

struct AXTextSnapshot: Equatable, Sendable {
    var value: String?
    /// UTF-16 location/length from AX selected-text range when available.
    var selectedUTF16Range: (location: Int, length: Int)?

    static func == (lhs: AXTextSnapshot, rhs: AXTextSnapshot) -> Bool {
        lhs.value == rhs.value
            && lhs.selectedUTF16Range?.location == rhs.selectedUTF16Range?.location
            && lhs.selectedUTF16Range?.length == rhs.selectedUTF16Range?.length
    }
}

// MARK: - Accessor

/// Thin AX wrapper with messaging timeout. Callers must treat failures as fallback triggers.
final class AXTextAccessor {
    /// Default AX messaging timeout (seconds). Keep well under event-tap watchdog budget.
    static let defaultTimeoutSeconds: Float = 0.05

    /// Cap applied to any caller-supplied timeout.
    static let maxTimeoutSeconds: Float = 0.25

    private(set) var messagingTimeoutSeconds: Float

    init(messagingTimeoutSeconds: Float = AXTextAccessor.defaultTimeoutSeconds) {
        self.messagingTimeoutSeconds = Self.clampTimeout(messagingTimeoutSeconds)
    }

    func setMessagingTimeout(_ seconds: Float) {
        messagingTimeoutSeconds = Self.clampTimeout(seconds)
    }

    static func clampTimeout(_ seconds: Float) -> Float {
        if seconds.isNaN || seconds < 0 { return defaultTimeoutSeconds }
        return min(seconds, maxTimeoutSeconds)
    }

    // MARK: Trust / focus

    func isProcessTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    /// Applies messaging timeout to an element (best-effort; ignore failure).
    func applyTimeout(to element: AXUIElement) {
        AXUIElementSetMessagingTimeout(element, messagingTimeoutSeconds)
    }

    /// Focused UI element under the system-wide AX hierarchy, or nil.
    func focusedElement() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        applyTimeout(to: system)

        var focused: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(
            system,
            kAXFocusedUIElementAttribute as CFString,
            &focused
        )
        guard status == .success, let focused else {
            return nil
        }
        // AXUIElement is a CFType; bridge without force-cast crash paths.
        let element = focused as! AXUIElement
        applyTimeout(to: element)
        return element
    }

    // MARK: Read / write (bounded)

    func readValue(of element: AXUIElement) -> Result<String, AXAccessError> {
        applyTimeout(to: element)
        var raw: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &raw)
        guard status == .success else {
            return .failure(.messagingFailed("copyValue status=\(status.rawValue)"))
        }
        guard let raw else {
            return .failure(.unsupportedAttribute)
        }
        if CFGetTypeID(raw) == CFStringGetTypeID() {
            return .success(raw as! String)
        }
        return .failure(.typeMismatch)
    }

    func writeValue(_ text: String, of element: AXUIElement) -> Result<Void, AXAccessError> {
        applyTimeout(to: element)
        let status = AXUIElementSetAttributeValue(
            element,
            kAXValueAttribute as CFString,
            text as CFString
        )
        guard status == .success else {
            return .failure(.messagingFailed("setValue status=\(status.rawValue)"))
        }
        return .success(())
    }

    func readSelectedUTF16Range(of element: AXUIElement) -> Result<(location: Int, length: Int), AXAccessError> {
        applyTimeout(to: element)
        var raw: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &raw
        )
        guard status == .success, let raw else {
            return .failure(.messagingFailed("copySelectedRange status=\(status.rawValue)"))
        }
        var range = CFRange(location: 0, length: 0)
        if CFGetTypeID(raw) == AXValueGetTypeID() {
            let axValue = raw as! AXValue
            guard AXValueGetValue(axValue, .cfRange, &range) else {
                return .failure(.typeMismatch)
            }
            return .success((location: range.location, length: range.length))
        }
        return .failure(.typeMismatch)
    }

    /// Snapshot focused field value + selection. Fails fast when untrusted or unavailable.
    func snapshotFocused() -> Result<AXTextSnapshot, AXAccessError> {
        guard isProcessTrusted() else {
            return .failure(.notTrusted)
        }
        guard let element = focusedElement() else {
            return .failure(.noFocusedElement)
        }
        let value = try? readValue(of: element).get()
        let range = try? readSelectedUTF16Range(of: element).get()
        return .success(AXTextSnapshot(value: value, selectedUTF16Range: range))
    }

    /// Replace focused text by deleting `deleteScalarCount` trailing scalars then writing `replacement`.
    ///
    /// MVP: full AX range math + UTF-16 conversion is P3.5. This method attempts a best-effort
    /// value rewrite when possible; otherwise returns a failure so TextInjector can fall back
    /// to synthetic Backspace + Unicode without crashing.
    func replaceFocusedText(deleteScalarCount: Int, replacement: String) -> Result<Void, AXAccessError> {
        guard deleteScalarCount >= 0 else {
            return .failure(.messagingFailed("negative delete count"))
        }
        guard isProcessTrusted() else {
            return .failure(.notTrusted)
        }
        guard let element = focusedElement() else {
            return .failure(.noFocusedElement)
        }

        // TODO(P3.5): convert scalar delete count → UTF-16 offsets, set selected range,
        // then set value / selected text atomically and restore cursor.
        // Current path: only succeed when delete count is 0 and writeValue works; else fail → synthetic.
        if deleteScalarCount == 0 {
            return writeValue(replacement, of: element)
        }

        // Structured stub: signal fallback rather than inventing incomplete UTF-16 edits.
        return .failure(.notImplemented)
    }
}
