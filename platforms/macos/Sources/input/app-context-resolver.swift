// Dấu macOS — frontmost app + optional AX role cache (WP-05 / P2.3).
// Hot path must read the cache only; refresh is explicit / on invalidate.

import AppKit
import ApplicationServices
import Foundation

// MARK: - Providers (test seams)

/// Supplies the current frontmost application identity.
protocol FrontmostAppProviding: AnyObject {
    func frontmostApp() -> (bundleId: String?, appName: String?)
}

/// Optional AX role probe. MVP may return `nil` (stub / timeout / untrusted).
protocol AXRoleProviding: AnyObject {
    func focusedRoleCategory() -> AXRoleCategory?
}

/// Default frontmost provider via `NSWorkspace`.
final class WorkspaceFrontmostAppProvider: FrontmostAppProviding {
    func frontmostApp() -> (bundleId: String?, appName: String?) {
        let app = NSWorkspace.shared.frontmostApplication
        return (app?.bundleIdentifier, app?.localizedName)
    }
}

/// Bounded AX role probe. Never blocks longer than the accessor messaging timeout.
/// Returns `nil` when Accessibility is denied, no focused element, or role is unknown.
final class AXFocusedRoleProvider: AXRoleProviding {
    private let accessor: AXTextAccessor

    init(accessor: AXTextAccessor = AXTextAccessor()) {
        self.accessor = accessor
    }

    func focusedRoleCategory() -> AXRoleCategory? {
        guard accessor.isProcessTrusted() else {
            return nil
        }
        guard let element = accessor.focusedElement() else {
            return nil
        }
        return Self.classify(element: element, accessor: accessor)
    }

    /// Map AX role / subrole / description tokens → `AXRoleCategory`.
    /// Returns `nil` when classification is inconclusive (MVP-safe).
    static func classify(element: AXUIElement, accessor: AXTextAccessor) -> AXRoleCategory? {
        accessor.applyTimeout(to: element)

        let role = copyStringAttribute(element, kAXRoleAttribute as CFString) ?? ""
        let subrole = copyStringAttribute(element, kAXSubroleAttribute as CFString) ?? ""
        let description = copyStringAttribute(element, kAXDescriptionAttribute as CFString) ?? ""
        let identifier = copyStringAttribute(element, kAXIdentifierAttribute as CFString) ?? ""

        return category(role: role, subrole: subrole, description: description, identifier: identifier)
    }

    /// Pure token → category decision (no AX work; unit-testable).
    static func category(
        role: String,
        subrole: String = "",
        description: String = "",
        identifier: String = ""
    ) -> AXRoleCategory? {
        let blob = [role, subrole, description, identifier]
            .joined(separator: " ")
            .lowercased()

        // Password / secure field — never compose or inject. Highest priority:
        // a secure field must win over any addressBar / textField / terminal token below.
        // Note: kAXSecureTextFieldRole is not exposed in Swift, use the literal role name.
        if role == "AXSecureTextField"
            || blob.contains("secure") || blob.contains("password") {
            return .secure
        }
        if blob.contains("url") || blob.contains("address") {
            return .addressBar
        }
        if role == (kAXComboBoxRole as String) || blob.contains("combobox") {
            return .comboBox
        }
        if blob.contains("terminal") || blob.contains("tty") || blob.contains("console") {
            return .terminal
        }
        if role == (kAXTextAreaRole as String) {
            return .editor
        }
        if role == (kAXTextFieldRole as String) || subrole == (kAXSearchFieldSubrole as String) {
            return .textField
        }
        // Inconclusive — leave nil so resolver does not invent a role layer.
        return nil
    }

    private static func copyStringAttribute(_ element: AXUIElement, _ attr: CFString) -> String? {
        var raw: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attr, &raw)
        guard status == .success, let raw else { return nil }
        if CFGetTypeID(raw) == CFStringGetTypeID() {
            return (raw as! String)
        }
        return nil
    }
}

/// Test / non-AX provider that always returns `nil` role (no AX work).
/// Production wiring defaults to `AXFocusedRoleProvider`; this stays as a test seam.
final class StubAXRoleProvider: AXRoleProviding {
    func focusedRoleCategory() -> AXRoleCategory? { nil }
}

// MARK: - Resolver

/// Caches frontmost bundle id + optional AX role. Invalidate on focus / app switch.
final class AppContextResolver {
    private let frontmostProvider: FrontmostAppProviding
    private let roleProvider: AXRoleProviding

    private var cached: AppContextSnapshot = .empty
    private var generation: UInt64 = 0
    private var isValid = false

    init(
        frontmostProvider: FrontmostAppProviding = WorkspaceFrontmostAppProvider(),
        roleProvider: AXRoleProviding = AXFocusedRoleProvider()
    ) {
        self.frontmostProvider = frontmostProvider
        self.roleProvider = roleProvider
    }

    /// Current snapshot. Refreshes once if the cache was invalidated.
    var current: AppContextSnapshot {
        if !isValid {
            refresh()
        }
        return cached
    }

    /// Force a refresh from providers (bounded AX work if role provider does AX).
    @discardableResult
    func refresh() -> AppContextSnapshot {
        let front = frontmostProvider.frontmostApp()
        let role = roleProvider.focusedRoleCategory()
        generation &+= 1
        cached = AppContextSnapshot(
            bundleId: front.bundleId,
            appName: front.appName,
            role: role,
            generation: generation
        )
        isValid = true
        return cached
    }

    /// Seed cache from a known activation (focus-change notification).
    /// Prefer this over bare `invalidate()` so profile resolve does not depend on a
    /// second frontmost query that can lag or return nil after app switch.
    @discardableResult
    func updateFrontmost(bundleId: String?, appName: String? = nil) -> AppContextSnapshot {
        generation &+= 1
        // Role stays optional; stub provider returns nil without AX work.
        let role = roleProvider.focusedRoleCategory()
        cached = AppContextSnapshot(
            bundleId: bundleId,
            appName: appName,
            role: role,
            generation: generation
        )
        isValid = true
        return cached
    }

    /// Mark cache stale. Next `current` / explicit `refresh` re-queries providers.
    func invalidate() {
        isValid = false
    }

    /// Whether the cache is considered fresh.
    var hasValidCache: Bool { isValid }
}
