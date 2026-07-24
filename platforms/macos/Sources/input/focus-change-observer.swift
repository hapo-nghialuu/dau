// Dấu macOS — app activation focus invalidation (WP-05 / P2.3).
// On focus change: invalidate AppContextResolver and notify callers (compose clear is WP-06).

import AppKit
import Foundation

/// Observes frontmost-app changes and drives context invalidation + lightweight hooks.
///
/// Does not call `dau-core` or perform AX work. Callback must stay cheap.
final class FocusChangeObserver {
    /// Fired on the main queue after invalidation when the frontmost app changes.
    /// Arguments: previous bundle id (if known), new bundle id (if known).
    var onFocusChange: ((_ previousBundleId: String?, _ newBundleId: String?) -> Void)?

    private let contextResolver: AppContextResolver
    private var observer: NSObjectProtocol?
    private var lastBundleId: String?
    private(set) var isRunning = false

    init(contextResolver: AppContextResolver) {
        self.contextResolver = contextResolver
    }

    deinit {
        stop()
    }

    /// Start listening for `NSWorkspace.didActivateApplicationNotification`.
    func start() {
        guard !isRunning else { return }
        lastBundleId = contextResolver.current.bundleId
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleActivation(notification)
        }
        isRunning = true
    }

    func stop() {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            self.observer = nil
        }
        isRunning = false
    }

    /// Test / manual entry: simulate an app activation by bundle id.
    /// Caller should update the frontmost provider before calling when role/bundle must refresh.
    func simulateActivation(bundleId: String?) {
        // Prefer last notified id; fall back to cache when `start()` was not used (unit tests).
        let previous = lastBundleId ?? contextResolver.current.bundleId
        contextResolver.invalidate()
        lastBundleId = bundleId
        onFocusChange?(previous, bundleId)
    }

    private func handleActivation(_ notification: Notification) {
        let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        let newId = app?.bundleIdentifier
        let previous = lastBundleId

        // Always invalidate so the next hot-path read re-queries frontmost/role.
        contextResolver.invalidate()
        lastBundleId = newId
        onFocusChange?(previous, newId)
    }
}
