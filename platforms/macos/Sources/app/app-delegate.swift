// Dấu macOS — startup/shutdown orchestration + TypingSession wiring (WP-06 / P0-2).
// CRITICAL: EventTap callback must NEVER call TextInjector.inject or usleep.
// Hot path: typingSession.handleKey → queue.sync map → queue.async inject.

import AppKit
import Foundation

/// Application delegate: wires EventTap → profile cache → TypingSession (async inject).
///
/// P0-2 contract: no bare `MacKeyPipeline` / `TextInjector` owned here. All key
/// processing goes through `TypingSession` so delays cannot run on the tap thread.
final class AppDelegate: NSObject, NSApplicationDelegate {
    let state = AppState()

    /// Sole owner of pipeline + injector for the key path (serial queue `dau.typing`).
    private let typingSession = TypingSession()
    private let eventTap = KeyboardEventTap()
    private let profileStore = InjectionProfileStore()
    private lazy var profileResolver = InjectionProfileResolver(store: profileStore)
    private let contextResolver = AppContextResolver()
    private lazy var focusObserver = FocusChangeObserver(contextResolver: contextResolver)
    private let inputSourceObserver = InputSourceObserver()
    private lazy var menuBar = MenuBarController(state: state)
    private lazy var onboarding = OnboardingController(state: state)

    /// Cached resolution mirrored into TypingSession on focus/settings change.
    private var cachedSettings: ResolvedInjectionSettings = ResolvedInjectionSettings(
        typingEnabled: true,
        engineMethod: .telex,
        injectionMethod: .backspaceFast,
        delays: .zero,
        source: .safeDefault
    )

    private var axPollTimer: Timer?

    // MARK: - NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        typingSession.onInjectCompleted = { result in
            if case .failure = result {
                // Metadata only — no text content.
                fputs("[dau] inject failed; compose cleared\n", stderr)
            }
        }

        applyEngineFlags()
        refreshProfileCache()

        eventTap.onTapReset = { [weak self] in
            self?.typingSession.resetCompose()
        }
        // P0-2: only TypingSession.handleKey on the tap callback — never inject here.
        eventTap.keyHandler = { [weak self] key, _, _ in
            guard let self else { return .pass }
            let decision = self.typingSession.handleKey(key)
            return decision.consumeOriginal ? .consume : .pass
        }

        focusObserver.onFocusChange = { [weak self] _, _ in
            self?.typingSession.resetCompose()
            self?.refreshProfileCache()
            self?.syncUI()
        }
        focusObserver.start()

        inputSourceObserver.onBlockedChange = { [weak self] blocked, sourceID in
            guard let self else { return }
            self.typingSession.resetCompose()
            self.state.inputSourceBlocked = blocked
            if blocked {
                self.state.statusDetail = "input source blocked"
            } else if sourceID != nil {
                // Metadata only — source id, not key content.
                self.state.statusDetail = "source ok"
            } else {
                self.state.statusDetail = ""
            }
            // Push blocked state into session so hot path stays a single gate.
            self.refreshProfileCache()
            self.syncUI()
        }
        inputSourceObserver.start()

        wireMenuBar()
        wireOnboarding()
        menuBar.start()

        startAXPolling()
        attemptStartTap(prompt: false)

        // First-run / recovery: show setup until AX trusted AND keyboard listener runs.
        // Trusted-but-tap-failed must not be treated as success (ONBOARD-03).
        if !state.accessibilityTrusted || !state.eventTapRunning {
            onboarding.show()
        }

        fputs("[dau] app launched \(state.versionLabel) (TypingSession hot path)\n", stderr)
    }

    func applicationWillTerminate(_ notification: Notification) {
        axPollTimer?.invalidate()
        eventTap.stop()
        focusObserver.stop()
        inputSourceObserver.stop()
        menuBar.stop()
        onboarding.close()
        typingSession.resetCompose()
    }

    // MARK: - Profile / engine → TypingSession

    private func refreshProfileCache() {
        let snapshot = contextResolver.current
        profileResolver.globalTypingEnabled = state.typingEnabled
        profileResolver.globalEngineMethod = state.engineMethod.asOverride
        cachedSettings = profileResolver.resolve(context: snapshot)

        // Master gates: VI/EN + input-source block + per-app profile.
        let enabled =
            state.typingEnabled
            && !state.inputSourceBlocked
            && cachedSettings.typingEnabled

        let method = cachedSettings.effectiveInjectionMethod
        // Non-zero delays are safe: inject runs async on `dau.typing`, not on EventTap.
        let delays = cachedSettings.delays

        let engine: DauMethod
        switch cachedSettings.engineMethod {
        case .telex: engine = DauMethod_Telex
        case .vni: engine = DauMethod_Vni
        }

        typingSession.applyRuntimeSettings(
            typingEnabled: enabled,
            injectionMethod: method,
            delays: delays,
            engineMethod: engine
        )
    }

    private func applyEngineFlags() {
        // Core flags via session queue wrappers (never touch pipeline off-queue).
        typingSession.setEnabled(true)
        typingSession.setMethod(state.engineMethod.asDauMethod)
        typingSession.setAutoRestore(true)
        // Global default: auto-cap off (terminal north star).
        typingSession.setAutoCapitalize(false)
    }

    // MARK: - Tap / AX

    private func attemptStartTap(prompt: Bool) {
        state.accessibilityTrusted = KeyboardEventTap.isAccessibilityTrusted(prompt: false)
        if prompt {
            _ = KeyboardEventTap.isAccessibilityTrusted(prompt: true)
            state.accessibilityTrusted = KeyboardEventTap.isAccessibilityTrusted(prompt: false)
        }

        if state.accessibilityTrusted {
            let ok = eventTap.start(promptForAccessibility: false)
            state.eventTapRunning = ok
            if !ok {
                state.statusDetail = "event tap create failed"
            } else if case .running(let place) = eventTap.status {
                state.statusDetail = "tap \(place.rawValue)"
            }
        } else {
            eventTap.stop()
            state.eventTapRunning = false
            state.statusDetail = "need Accessibility"
        }
        syncUI()
        onboarding.refreshStatus()
    }

    private func restartTap() {
        typingSession.resetCompose()
        state.accessibilityTrusted = KeyboardEventTap.isAccessibilityTrusted(prompt: false)
        if state.accessibilityTrusted {
            let ok = eventTap.restart(promptForAccessibility: false)
            state.eventTapRunning = ok
        } else {
            eventTap.stop()
            state.eventTapRunning = false
        }
        refreshProfileCache()
        syncUI()
        onboarding.refreshStatus()
    }

    private func startAXPolling() {
        axPollTimer?.invalidate()
        // Poll while untrusted so granting permission in System Settings is noticed.
        let timer = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.pollAccessibility()
        }
        RunLoop.main.add(timer, forMode: .common)
        axPollTimer = timer
    }

    private func pollAccessibility() {
        let trusted = KeyboardEventTap.isAccessibilityTrusted(prompt: false)
        if trusted != state.accessibilityTrusted {
            state.accessibilityTrusted = trusted
            if trusted {
                // Start listener; onboarding only completes when tap is running.
                attemptStartTap(prompt: false)
            } else {
                eventTap.stop()
                state.eventTapRunning = false
                typingSession.resetCompose()
                syncUI()
                onboarding.refreshStatus()
            }
        } else if trusted, !state.eventTapRunning {
            // Permission ok but listener not running — recover without prompt spam.
            attemptStartTap(prompt: false)
        } else if trusted, state.eventTapRunning {
            // Keep ready phase in sync while window still open (auto-close is onboarding-owned).
            onboarding.refreshStatus()
        }
    }

    private func openAccessibilitySettings() {
        // macOS Ventura+ privacy pane deep link.
        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
        ]
        for s in urls {
            if let url = URL(string: s), NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    // MARK: - Menu / onboarding wiring

    private func wireMenuBar() {
        menuBar.onToggleTyping = { [weak self] in
            self?.toggleTyping()
        }
        menuBar.onSelectTelex = { [weak self] in
            self?.setEngineMethod(.telex)
        }
        menuBar.onSelectVNI = { [weak self] in
            self?.setEngineMethod(.vni)
        }
        menuBar.onOpenAccessibilitySettings = { [weak self] in
            self?.openAccessibilitySettings()
        }
        menuBar.onRestartTap = { [weak self] in
            self?.restartTap()
        }
        menuBar.onShowOnboarding = { [weak self] in
            self?.onboarding.show()
        }
        menuBar.onQuit = {
            NSApp.terminate(nil)
        }
    }

    private func wireOnboarding() {
        onboarding.onOpenSystemSettings = { [weak self] in
            self?.openAccessibilitySettings()
        }
        onboarding.onRequestAccessibilityPrompt = { [weak self] in
            self?.attemptStartTap(prompt: true)
        }
        onboarding.onRetryTap = { [weak self] in
            self?.restartTap()
        }
    }

    private func toggleTyping() {
        state.typingEnabled.toggle()
        typingSession.resetCompose()
        refreshProfileCache()
        syncUI()
    }

    private func setEngineMethod(_ method: AppEngineMethod) {
        guard state.engineMethod != method else { return }
        state.engineMethod = method
        typingSession.resetCompose()
        applyEngineFlags()
        refreshProfileCache()
        syncUI()
    }

    private func syncUI() {
        // Ensure main-thread UI updates.
        if Thread.isMainThread {
            menuBar.refresh()
            onboarding.refreshStatus()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.menuBar.refresh()
                self?.onboarding.refreshStatus()
            }
        }
    }
}
