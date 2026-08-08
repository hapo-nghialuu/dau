// Dấu macOS — startup/shutdown orchestration + TypingSession wiring (WP-06 / P0-2 / TG-00).
// CRITICAL: EventTap callback must NEVER call permission prompts, unbounded AX, or hang on inject.
// Hot path: early EN/boundary fail-open → TypingSession.handleKey (bounded budget) → optional inject.

import AppKit
import Foundation

final class AppDelegate: NSObject, NSApplicationDelegate {
    let state = AppState()

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
    private let toggleHotkeyRegistrar = ToggleHotkeyRegistrar()

    private var cachedSettings: ResolvedInjectionSettings = ResolvedInjectionSettings(
        typingEnabled: true,
        engineMethod: .telex,
        injectionMethod: .backspaceFast,
        delays: .zero,
        source: .safeDefault
    )

    private var axPollTimer: Timer?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var sleepWakeEngine = SleepWakeLifecycleEngine()
    private var keyboardLatencyActivity: NSObjectProtocol?
    private let updateChecker = UpdateChecker()
    private var pendingRestart: DispatchWorkItem?
    private var onboardingObserver: NSObjectProtocol?
    private var hasRelaunchedForBundleChange = false
    private lazy var bundleWatcher = BundleWatcher { [weak self] in self?.handleBundleChange() }
    /// True once startEngine() has wired keyHandler + observers. Guards against recovery paths
    /// (requestLaunchPermissionRecoveryIfNeeded, pollAccessibility) starting the tap without
    /// wiring the keyHandler — which would leave the tap running but processing nothing.
    private var engineStarted = false

    // MARK: - NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        registerDefaultSettings()
        NSApp.setActivationPolicy(.accessory)

        keyboardLatencyActivity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep, .latencyCritical],
            reason: "Dấu keyboard event tap latency"
        )

        warmUpEventPostChannel()
        bundleWatcher.start()

        typingSession.onInjectCompleted = { result in
            if case .failure = result {
                fputs("[dau] inject failed; compose cleared\n", stderr)
            }
        }
        typingSession.onCallbackTelemetry = { line in
            fputs("[dau] \(line)\n", stderr)
        }

        // Hotkey callback (always needed, even before engine start, for UI responsiveness)
        toggleHotkeyRegistrar.onHotkey = { [weak self] in
            self?.toggleTyping()
        }

        wireMenuBar()
        wireOnboarding()
        wireSettings()
        menuBar.start()
        registerSleepWakeObservers()

        // Onboarding gate — port GoNhanh: only start engine when completed + trusted.
        onboardingObserver = NotificationCenter.default.addObserver(
            forName: .onboardingCompleted,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.onboardingDidComplete()
        }

        if state.hasCompletedOnboarding, KeyboardEventTap.isAccessibilityTrusted(prompt: false) {
            startEngine()
        } else {
            onboarding.show()
        }
        requestLaunchPermissionRecoveryIfNeeded()

        refreshLaunchAtLoginState()
        checkForUpdates()

        fputs("[dau] app launched \(state.versionLabel) (TypingSession hot path, TG-00 fail-open)\n", stderr)
    }

    private func registerDefaultSettings() {
        AppState.registerDefaultSettings()
    }

    /// Wire engine + tap + observers — mirrors GoNhanh MenuBar.startEngine.
    /// Idempotent: safe to call from recovery paths; no-ops if already started.
    private func startEngine() {
        guard !engineStarted else { return }
        engineStarted = true
        applyEngineFlags()
        refreshProfileCache()

        eventTap.onTapReset = { [weak self] in
            self?.typingSession.resetComposeAsync()
            DispatchQueue.main.async { self?.syncEventTapStateToUI() }
        }
        eventTap.healthCheck = { [weak self] in
            guard self != nil else { return false }
            return KeyboardEventTap.isAccessibilityTrusted(prompt: false)
        }
        eventTap.onTelemetry = { line in
            fputs("[dau] \(line)\n", stderr)
        }
        eventTap.keyHandler = { [weak self] key, _, _ in
            guard let self else { return .pass }
            let decision = self.typingSession.handleKey(key)
            return decision.consumeOriginal ? .consume : .pass
        }

        reregisterToggleHotkey()

        focusObserver.onFocusChange = { [weak self] _, _ in
            self?.typingSession.resetCompose()
            self?.refreshProfileCache()
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
                self.state.statusDetail = "source ok"
            } else {
                self.state.statusDetail = ""
            }
            self.refreshProfileCache()
            self.syncUI()
        }
        inputSourceObserver.start()

        startAXPolling()
        attemptStartTap(prompt: false)
    }

    @objc private func onboardingDidComplete() {
        // Mirror GoNhanh onboardingDidComplete: update button, start engine, enable launch at login.
        startEngine()
        _ = setLaunchAtLogin(true)
        syncUI()
    }

    func cancelPendingRestart() {
        pendingRestart?.cancel()
        pendingRestart = nil
    }

    private func requestLaunchPermissionRecoveryIfNeeded() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // Only attempt recovery when onboarding already completed — otherwise onboarding handles it.
            guard self.state.hasCompletedOnboarding else { return }
            // Engine already started at launch (both conditions were true) — nothing to recover.
            guard !self.engineStarted else { return }
            guard LaunchPermissionRecoveryPolicy.shouldRequestAccessibility(
                accessibilityTrusted: self.state.accessibilityTrusted
            ) else { return }
            fputs("[dau] launch permission recovery: AX untrusted at launch, will start engine when trust is granted\n", stderr)
            // Do not call attemptStartTap directly — it starts the tap without wiring keyHandler.
            // Instead, the AX poll timer (startAXPolling below) will detect when trust is granted
            // and call startEngine() via pollAccessibility(). Start polling now.
            self.startAXPolling()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        bundleWatcher.stop()
        cancelPendingRestart()
        if let keyboardLatencyActivity {
            ProcessInfo.processInfo.endActivity(keyboardLatencyActivity)
            self.keyboardLatencyActivity = nil
        }
        if let obs = onboardingObserver {
            NotificationCenter.default.removeObserver(obs)
            onboardingObserver = nil
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

    private func handleBundleChange() {
        guard !hasRelaunchedForBundleChange else { return }
        let fm = FileManager.default
        let onDiskPath = "/Applications/Dau.app/Contents/MacOS/Dau"
        // When running from /Applications, onDiskPath == executablePath, but the file content may have changed (new ad-hoc hash).
        // Detect change via version string or file mtime.
        let runningVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        var onDiskVersion: String?
        if let dict = NSDictionary(contentsOfFile: "/Applications/Dau.app/Contents/Info.plist") as? [String: Any] {
            onDiskVersion = dict["CFBundleShortVersionString"] as? String
        }
        var shouldRelaunch = false
        if let od = onDiskVersion, od != runningVersion {
            shouldRelaunch = true
        } else {
            // Fallback: detect same-version ad-hoc binary change.
            let executablePath = Bundle.main.executablePath ?? ""
            let samePath = onDiskPath == executablePath
            if samePath {
                // Running from /Applications: onDiskPath == executablePath, so mtime comparison
                // always returns equal (same inode after atomic rename). Trust the DispatchSource
                // event — it only fires on write/extend/attrib/rename/delete, i.e. a real change.
                shouldRelaunch = true
            } else if let attrs = try? fm.attributesOfItem(atPath: onDiskPath),
                      let mtime = attrs[.modificationDate] as? Date {
                // Running from a different path (e.g. build/Release): compare mtimes.
                if mtime.timeIntervalSinceNow > -5 {
                    shouldRelaunch = true
                } else if let runningAttrs = try? fm.attributesOfItem(atPath: executablePath),
                          let rtime = runningAttrs[.modificationDate] as? Date,
                          mtime > rtime {
                    shouldRelaunch = true
                }
            } else if fm.fileExists(atPath: onDiskPath) {
                shouldRelaunch = true
            }
        }
        guard shouldRelaunch else { return }
        hasRelaunchedForBundleChange = true
        fputs("[dau] bundle watcher: on-disk binary changed (running=\(runningVersion) onDisk=\(onDiskVersion ?? "unknown")) → relaunch\n", stderr)
        let path = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 0.5; /usr/bin/open \"$1\"", "_", path]
        try? task.run()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            NSApp.terminate(nil)
        }
    }

    // MARK: - Profile / engine → TypingSession

    private func refreshProfileCache() {
        let snapshot = contextResolver.current
        profileResolver.globalTypingEnabled = state.typingEnabled
        profileResolver.globalEngineMethod = state.engineMethod.asOverride
        cachedSettings = profileResolver.resolve(context: snapshot)

        let enabled =
            state.typingEnabled
            && !state.inputSourceBlocked
            && cachedSettings.typingEnabled

        let method = cachedSettings.effectiveInjectionMethod
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
        typingSession.setEnabled(true)
        typingSession.setMethod(state.engineMethod.asDauMethod)
        typingSession.setAutoRestore(state.autoRestore)
        typingSession.setAutoCapitalize(state.autoCapitalize)
    }

    // MARK: - Tap / AX

    private func attemptStartTap(prompt: Bool) {
        state.accessibilityTrusted = KeyboardEventTap.isAccessibilityTrusted(prompt: false)
        if prompt {
            // Legacy prompt path — kept for API compat but not used in onboarding (GoNhanh parity prefers System Settings).
            _ = KeyboardEventTap.isAccessibilityTrusted(prompt: true)
            state.accessibilityTrusted = KeyboardEventTap.isAccessibilityTrusted(prompt: false)
        }
        if state.accessibilityTrusted {
            let ok = eventTap.start(promptForAccessibility: false)
            syncEventTapStateToUI(fallbackDetail: ok ? nil : "event tap create failed")
            if !ok {
                startAXPolling()
            } else {
                stopAXPollingIfHealthy()
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
        ensureToggleHotkeyRegistered()
        refreshProfileCache()
        syncUI()
        onboarding.refreshStatus()
    }

    private func syncEventTapStateToUI(fallbackDetail: String? = nil) {
        let running = eventTap.isRunning
        let degraded = eventTap.isDegraded || {
            if case .degradedStopped = eventTap.status { return true }
            return false
        }()
        var detail = fallbackDetail
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
            !state.eventTapDegraded {
            stopAXPolling()
        }
    }

    private func pollAccessibility() {
        let trusted = KeyboardEventTap.isAccessibilityTrusted(prompt: false)
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
            if !engineStarted {
                // Engine not yet wired — startEngine() handles wiring + tap start.
                // Happens when onboarding completed but AX was untrusted at launch.
                fputs("[dau] launch permission recovery: AX trust granted, starting engine\n", stderr)
                startEngine()
            } else {
                attemptStartTap(prompt: false)
            }
        }
        if decision.refreshUI {
            syncUI()
            onboarding.refreshStatus()
        }
        if decision.stopPolling {
            stopAXPolling()
            return
        }
    }

    private func openAccessibilitySettings() {
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

    func handleSleepWake(_ phase: SleepWakePhase) {
        let trusted = KeyboardEventTap.isAccessibilityTrusted(prompt: false)
        state.accessibilityTrusted = trusted
        let decision = sleepWakeEngine.handle(phase, accessibilityTrusted: trusted)
        state.lastLifecycleTransition = decision.transitionLabel
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
            startAXPolling()
            syncUI()
            return
        }

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
            ensureToggleHotkeyRegistered()
            typingSession.resetComposeAsync()
            refreshProfileCache()
            warmUpEventPostChannel()
            syncUI()
            onboarding.refreshStatus()
        }
    }

    private func warmUpEventPostChannel() {
        DispatchQueue.global(qos: .utility).async {
            guard let source = CGEventSource(stateID: .privateState)
                ?? CGEventSource(stateID: .combinedSessionState)
            else { return }
            _ = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
            guard let event = CGEvent(source: source) else { return }
            SyntheticEventMarker.apply(to: event)
            event.post(tap: .cgSessionEventTap)
        }
    }

    // MARK: - Menu / onboarding wiring

    private func wireMenuBar() {
        menuBar.onToggleTyping = { [weak self] in self?.toggleTyping() }
        menuBar.onSelectTelex = { [weak self] in self?.setEngineMethod(.telex) }
        menuBar.onSelectVNI = { [weak self] in self?.setEngineMethod(.vni) }
        menuBar.onOpenAccessibilitySettings = { [weak self] in self?.openAccessibilitySettings() }
        menuBar.onRestartTap = { [weak self] in self?.restartTap() }
        menuBar.onShowSettings = { [weak self] in self?.settings.show(page: .general) }
        menuBar.onShowAbout = { [weak self] in self?.settings.show(page: .about) }
        menuBar.onShowOnboarding = { [weak self] in self?.onboarding.show() }
        menuBar.onQuit = { NSApp.terminate(nil) }
        menuBar.onCheckForUpdates = { [weak self] in self?.checkForUpdatesNow() }
        menuBar.onOpenLatestRelease = { [weak self] in self?.openLatestReleasePage() }
        menuBar.onOpenUpdateGuide = { [weak self] in self?.openHomebrewUpdateGuide() }
    }

    private func wireOnboarding() {
        onboarding.onOpenSystemSettings = { [weak self] in self?.openAccessibilitySettings() }
        // No prompt — GoNhanh parity: only “Mở Cài đặt” opens System Settings.
    }

    private func wireSettings() {
        settings.onToggleTyping = { [weak self] in self?.toggleTyping() }
        settings.onSelectMethod = { [weak self] method in self?.setEngineMethod(method) }
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
        settings.onOpenAccessibilitySettings = { [weak self] in self?.openAccessibilitySettings() }
        settings.onOpenAccessibilityGuide = { [weak self] in self?.onboarding.show() }
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
                self.toggleHotkeyRegistrar.clearHotKey()
            } else {
                self.reregisterToggleHotkey()
            }
        }
        settings.onWindowDidClose = { [weak self] in
            guard let self else { return }
            self.state.isRecordingToggleHotkey = false
            self.reregisterToggleHotkey()
            NSApp.setActivationPolicy(.accessory)
            self.syncUI()
        }
        settings.onSetLaunchAtLogin = { [weak self] enabled in self?.setLaunchAtLogin(enabled) ?? false }
        settings.onRefreshLaunchAtLoginState = { [weak self] in self?.refreshLaunchAtLoginState() }
        settings.onOpenLoginItemsSettings = { [weak self] in self?.openLoginItemsSettings() }
        settings.onCheckForUpdates = { [weak self] in self?.checkForUpdatesNow() }
    }

    private func toggleTyping() {
        state.typingEnabled.toggle()
        typingSession.resetCompose()
        refreshProfileCache()
        syncUI()
    }

    // MARK: - Launch at login (SET-06)

    func refreshLaunchAtLoginState() {
        state.applyLaunchAtLoginState(LaunchAtLogin.currentState)
    }

    @discardableResult
    func setLaunchAtLogin(_ enabled: Bool) -> Bool {
        state.launchAtLoginDesired = enabled
        switch LaunchAtLogin.setEnabled(enabled) {
        case .success(let mirrored):
            state.applyLaunchAtLoginState(mirrored)
            return true
        case .failure(let error):
            state.applyLaunchAtLoginState(.error(error.localizedDescription))
            return false
        }
    }

    func openLoginItemsSettings() {
        LaunchAtLogin.openLoginItemsSettings()
    }

    // MARK: - Update check (UPDATE-01)

    func checkForUpdates() {
        state.releaseCheckState = .checking
        syncUI()
        updateChecker.checkIfNeeded { [weak self] result in
            DispatchQueue.main.async { self?.applyUpdateResult(result) }
        }
    }

    func checkForUpdatesNow() {
        state.releaseCheckState = .checking
        syncUI()
        updateChecker.checkNow { [weak self] result in
            DispatchQueue.main.async { self?.applyUpdateResult(result) }
        }
    }

    private func applyUpdateResult(_ result: ReleaseCheckResult) {
        state.releaseCheckState = result.state
        state.releaseInfo = result.release
        syncUI()
    }

    func openLatestReleasePage() { updateChecker.openLatestReleasePage() }
    func openHomebrewUpdateGuide() { updateChecker.openHomebrewGuide() }

    private func reregisterToggleHotkey() {
        guard !state.isRecordingToggleHotkey else {
            toggleHotkeyRegistrar.clearHotKey()
            return
        }
        toggleHotkeyRegistrar.register(state.toggleHotkey)
    }

    private func ensureToggleHotkeyRegistered() {
        switch ToggleHotkeyRecoveryPolicy.action(
            isRecording: state.isRecordingToggleHotkey,
            isRegistered: toggleHotkeyRegistrar.isRegistered
        ) {
        case .clear: toggleHotkeyRegistrar.clearHotKey()
        case .noop: break
        case .register: toggleHotkeyRegistrar.registerIfNeeded(state.toggleHotkey)
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
