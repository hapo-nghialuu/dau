// Dấu macOS — app activation + AX focused-element focus invalidation (WP-05 / P2.3).
// On focus change: invalidate AppContextResolver and notify callers (compose clear is WP-06).

import AppKit
import ApplicationServices
import Foundation

/// Observes frontmost-app changes and drives context invalidation + lightweight hooks.
///
/// Primary signal: `NSWorkspace.didActivateApplicationNotification`. Fail-safe: an
/// AX `kAXFocusedUIElementChangedNotification` observer, re-targeted at the frontmost
/// app on every activation, catches same-app focus moves (address bar ↔ web input ↔
/// password field) the workspace notification misses. The AX callback only invalidates
/// the resolver cache and fires the hook — role re-classification happens lazily on the
/// next `current` read, never on the key event-tap hot path.
final class FocusChangeObserver {
    /// Fired on the main queue after invalidation when the frontmost app changes.
    /// Arguments: previous bundle id (if known), new bundle id (if known).
    var onFocusChange: ((_ previousBundleId: String?, _ newBundleId: String?) -> Void)?

    private let contextResolver: AppContextResolver
    private var observer: NSObjectProtocol?
    private var lastBundleId: String?
    private(set) var isRunning = false

    // AX focused-element fail-safe observer (re-targeted on the frontmost app).
    private var axObserver: AXObserver?
    private var axApp: AXUIElement?
    private var axSource: CFRunLoopSource?

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
        registerAXObserver(for: NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0)
        isRunning = true
    }

    func stop() {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            self.observer = nil
        }
        unregisterAXObserver()
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

        // Re-target the AX fail-safe observer at the newly activated app.
        if let pid = app?.processIdentifier {
            registerAXObserver(for: pid)
        }
    }

    /// AX focused element changed inside the frontmost app (same-app focus move).
    /// Stale the cache so the next resolve re-classifies the AX role, then fire the
    /// hook with the same bundle id (prev == next). Main queue; not the key hot path.
    private func handleAXFocusChange() {
        contextResolver.invalidate()
        onFocusChange?(lastBundleId, lastBundleId)
    }

    /// Test / manual entry: simulate an AX focused-element change in the current app.
    func simulateAXFocusChange() {
        handleAXFocusChange()
    }

    /// Register the AX focused-element observer for `pid`. No-op without
    /// Accessibility trust or a valid pid. Silently re-targets on app switch.
    private func registerAXObserver(for pid: pid_t) {
        guard pid > 0, AXIsProcessTrusted() else { return }
        unregisterAXObserver()

        var ref: AXObserver?
        let createStatus = AXObserverCreate(pid, { _, _, _, refcon in
            guard let refcon else { return }
            let this = Unmanaged<FocusChangeObserver>.fromOpaque(refcon).takeUnretainedValue()
            DispatchQueue.main.async {
                this.handleAXFocusChange()
            }
        }, &ref)
        guard createStatus == .success, let ref else { return }

        let element = AXUIElementCreateApplication(pid)
        let addStatus = AXObserverAddNotification(
            ref,
            element,
            kAXFocusedUIElementChangedNotification as CFString,
            Unmanaged.passUnretained(self).toOpaque()
        )
        guard addStatus == .success else {
            axObserver = nil
            axApp = nil
            return
        }

        axObserver = ref
        axApp = element
        // AXObserverGetRunLoopSource is non-optional per its API contract.
        let source = AXObserverGetRunLoopSource(ref)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        axSource = source
    }

    private func unregisterAXObserver() {
        if let axSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), axSource, .commonModes)
            self.axSource = nil
        }
        if let axObserver, let axApp {
            AXObserverRemoveNotification(axObserver, axApp, kAXFocusedUIElementChangedNotification as CFString)
        }
        axObserver = nil
        axApp = nil
    }
}
