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
    /// Seeds the context cache so profile resolve sees `bundleId` without a provider round-trip.
    func simulateActivation(bundleId: String?) {
        // Prefer last notified id; fall back to cache when `start()` was not used (unit tests).
        let previous = lastBundleId ?? contextResolver.current.bundleId
        // Seed from the simulated id (authoritative for this event). Not keyboard hot path.
        contextResolver.updateFrontmost(bundleId: bundleId, appName: nil)
        lastBundleId = bundleId
        onFocusChange?(previous, bundleId)
    }

    private func handleActivation(_ notification: Notification) {
        let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        let newId = app?.bundleIdentifier
        let newName = app?.localizedName
        let previous = lastBundleId

        // Seed cache from the activation notification (authoritative for this event).
        // Do not rely on a second frontmost query that can lag/nil after app switch.
        // Not keyboard hot path — resolve here, hot path only reads the cache.
        contextResolver.updateFrontmost(bundleId: newId, appName: newName)
        lastBundleId = newId
        onFocusChange?(previous, newId)
    }
}
