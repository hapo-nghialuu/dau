// Dấu macOS — startup/shutdown orchestration + TypingSession wiring (WP-06 / P0-2 / TG-00).
// CRITICAL: EventTap callback must NEVER call permission prompts, unbounded AX, or hang on inject.
// Hot path: early EN/boundary fail-open → TypingSession.handleKey (bounded budget) → optional inject.

import AppKit
import Foundation

/// Application delegate: wires EventTap → profile cache → TypingSession (bounded callback).
///
/// TG-00 contract:
/// - EN / blocked / off path never waits on `dau.typing` or SyntheticPostAccess.
/// - Sleep/wake stops and recreates the tap; no permission prompt on wake.
/// - AX poll stops when trusted + tap healthy.
/// - `state.eventTapRunning` always mirrors real tap status.
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
    private lazy var settings = SettingsController(
        state: state,
        profileStore: profileStore,
        profileResolver: profileResolver,
        contextResolver: contextResolver
    )
    /// Global VI/EN hotkey (Carbon). Separate from EventTap compose path.
    private let toggleHotkeyRegistrar = ToggleHotkeyRegistrar()

    /// Cached resolution mirrored into TypingSession on focus/settings change.
    private var cachedSettings: ResolvedInjectionSettings = ResolvedInjectionSettings(
        typingEnabled: true,
        engineMethod: .telex,
        injectionMethod: .backspaceFast,
        delays: .zero,
        source: .safeDefault
    )

    private var axPollTimer: Timer?
    /// Workspace sleep/wake / session observers.
    private var workspaceObservers: [NSObjectProtocol] = []
    private var sleepWakeEngine = SleepWakeLifecycleEngine()
    /// Held for the app lifetime: App Nap / timer coalescing on an idle accessory app
    /// delays EventTap servicing + `dau.typing` scheduling past the 12ms budget,
    /// so the first burst after minutes of idle passes through raw.
    private var keyboardLatencyActivity: NSObjectProtocol?
    /// Update checker (UPDATE-01). Background queue only — never the keyboard hot path.
    private let updateChecker = UpdateChecker()

    // MARK: - NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Opt out of App Nap for the whole process (allows idle system sleep).
        // Launch-time only — never touches the keyboard hot path.
        keyboardLatencyActivity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep, .latencyCritical],
            reason: "Dấu keyboard event tap latency"
        )

        // Capability snapshot for inject path — no prompt on launch.
        refreshPostEventAccess(prompt: false)
        warmUpEventPostChannel()

        typingSession.onInjectCompleted = { result in
            if case .failure = result {
                // Metadata only — no text content.
                fputs("[dau] inject failed; compose cleared\n", stderr)
            }
        }
        typingSession.onCallbackTelemetry = { line in
            // Metadata only (phase/gen/bucket). Never key codes or text.
            fputs("[dau] \(line)\n", stderr)
        }

        applyEngineFlags()
        refreshProfileCache()

        // Tap reset must not block; clear compose on session queue asynchronously.
        eventTap.onTapReset = { [weak self] in
            self?.typingSession.resetComposeAsync()
            DispatchQueue.main.async {
                self?.syncEventTapStateToUI()
            }
        }
        eventTap.healthCheck = { [weak self] in
            guard let self else { return false }
            // Cached capability + AX trust only — never prompt from recovery.
            let ax = KeyboardEventTap.isAccessibilityTrusted(prompt: false)
            let post = SyntheticPostAccess.cachedGranted
            return ax && post
        }
        eventTap.onTelemetry = { line in
            fputs("[dau] \(line)\n", stderr)
        }

        // P0-2 / TG-00: early fail-open lives in TypingSession; AppDelegate never injects here.
        // Global VI/EN toggle is Carbon RegisterEventHotKey (ToggleHotkeyRegistrar), not EventTap.
        eventTap.keyHandler = { [weak self] key, _, _ in
            guard let self else { return .pass }
            let decision = self.typingSession.handleKey(key)
            return decision.consumeOriginal ? .consume : .pass
        }

        toggleHotkeyRegistrar.onHotkey = { [weak self] in
            self?.toggleTyping()
        }
        reregisterToggleHotkey()

        focusObserver.onFocusChange = { [weak self] _, _ in
            self?.typingSession.resetCompose()
            // Refresh post-access cache off the keyboard hot path when focus changes.
            self?.refreshPostEventAccess(prompt: false)
            self?.refreshProfileCache()
            // App switch is exactly when the first composed word lands on a cold
            // post channel + ramping CPU — pre-pay that before the first keystroke.
            self?.warmUpEventPostChannel()
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
        wireSettings()
        menuBar.start()

        registerSleepWakeObservers()
        startAXPolling()
        attemptStartTap(prompt: false)

        // First-run / recovery: show setup until AX trusted AND keyboard listener runs.
        // Trusted-but-tap-failed must not be treated as success (ONBOARD-03).
        if !state.accessibilityTrusted || !state.eventTapRunning || !state.postEventAccessGranted {
            onboarding.show()
        }

        // SET-06: mirror real login-item status; keep UI in sync with SMAppService.
        refreshLaunchAtLoginState()
        // UPDATE-01: throttled background update check (24h). Never blocks launch.
        checkForUpdates()

        fputs("[dau] app launched \(state.versionLabel) (TypingSession hot path, TG-00 fail-open)\n", stderr)
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let keyboardLatencyActivity {
            ProcessInfo.processInfo.endActivity(keyboardLatencyActivity)
            self.keyboardLatencyActivity = nil
        }
        axPollTimer?.invalidate()
        axPollTimer = nil
        unregisterSleepWakeObservers()
        toggleHotkeyRegistrar.unregister()
        eventTap.stopClean()
        focusObserver.stop()
        inputSourceObserver.stop()
        menuBar.stop()
        onboarding.close()
        settings.close()
        typingSession.resetCompose()
        syncEventTapStateToUI()
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
            engineMethod: engine,
            frontmostBundleId: snapshot.bundleId
        )
    }

    private func applyEngineFlags() {
        // Core flags via session queue wrappers (never touch pipeline off-queue).
        // Master engine stays enabled; VI/EN is `typingEnabled` at the session gate.
        typingSession.setEnabled(true)
        typingSession.setMethod(state.engineMethod.asDauMethod)
        typingSession.setAutoRestore(state.autoRestore)
        typingSession.setAutoCapitalize(state.autoCapitalize)
    }

    // MARK: - Tap / AX

    private func attemptStartTap(prompt: Bool) {
        state.accessibilityTrusted = KeyboardEventTap.isAccessibilityTrusted(prompt: false)
        if prompt {
            _ = KeyboardEventTap.isAccessibilityTrusted(prompt: true)
            state.accessibilityTrusted = KeyboardEventTap.isAccessibilityTrusted(prompt: false)
            // Post-event access prompt only from setup/recovery UI — never keyboard callback.
            refreshPostEventAccess(prompt: true)
        } else {
            refreshPostEventAccess(prompt: false)
        }

        if state.accessibilityTrusted {
            let ok = eventTap.start(promptForAccessibility: false)
            syncEventTapStateToUI(fallbackDetail: ok ? nil : "event tap create failed")
            if !ok {
                // Real status already mirrored; keep polling so recovery can retry.
                startAXPolling()
            } else {
                // Healthy start: AX poll can stop (restarted if trust/tap drops).
                stopAXPollingIfHealthy()
                // AX may have been late at launch — retry toggle hotkey only if not live.
                ensureToggleHotkeyRegistered()
            }
        } else {
            eventTap.stopClean()
            syncEventTapStateToUI(fallbackDetail: "need Accessibility")
            startAXPolling()
        }
        syncUI()
        onboarding.refreshStatus()
    }

    private func restartTap() {
        typingSession.resetCompose()
        state.accessibilityTrusted = KeyboardEventTap.isAccessibilityTrusted(prompt: false)
        refreshPostEventAccess(prompt: false)
        if state.accessibilityTrusted {
            let ok = eventTap.restart(promptForAccessibility: false)
            syncEventTapStateToUI(fallbackDetail: ok ? nil : "event tap restart failed")
            if ok {
                stopAXPollingIfHealthy()
            } else {
                startAXPolling()
            }
        } else {
            eventTap.stopClean()
            syncEventTapStateToUI(fallbackDetail: "need Accessibility")
            startAXPolling()
        }
        // Recovery path: reinstall toggle hotkey only when previous install failed.
        ensureToggleHotkeyRegistered()
        refreshProfileCache()
        syncUI()
        onboarding.refreshStatus()
    }

    /// Mirror real tap status into AppState (including degraded / failed restart).
    private func syncEventTapStateToUI(fallbackDetail: String? = nil) {
        let running = eventTap.isRunning
        let degraded = eventTap.isDegraded || {
            if case .degradedStopped = eventTap.status { return true }
            return false
        }()
        var detail = fallbackDetail
        if state.accessibilityTrusted && running && !state.postEventAccessGranted {
            detail = "need post-event access"
        }
        if detail == nil {
            switch eventTap.status {
            case .running(let place):
                detail = "tap \(place.rawValue) gen=\(eventTap.generation)"
            case .degradedStopped:
                detail = "tap degraded (fail-open)"
            case .createFailed:
                detail = "event tap create failed"
            case .accessibilityDenied:
                detail = "need Accessibility"
            case .stopped:
                detail = state.accessibilityTrusted ? "tap stopped" : "need Accessibility"
            }
        }
        state.applyEventTapMirror(
            running: running,
            degraded: degraded,
            generation: eventTap.generation,
            detail: detail
        )
    }

    private func startAXPolling() {
        guard axPollTimer == nil else { return }
        // Bounded cadence while untrusted / unhealthy only.
        let timer = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.pollAccessibility()
        }
        RunLoop.main.add(timer, forMode: .common)
        axPollTimer = timer
    }

    private func stopAXPolling() {
        axPollTimer?.invalidate()
        axPollTimer = nil
    }

    private func stopAXPollingIfHealthy() {
        if state.accessibilityTrusted && state.eventTapRunning &&
            state.postEventAccessGranted && !state.eventTapDegraded {
            stopAXPolling()
        }
    }

    private func pollAccessibility() {
        let trusted = KeyboardEventTap.isAccessibilityTrusted(prompt: false)
        refreshPostEventAccess(prompt: false)
        let decision = AccessibilityPollEngine.evaluate(
            trusted: trusted,
            wasTrusted: state.accessibilityTrusted,
            tapRunning: state.eventTapRunning,
            tapDegraded: state.eventTapDegraded
        )

        if trusted != state.accessibilityTrusted {
            state.accessibilityTrusted = trusted
        }

        if decision.stopTap {
            eventTap.stopClean()
            typingSession.resetComposeAsync()
            syncEventTapStateToUI()
        }
        if decision.attemptStartTap {
            attemptStartTap(prompt: false)
        }
        if decision.refreshUI {
            syncUI()
            onboarding.refreshStatus()
        }
        if decision.stopPolling && state.postEventAccessGranted {
            stopAXPolling()
            return
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

    // MARK: - Sleep / wake / session

    private func registerSleepWakeObservers() {
        let nc = NSWorkspace.shared.notificationCenter
        let pairs: [(NSNotification.Name, SleepWakePhase)] = [
            (NSWorkspace.willSleepNotification, .willSleep),
            (NSWorkspace.didWakeNotification, .didWake),
            (NSWorkspace.sessionDidResignActiveNotification, .sessionResign),
            (NSWorkspace.sessionDidBecomeActiveNotification, .sessionActive),
        ]
        for (name, phase) in pairs {
            let token = nc.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.handleSleepWake(phase)
            }
            workspaceObservers.append(token)
        }
    }

    private func unregisterSleepWakeObservers() {
        let nc = NSWorkspace.shared.notificationCenter
        for token in workspaceObservers {
            nc.removeObserver(token)
        }
        workspaceObservers.removeAll()
    }

    /// Workspace sleep/wake/session edge (also usable from tests via same engine).
    func handleSleepWake(_ phase: SleepWakePhase) {
        // Trust re-check without prompt on every edge.
        let trusted = KeyboardEventTap.isAccessibilityTrusted(prompt: false)
        state.accessibilityTrusted = trusted
        refreshPostEventAccess(prompt: false)

        let decision = sleepWakeEngine.handle(phase, accessibilityTrusted: trusted)
        state.lastLifecycleTransition = decision.transitionLabel
        // Metadata only: phase + bundle id. Never key codes / text / clipboard.
        let bundle = Bundle.main.bundleIdentifier ?? "unknown"
        fputs(
            "[dau] lifecycle phase=\(decision.transitionLabel) trusted=\(trusted) " +
                "recreate=\(decision.recreateOnce) prompt=\(decision.promptPermission) bundle=\(bundle)\n",
            stderr
        )

        if decision.stopAndReset {
            typingSession.resetComposeAsync()
            eventTap.stopClean()
            syncEventTapStateToUI(fallbackDetail: "tap stopped (\(decision.transitionLabel))")
            // Resume AX polling after sleep so wake recovery can notice trust changes.
            startAXPolling()
            syncUI()
            return
        }

        // Wake / session-active: never prompt for permission automatically.
        assert(!decision.promptPermission, "wake path must not prompt")
        if decision.recreateOnce {
            if trusted {
                let ok = eventTap.start(promptForAccessibility: false)
                syncEventTapStateToUI(
                    fallbackDetail: ok ? nil : "event tap recreate failed after wake"
                )
                if ok {
                    stopAXPollingIfHealthy()
                } else {
                    startAXPolling()
                }
            } else {
                eventTap.stopClean()
                syncEventTapStateToUI(fallbackDetail: "need Accessibility")
                startAXPolling()
            }
            // Wake path never tore down hotkey tap explicitly, but launch may have
            // left it unregistered when AX was late — retry only if still missing.
            ensureToggleHotkeyRegistered()
            typingSession.resetComposeAsync()
            refreshProfileCache()
            // Post channel can be cold again after sleep — re-pay setup off the hot path.
            warmUpEventPostChannel()
            syncUI()
            onboarding.refreshStatus()
        }
    }

    /// Refresh and mirror post-event capability outside the keyboard callback.
    private func refreshPostEventAccess(prompt: Bool) {
        SyntheticPostAccess.refreshFromSystem(prompt: prompt)
        state.applyPostEventAccessMirror(granted: SyntheticPostAccess.cachedGranted)
    }

    /// Warm the synthetic post path off the hot path (launch / wake / focus change).
    /// Cold costs measured >12ms callback budget on the first composed word:
    /// first `CGEventPost` of the process (~10-14ms WindowServer handshake) and
    /// first keyboard `CGEvent` creation (keyboard-layout fetch). Pay both here:
    /// build a keyboard event without posting it, then post a marker-tagged null
    /// event (apps ignore null events).
    private func warmUpEventPostChannel() {
        guard SyntheticPostAccess.cachedGranted else { return }
        DispatchQueue.global(qos: .utility).async {
            guard let source = CGEventSource(stateID: .privateState)
                ?? CGEventSource(stateID: .combinedSessionState)
            else { return }
            // Keyboard event creation only — never posted, no stray key reaches apps.
            _ = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
            guard let event = CGEvent(source: source) else { return }
            SyntheticEventMarker.apply(to: event)
            event.post(tap: .cgSessionEventTap)
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
        menuBar.onShowSettings = { [weak self] in
            self?.settings.show(page: .general)
        }
        menuBar.onShowAbout = { [weak self] in
            self?.settings.show(page: .about)
        }
        menuBar.onShowOnboarding = { [weak self] in
            self?.onboarding.show()
        }
        menuBar.onQuit = {
            NSApp.terminate(nil)
        }
        menuBar.onCheckForUpdates = { [weak self] in
            self?.checkForUpdatesNow()
        }
        menuBar.onOpenLatestRelease = { [weak self] in
            self?.openLatestReleasePage()
        }
        menuBar.onOpenUpdateGuide = { [weak self] in
            self?.openHomebrewUpdateGuide()
        }
    }

    private func wireOnboarding() {
        onboarding.onOpenSystemSettings = { [weak self] in
            self?.openAccessibilitySettings()
        }
        onboarding.onRequestAccessibilityPrompt = { [weak self] in
            // Setup UI may prompt for Accessibility + post-event access.
            self?.attemptStartTap(prompt: true)
        }
        onboarding.onRetryTap = { [weak self] in
            self?.restartTap()
        }
    }

    private func wireSettings() {
        settings.onToggleTyping = { [weak self] in
            self?.toggleTyping()
        }
        settings.onSelectMethod = { [weak self] method in
            self?.setEngineMethod(method)
        }
        settings.onAutoRestoreChanged = { [weak self] on in
            guard let self else { return }
            self.state.autoRestore = on
            self.typingSession.resetCompose()
            self.applyEngineFlags()
            self.syncUI()
        }
        settings.onAutoCapitalizeChanged = { [weak self] on in
            guard let self else { return }
            self.state.autoCapitalize = on
            self.applyEngineFlags()
            self.syncUI()
        }
        settings.onOpenAccessibilitySettings = { [weak self] in
            self?.openAccessibilitySettings()
        }
        settings.onOpenAccessibilityGuide = { [weak self] in
            self?.onboarding.show()
        }
        settings.onProfilesChanged = { [weak self] in
            self?.refreshProfileCache()
            self?.syncUI()
        }
        settings.onToggleHotkeyChanged = { [weak self] in
            self?.reregisterToggleHotkey()
            self?.syncUI()
        }
        settings.onToggleHotkeyRecordingChanged = { [weak self] recording in
            guard let self else { return }
            if recording {
                // Avoid capturing the new combo as a toggle press.
                self.toggleHotkeyRegistrar.clearHotKey()
            } else {
                self.reregisterToggleHotkey()
            }
        }
        settings.onWindowDidClose = { [weak self] in
            // Ensure accessory policy even if user closed via red traffic light.
            guard let self else { return }
            self.state.isRecordingToggleHotkey = false
            self.reregisterToggleHotkey()
            NSApp.setActivationPolicy(.accessory)
            self.syncUI()
        }
        settings.onSetLaunchAtLogin = { [weak self] enabled in
            self?.setLaunchAtLogin(enabled) ?? false
        }
        settings.onRefreshLaunchAtLoginState = { [weak self] in
            self?.refreshLaunchAtLoginState()
        }
        settings.onOpenLoginItemsSettings = { [weak self] in
            self?.openLoginItemsSettings()
        }
        settings.onCheckForUpdates = { [weak self] in
            self?.checkForUpdatesNow()
        }
    }

    private func toggleTyping() {
        state.typingEnabled.toggle()
        typingSession.resetCompose()
        refreshProfileCache()
        syncUI()
    }

    // MARK: - Launch at login (SET-06)

    /// Mirror the real `SMAppService` status into AppState. Call at launch and
    /// after every toggle. Never guesses from `launchAtLoginDesired`.
    func refreshLaunchAtLoginState() {
        state.applyLaunchAtLoginState(LaunchAtLogin.currentState)
    }

    /// Toggle the login item. Mirrors real status/error into AppState.
    /// - Returns: `true` when the requested state is now active (or requires user approval).
    @discardableResult
    func setLaunchAtLogin(_ enabled: Bool) -> Bool {
        state.launchAtLoginDesired = enabled
        switch LaunchAtLogin.setEnabled(enabled) {
        case .success(let mirrored):
            state.applyLaunchAtLoginState(mirrored)
            return true
        case .failure(let error):
            // Keep the toggle visible but reflect the failure (e.g. not signed in).
            state.applyLaunchAtLoginState(.error(error.localizedDescription))
            return false
        }
    }

    func openLoginItemsSettings() {
        LaunchAtLogin.openLoginItemsSettings()
    }

    // MARK: - Update check (UPDATE-01)

    /// Background check (24h throttle) then mirror into AppState + menu.
    /// Flips to `.checking` first so the menu shows progress; the completion
    /// always lands on a terminal state (`.none` on throttle skip).
    func checkForUpdates() {
        state.releaseCheckState = .checking
        syncUI()
        updateChecker.checkIfNeeded { [weak self] result in
            DispatchQueue.main.async {
                self?.applyUpdateResult(result)
            }
        }
    }

    /// Manual check (menu action) — bypasses throttle.
    func checkForUpdatesNow() {
        state.releaseCheckState = .checking
        syncUI()
        updateChecker.checkNow { [weak self] result in
            DispatchQueue.main.async {
                self?.applyUpdateResult(result)
            }
        }
    }

    private func applyUpdateResult(_ result: ReleaseCheckResult) {
        state.releaseCheckState = result.state
        state.releaseInfo = result.release
        syncUI()
    }

    func openLatestReleasePage() {
        updateChecker.openLatestReleasePage()
    }

    func openHomebrewUpdateGuide() {
        updateChecker.openHomebrewGuide()
    }

    /// Force rebind (settings change / launch). Always tears down then installs.
    private func reregisterToggleHotkey() {
        guard !state.isRecordingToggleHotkey else {
            toggleHotkeyRegistrar.clearHotKey()
            return
        }
        toggleHotkeyRegistrar.register(state.toggleHotkey)
    }

    /// Recovery path (AX ready / restart / wake): install only when not already live.
    /// Must NOT call `register` while registered — that clears the running mod-only tap.
    private func ensureToggleHotkeyRegistered() {
        switch ToggleHotkeyRecoveryPolicy.action(
            isRecording: state.isRecordingToggleHotkey,
            isRegistered: toggleHotkeyRegistrar.isRegistered
        ) {
        case .clear:
            toggleHotkeyRegistrar.clearHotKey()
        case .noop:
            break
        case .register:
            toggleHotkeyRegistrar.registerIfNeeded(state.toggleHotkey)
        }
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
            settings.refresh()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.menuBar.refresh()
                self?.onboarding.refreshStatus()
                self?.settings.refresh()
            }
        }
    }
}
