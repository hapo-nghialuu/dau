// Dấu macOS — CGEventTap lifecycle: HID → session fallback, marker filter, fail-open recovery (WP-04 / TG-00).
// Does not parse config, choose injection method, or call AX uncached in the hot path.
// Prefer leaving the tap stopped (OS passes keys) over re-enabling a hung/degraded tap blindly.

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
    /// Tap intentionally left disabled so macOS delivers keys (fail-open).
    case degradedStopped
}

/// Decision returned by the key handler after classification.
enum EventTapDisposition: Equatable, Sendable {
    /// Deliver the original event to the rest of the system.
    case pass
    /// Suppress the original keyDown (compose replacement will be injected separately).
    case consume
}

// MARK: - Recovery policy (pure — unit-testable without CGEvent)

/// Why the OS or watchdog considered the tap unhealthy.
enum EventTapDisableReason: String, Equatable, Sendable {
    case timeout
    case userInput
    case watchdog
}

/// Action chosen by the recovery policy after disable / watchdog tick.
enum EventTapRecoveryAction: Equatable, Sendable {
    case none
    /// Dependencies healthy: try CGEvent.tapEnable once.
    case reenable
    /// Re-enable failed or policy demands a new port: stop + create once.
    case recreate
    /// Health failed or recreate budget exhausted: leave tap down so OS passes keys.
    case stopDegraded
}

/// Pure recovery state machine for system-disable + watchdog (no CGEvent dependency).
/// Manual clock + fake health/enable results cover: re-enable healthy, recreate failure, no storm.
struct EventTapRecoveryState: Equatable, Sendable {
    /// Tap generation (increments on each successful start).
    var generation: UInt64 = 0
    var isDegraded: Bool = false
    /// Successful recreate attempts in the current storm window.
    var recreatesInWindow: Int = 0
    /// Monotonic clock seconds of last recreate (manual clock in tests).
    var lastRecreateAt: TimeInterval = 0
    /// Max recreates allowed within `stormWindowSeconds` before stopDegraded.
    var maxRecreatesPerWindow: Int = 1
    var stormWindowSeconds: TimeInterval = 5.0

    /// OS reported `.tapDisabledByTimeout` / `.tapDisabledByUserInput`.
    /// Never blind re-enable without a health check.
    mutating func onSystemDisabled(
        reason: EventTapDisableReason,
        healthOk: Bool,
        now: TimeInterval
    ) -> EventTapRecoveryAction {
        _ = reason
        isDegraded = true
        guard healthOk else {
            return .stopDegraded
        }
        return recreateOrStop(now: now)
    }

    /// Watchdog observed port disabled (or missing).
    mutating func onWatchdogTick(
        portEnabled: Bool,
        healthOk: Bool,
        reenableSucceeded: Bool,
        now: TimeInterval
    ) -> EventTapRecoveryAction {
        if portEnabled {
            return .none
        }
        isDegraded = true
        guard healthOk else {
            return .stopDegraded
        }
        // Try re-enable first; only recreate when re-enable fails.
        if reenableSucceeded {
            isDegraded = false
            return .reenable
        }
        return recreateOrStop(now: now)
    }

    mutating func noteStarted(now: TimeInterval) {
        generation &+= 1
        isDegraded = false
        _ = now
    }

    mutating func noteStopped() {
        // Keep generation for telemetry; mark not running via status externally.
    }

    /// Call after a recovery recreate path succeeds (`start` already bumped `generation`).
    mutating func noteRecreateAttempt(succeeded: Bool, now: TimeInterval) {
        rollWindowIfNeeded(now: now)
        recreatesInWindow += 1
        lastRecreateAt = now
        if succeeded {
            isDegraded = false
        } else {
            isDegraded = true
        }
    }

    private mutating func recreateOrStop(now: TimeInterval) -> EventTapRecoveryAction {
        rollWindowIfNeeded(now: now)
        if recreatesInWindow >= maxRecreatesPerWindow {
            return .stopDegraded
        }
        return .recreate
    }

    private mutating func rollWindowIfNeeded(now: TimeInterval) {
        if lastRecreateAt > 0, now - lastRecreateAt > stormWindowSeconds {
            recreatesInWindow = 0
        }
    }
}

// MARK: - Seams for tests

/// Clock seam so watchdog / recovery tests can advance time without sleeping.
protocol EventTapClock: AnyObject {
    var now: TimeInterval { get }
}

final class SystemEventTapClock: EventTapClock {
    var now: TimeInterval { Date().timeIntervalSince1970 }
}

/// Manual clock for deterministic recovery tests.
final class ManualEventTapClock: EventTapClock {
    var now: TimeInterval = 0
    func advance(_ delta: TimeInterval) {
        now += delta
    }
}

/// Port control seam. Production wraps CFMachPort; tests use `FakeEventTapPortControl`.
protocol EventTapPortControl: AnyObject {
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool)
    func invalidate()
}

final class FakeEventTapPortControl: EventTapPortControl {
    var isEnabled: Bool = true
    /// When false, `setEnabled(true)` leaves the port disabled (re-enable failure).
    var allowEnable: Bool = true
    private(set) var enableCallCount = 0
    private(set) var invalidateCallCount = 0

    func setEnabled(_ enabled: Bool) {
        enableCallCount += 1
        if enabled {
            isEnabled = allowEnable
        } else {
            isEnabled = false
        }
    }

    func invalidate() {
        invalidateCallCount += 1
        isEnabled = false
    }
}

// MARK: - Tap

/// System-wide keyboard event tap with synthetic-marker filtering and fail-open recovery.
///
/// Callback is intentionally thin: classify → handler. No file I/O, no AX queries, no permission prompts.
final class KeyboardEventTap {
    /// Handler for real (non-synthetic) classified keys.
    /// Return `.consume` to suppress the original event; `.pass` to forward it.
    typealias KeyHandler = (
        _ key: ClassifiedKey,
        _ event: CGEvent,
        _ proxy: CGEventTapProxy
    ) -> EventTapDisposition

    /// Invoked when the tap is re-enabled or recreated after macOS disabled it.
    /// Callers should clear compose / provisional state (plan §2.3). Prefer async-safe work.
    var onTapReset: (() -> Void)?

    /// Optional key handler; when nil, all non-synthetic events pass through.
    var keyHandler: KeyHandler?

    /// Dependency health for recovery (post-access cache, AX trust, etc.). Never prompts.
    /// Default: Accessibility trusted without prompt.
    var healthCheck: () -> Bool = {
        KeyboardEventTap.isAccessibilityTrusted(prompt: false)
    }

    /// Optional metadata telemetry (generation / status / reason). Never key codes or text.
    var onTelemetry: ((String) -> Void)?

    /// Clock seam (manual in tests).
    var clock: EventTapClock = SystemEventTapClock()

    /// Watchdog interval (seconds).
    var watchdogInterval: TimeInterval = 1.0

    private(set) var status: KeyboardEventTapStatus = .stopped
    private(set) var recovery = EventTapRecoveryState()

    /// Current tap generation (0 when never started).
    var generation: UInt64 { recovery.generation }
    var isDegraded: Bool { recovery.isDegraded }

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var watchdogTimer: Timer?
    private var selfPointer: UnsafeMutableRawPointer?
    private var placement: EventTapPlacement?

    /// When set, production CGEvent port is bypassed (unit tests).
    private var fakePort: EventTapPortControl?
    /// Tracks whether the last start used the fake backend.
    private var usingFakeBackend = false

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

    // MARK: - Test backend

    /// Install a fake port so recovery/watchdog can be tested without CGEvent.tapCreate.
    func installFakePortForTesting(_ port: EventTapPortControl) {
        stop()
        fakePort = port
        usingFakeBackend = true
        recovery.noteStarted(now: clock.now)
        status = .running(.session)
        startWatchdog()
        emitTelemetry(event: "fake-start", detail: "gen=\(recovery.generation)")
    }

    // MARK: - Lifecycle

    /// Create and enable the tap. Prefers HID; falls back to session.
    /// Returns `true` when the tap is running.
    @discardableResult
    func start(promptForAccessibility: Bool = false) -> Bool {
        stop()

        // Fake backend: re-bind without CGEvent (tests).
        if let fake = fakePort, usingFakeBackend {
            fake.setEnabled(true)
            if fake.isEnabled {
                recovery.noteStarted(now: clock.now)
                status = .running(.session)
                startWatchdog()
                emitTelemetry(event: "start", detail: "placement=fake gen=\(recovery.generation)")
                return true
            }
            status = .createFailed
            recovery.isDegraded = true
            emitTelemetry(event: "start-failed", detail: "fake")
            return false
        }

        guard Self.isAccessibilityTrusted(prompt: promptForAccessibility) else {
            status = .accessibilityDenied
            fputs("[dau] event-tap: Accessibility not trusted\n", stderr)
            emitTelemetry(event: "start-denied", detail: "ax")
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
            emitTelemetry(event: "start-failed", detail: "create")
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
        recovery.noteStarted(now: clock.now)
        status = .running(place)
        startWatchdog()
        fputs("[dau] event-tap: running placement=\(place.rawValue) gen=\(recovery.generation)\n", stderr)
        emitTelemetry(event: "start", detail: "placement=\(place.rawValue) gen=\(recovery.generation)")
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
        if let fake = fakePort {
            fake.setEnabled(false)
        }
        placement = nil
        selfPointer = nil
        recovery.noteStopped()
        // Preserve degradedStopped if already set by recovery; otherwise stopped.
        if status != .degradedStopped {
            status = .stopped
        }
        emitTelemetry(event: "stop", detail: "gen=\(recovery.generation) degraded=\(recovery.isDegraded)")
    }

    /// Force a clean stopped status (e.g. before sleep).
    func stopClean() {
        recovery.isDegraded = false
        status = .stopped
        stop()
        status = .stopped
    }

    /// Stop + start; notifies `onTapReset` so compose state can be cleared.
    @discardableResult
    func restart(promptForAccessibility: Bool = false) -> Bool {
        // Clear degraded flag path for intentional user/menu restart.
        if status == .degradedStopped {
            status = .stopped
        }
        stop()
        status = .stopped
        onTapReset?()
        return start(promptForAccessibility: promptForAccessibility)
    }

    /// True when status is a live running placement.
    var isRunning: Bool {
        if case .running = status { return true }
        return false
    }

    // MARK: - Callback path

    fileprivate func handle(
        proxy: CGEventTapProxy,
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        // OS disabled the tap. Do **not** blind re-enable (TG-00).
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            let reason: EventTapDisableReason =
                type == .tapDisabledByTimeout ? .timeout : .userInput
            handleSystemDisabled(reason: reason)
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

    /// Recovery entry for OS disable notifications (also callable from tests).
    func handleSystemDisabled(reason: EventTapDisableReason) {
        let healthOk = healthCheck()
        let action = recovery.onSystemDisabled(reason: reason, healthOk: healthOk, now: clock.now)
        emitTelemetry(
            event: "system-disabled",
            detail: "reason=\(reason.rawValue) health=\(healthOk) action=\(String(describing: action)) gen=\(recovery.generation)"
        )
        applyRecoveryAction(action, source: "system-disabled")
    }

    // MARK: - Watchdog

    private func startWatchdog() {
        stopWatchdog()
        // `.common` so the timer fires while tracking runs (menus, modal tracking).
        let interval = watchdogInterval
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.watchdogTick()
        }
        RunLoop.main.add(timer, forMode: .common)
        watchdogTimer = timer
    }

    private func stopWatchdog() {
        watchdogTimer?.invalidate()
        watchdogTimer = nil
    }

    /// Watchdog tick — public for manual-clock unit tests.
    func watchdogTick() {
        let enabled = currentPortIsEnabled()
        if enabled {
            return
        }
        // Probe re-enable only after health check; never storm recreate.
        let healthOk = healthCheck()
        var reenableSucceeded = false
        if healthOk {
            reenableSucceeded = tryReenablePort()
        }
        let action = recovery.onWatchdogTick(
            portEnabled: false,
            healthOk: healthOk,
            reenableSucceeded: reenableSucceeded,
            now: clock.now
        )
        // If re-enable already succeeded inside the probe, policy returns .reenable — notify reset.
        if reenableSucceeded, action == .reenable {
            recovery.isDegraded = false
            onTapReset?()
            emitTelemetry(event: "watchdog-reenable", detail: "gen=\(recovery.generation)")
            fputs("[dau] event-tap: watchdog re-enabled gen=\(recovery.generation)\n", stderr)
            return
        }
        emitTelemetry(
            event: "watchdog",
            detail: "health=\(healthOk) reenable=\(reenableSucceeded) action=\(String(describing: action)) gen=\(recovery.generation)"
        )
        applyRecoveryAction(action, source: "watchdog")
    }

    private func applyRecoveryAction(_ action: EventTapRecoveryAction, source: String) {
        switch action {
        case .none:
            return
        case .reenable:
            // Already applied in watchdog path when probe succeeded.
            return
        case .recreate:
            // Clear compose via callback (callers should prefer async reset); do not block here.
            onTapReset?()
            let ok = recreateOnce()
            recovery.noteRecreateAttempt(succeeded: ok, now: clock.now)
            if ok {
                emitTelemetry(event: "recreate-ok", detail: "source=\(source) gen=\(recovery.generation)")
                fputs("[dau] event-tap: recreated source=\(source) gen=\(recovery.generation)\n", stderr)
            } else {
                leaveDegradedStopped(source: source)
            }
        case .stopDegraded:
            leaveDegradedStopped(source: source)
        }
    }

    private func recreateOnce() -> Bool {
        // Tear down without clearing degraded flag prematurely.
        stopWatchdog()
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            runLoopSource = nil
        }
        if let port = eventTap {
            CGEvent.tapEnable(tap: port, enable: false)
            CFMachPortInvalidate(port)
            eventTap = nil
        }
        placement = nil
        selfPointer = nil

        if usingFakeBackend, let fake = fakePort {
            fake.setEnabled(true)
            if fake.isEnabled {
                recovery.noteStarted(now: clock.now)
                status = .running(.session)
                startWatchdog()
                return true
            }
            status = .createFailed
            return false
        }

        // Production recreate: no accessibility prompt from recovery.
        return start(promptForAccessibility: false)
    }

    private func leaveDegradedStopped(source: String) {
        onTapReset?()
        recovery.isDegraded = true
        stopWatchdog()
        if let sourceRef = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), sourceRef, .commonModes)
            runLoopSource = nil
        }
        if let port = eventTap {
            CGEvent.tapEnable(tap: port, enable: false)
            CFMachPortInvalidate(port)
            eventTap = nil
        }
        if let fake = fakePort {
            fake.setEnabled(false)
        }
        placement = nil
        selfPointer = nil
        status = .degradedStopped
        emitTelemetry(event: "degraded-stopped", detail: "source=\(source) gen=\(recovery.generation)")
        fputs(
            "[dau] event-tap: degraded stopped (fail-open) source=\(source) gen=\(recovery.generation)\n",
            stderr
        )
    }

    private func currentPortIsEnabled() -> Bool {
        if let fake = fakePort, usingFakeBackend {
            return fake.isEnabled
        }
        guard let port = eventTap else { return false }
        return CGEvent.tapIsEnabled(tap: port)
    }

    @discardableResult
    private func tryReenablePort() -> Bool {
        if let fake = fakePort, usingFakeBackend {
            fake.setEnabled(true)
            return fake.isEnabled
        }
        guard let port = eventTap else { return false }
        CGEvent.tapEnable(tap: port, enable: true)
        return CGEvent.tapIsEnabled(tap: port)
    }

    private func emitTelemetry(event: String, detail: String) {
        // Metadata only: event name, generation, placement, degraded flag. No key codes / text.
        let line =
            "tap event=\(event) status=\(statusLabel) gen=\(recovery.generation) degraded=\(recovery.isDegraded) \(detail)"
        onTelemetry?(line)
    }

    private var statusLabel: String {
        switch status {
        case .stopped: return "stopped"
        case .running(let p): return "running(\(p.rawValue))"
        case .accessibilityDenied: return "accessibilityDenied"
        case .createFailed: return "createFailed"
        case .degradedStopped: return "degradedStopped"
        }
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
