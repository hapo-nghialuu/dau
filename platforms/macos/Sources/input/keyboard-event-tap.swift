// Dấu macOS — CGEventTap lifecycle: HID → session fallback, marker filter, watchdog (WP-04).
// Does not parse config, choose injection method, or call AX uncached in the hot path.

import ApplicationServices
import CoreGraphics
import Foundation

// MARK: - Status

enum EventTapPlacement: String, Equatable, Sendable {
    case hid
    case session
}

enum KeyboardEventTapStatus: Equatable, Sendable {
    case stopped
    case running(EventTapPlacement)
    case accessibilityDenied
    case createFailed
}

/// Decision returned by the key handler after classification.
enum EventTapDisposition: Equatable, Sendable {
    /// Deliver the original event to the rest of the system.
    case pass
    /// Suppress the original keyDown (compose replacement will be injected separately).
    case consume
}

// MARK: - Tap

/// System-wide keyboard event tap with synthetic-marker filtering and a re-enable watchdog.
///
/// Callback is intentionally thin: classify → handler. No file I/O, no AX queries.
final class KeyboardEventTap {
    /// Handler for real (non-synthetic) classified keys.
    /// Return `.consume` to suppress the original event; `.pass` to forward it.
    typealias KeyHandler = (
        _ key: ClassifiedKey,
        _ event: CGEvent,
        _ proxy: CGEventTapProxy
    ) -> EventTapDisposition

    /// Invoked when the tap is re-enabled or recreated after macOS disabled it.
    /// Callers should clear compose / provisional state (plan §2.3).
    var onTapReset: (() -> Void)?

    /// Optional key handler; when nil, all non-synthetic events pass through.
    var keyHandler: KeyHandler?

    private(set) var status: KeyboardEventTapStatus = .stopped

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var watchdogTimer: Timer?
    private var selfPointer: UnsafeMutableRawPointer?
    private var placement: EventTapPlacement?

    /// Interest mask: keyDown + flagsChanged + OS disable notifications.
    private static var eventsOfInterest: CGEventMask {
        let keyDown = CGEventMask(1) << CGEventType.keyDown.rawValue
        let flagsChanged = CGEventMask(1) << CGEventType.flagsChanged.rawValue
        let disabledTimeout = CGEventMask(1) << CGEventType.tapDisabledByTimeout.rawValue
        let disabledUser = CGEventMask(1) << CGEventType.tapDisabledByUserInput.rawValue
        return keyDown | flagsChanged | disabledTimeout | disabledUser
    }

    deinit {
        stop()
    }

    // MARK: - Accessibility

    /// TCC Accessibility trust check (not an entitlement).
    static func isAccessibilityTrusted(prompt: Bool = false) -> Bool {
        if prompt {
            let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            let options = [key: true] as CFDictionary
            return AXIsProcessTrustedWithOptions(options)
        }
        return AXIsProcessTrusted()
    }

    // MARK: - Lifecycle

    /// Create and enable the tap. Prefers HID; falls back to session.
    /// Returns `true` when the tap is running.
    @discardableResult
    func start(promptForAccessibility: Bool = false) -> Bool {
        stop()

        guard Self.isAccessibilityTrusted(prompt: promptForAccessibility) else {
            status = .accessibilityDenied
            fputs("[dau] event-tap: Accessibility not trusted\n", stderr)
            return false
        }

        let pointer = Unmanaged.passUnretained(self).toOpaque()
        selfPointer = pointer

        let locations: [(CGEventTapLocation, EventTapPlacement)] = [
            (.cghidEventTap, .hid),
            (.cgSessionEventTap, .session),
        ]

        var created: CFMachPort?
        var used: EventTapPlacement?

        for (location, place) in locations {
            if let port = CGEvent.tapCreate(
                tap: location,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: Self.eventsOfInterest,
                callback: keyboardEventTapCallback,
                userInfo: pointer
            ) {
                created = port
                used = place
                break
            }
        }

        guard let port = created, let place = used else {
            status = .createFailed
            selfPointer = nil
            fputs("[dau] event-tap: create failed (HID and session)\n", stderr)
            return false
        }

        eventTap = port
        placement = place
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        runLoopSource = source
        if let source {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }
        CGEvent.tapEnable(tap: port, enable: true)
        status = .running(place)
        startWatchdog()
        fputs("[dau] event-tap: running placement=\(place.rawValue)\n", stderr)
        return true
    }

    /// Tear down tap, run-loop source, and watchdog.
    func stop() {
        stopWatchdog()
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            runLoopSource = nil
        }
        if let port = eventTap {
            CGEvent.tapEnable(tap: port, enable: false)
            // CFMachPortInvalidate is the documented teardown for event taps.
            CFMachPortInvalidate(port)
            eventTap = nil
        }
        placement = nil
        selfPointer = nil
        status = .stopped
    }

    /// Stop + start; notifies `onTapReset` so compose state can be cleared.
    @discardableResult
    func restart(promptForAccessibility: Bool = false) -> Bool {
        stop()
        onTapReset?()
        return start(promptForAccessibility: promptForAccessibility)
    }

    // MARK: - Callback path

    fileprivate func handle(
        proxy: CGEventTapProxy,
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        // OS disabled the tap (callback took too long, or user input). Re-enable.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let port = eventTap {
                CGEvent.tapEnable(tap: port, enable: true)
            }
            onTapReset?()
            return Unmanaged.passUnretained(event)
        }

        // Skip synthetic posts from TextInjector (anti-recursion).
        if SyntheticEventMarker.matches(event) {
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown || type == .flagsChanged else {
            return Unmanaged.passUnretained(event)
        }

        let classified = KeyClassifier.classify(event: event, type: type)

        // No handler → observe-only / pass-through (scaffold safe).
        guard let keyHandler else {
            return Unmanaged.passUnretained(event)
        }

        let disposition = keyHandler(classified, event, proxy)
        switch disposition {
        case .pass:
            return Unmanaged.passUnretained(event)
        case .consume:
            return nil
        }
    }

    // MARK: - Watchdog

    private func startWatchdog() {
        stopWatchdog()
        // `.common` so the timer fires while tracking runs (menus, modal tracking).
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.watchdogTick()
        }
        RunLoop.main.add(timer, forMode: .common)
        watchdogTimer = timer
    }

    private func stopWatchdog() {
        watchdogTimer?.invalidate()
        watchdogTimer = nil
    }

    private func watchdogTick() {
        guard let port = eventTap else { return }
        if CGEvent.tapIsEnabled(tap: port) {
            return
        }
        // Sketch: re-enable first; if still dead, full restart.
        CGEvent.tapEnable(tap: port, enable: true)
        if CGEvent.tapIsEnabled(tap: port) {
            fputs("[dau] event-tap: watchdog re-enabled\n", stderr)
            onTapReset?()
            return
        }
        fputs("[dau] event-tap: watchdog recreate\n", stderr)
        _ = restart(promptForAccessibility: false)
    }
}

// MARK: - C callback

/// Free function required by `CGEvent.tapCreate` (C calling convention).
private func keyboardEventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent?,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let event else { return nil }
    guard let refcon else {
        return Unmanaged.passUnretained(event)
    }
    let tap = Unmanaged<KeyboardEventTap>.fromOpaque(refcon).takeUnretainedValue()
    return tap.handle(proxy: proxy, type: type, event: event)
}
