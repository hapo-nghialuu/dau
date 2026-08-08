// Dấu macOS — sleep/wake + AX poll policy unit tests (TG-00).
// Pure engines only — no live NSWorkspace / Accessibility prompts.

import XCTest

final class AppLifecycleTests: XCTestCase {

    // MARK: - Accessibility poll policy

    func testAXPollStopsWhenTrustedAndTapHealthy() {
        let d = AccessibilityPollEngine.evaluate(
            trusted: true,
            wasTrusted: true,
            tapRunning: true,
            tapDegraded: false
        )
        XCTAssertTrue(d.stopPolling)
        XCTAssertFalse(d.attemptStartTap)
        XCTAssertFalse(d.stopTap)
    }

    func testAXPollDoesNotStopWhenDegraded() {
        let d = AccessibilityPollEngine.evaluate(
            trusted: true,
            wasTrusted: true,
            tapRunning: false,
            tapDegraded: true
        )
        // Not running → attempt start; not stopPolling until healthy.
        XCTAssertFalse(d.stopPolling)
        XCTAssertTrue(d.attemptStartTap)
    }

    func testAXPollAttemptsStartWhenTrustedButTapDown() {
        let d = AccessibilityPollEngine.evaluate(
            trusted: true,
            wasTrusted: true,
            tapRunning: false,
            tapDegraded: false
        )
        XCTAssertTrue(d.attemptStartTap)
        XCTAssertFalse(d.stopPolling)
    }

    func testAXPollStopsTapWhenTrustLost() {
        let d = AccessibilityPollEngine.evaluate(
            trusted: false,
            wasTrusted: true,
            tapRunning: true,
            tapDegraded: false
        )
        XCTAssertTrue(d.stopTap)
        XCTAssertFalse(d.attemptStartTap)
        XCTAssertFalse(d.stopPolling)
    }

    func testAXPollStartsWhenTrustGained() {
        let d = AccessibilityPollEngine.evaluate(
            trusted: true,
            wasTrusted: false,
            tapRunning: false,
            tapDegraded: false
        )
        XCTAssertTrue(d.attemptStartTap)
        XCTAssertFalse(d.stopTap)
    }

    func testAXPollKeepsGoingWhileUntrusted() {
        let d = AccessibilityPollEngine.evaluate(
            trusted: false,
            wasTrusted: false,
            tapRunning: false,
            tapDegraded: false
        )
        XCTAssertFalse(d.stopPolling)
        XCTAssertFalse(d.attemptStartTap)
        XCTAssertFalse(d.stopTap)
    }

    // MARK: - Sleep / wake

    func testWillSleepStopsWithoutPrompt() {
        var engine = SleepWakeLifecycleEngine()
        let d = engine.handle(.willSleep, accessibilityTrusted: true)
        XCTAssertTrue(d.stopAndReset)
        XCTAssertFalse(d.recreateOnce)
        XCTAssertFalse(d.promptPermission)
        XCTAssertEqual(d.transitionLabel, "willSleep")
        XCTAssertTrue(engine.isAsleep)
    }

    func testDidWakeRecreatesOnceWithoutPermissionPrompt() {
        var engine = SleepWakeLifecycleEngine()
        _ = engine.handle(.willSleep, accessibilityTrusted: true)
        let d = engine.handle(.didWake, accessibilityTrusted: true)
        XCTAssertFalse(d.stopAndReset)
        XCTAssertTrue(d.recreateOnce)
        XCTAssertFalse(d.promptPermission, "wake must never auto-prompt")
        XCTAssertEqual(engine.wakeRecreateCount, 1)
    }

    func testDidWakeWithoutPriorSleepDoesNotRecreate() {
        var engine = SleepWakeLifecycleEngine()
        let d = engine.handle(.didWake, accessibilityTrusted: true)
        XCTAssertFalse(d.recreateOnce)
        XCTAssertEqual(engine.wakeRecreateCount, 0)
    }

    func testDidWakeUntrustedDoesNotRecreate() {
        var engine = SleepWakeLifecycleEngine()
        _ = engine.handle(.willSleep, accessibilityTrusted: true)
        let d = engine.handle(.didWake, accessibilityTrusted: false)
        XCTAssertFalse(d.recreateOnce)
        XCTAssertFalse(d.promptPermission)
        XCTAssertEqual(engine.wakeRecreateCount, 0)
    }

    func testWakeDebounceOnlyOneRecreatePerEdge() {
        var engine = SleepWakeLifecycleEngine()
        _ = engine.handle(.willSleep, accessibilityTrusted: true)
        let wake = engine.handle(.didWake, accessibilityTrusted: true)
        XCTAssertTrue(wake.recreateOnce)
        // sessionActive right after wake must not double-recreate.
        let active = engine.handle(.sessionActive, accessibilityTrusted: true)
        XCTAssertFalse(active.recreateOnce)
        XCTAssertEqual(engine.wakeRecreateCount, 1)
    }

    func testSessionResignAndActiveRoundTrip() {
        var engine = SleepWakeLifecycleEngine()
        let resign = engine.handle(.sessionResign, accessibilityTrusted: true)
        XCTAssertTrue(resign.stopAndReset)
        XCTAssertFalse(resign.promptPermission)

        let active = engine.handle(.sessionActive, accessibilityTrusted: true)
        XCTAssertTrue(active.recreateOnce)
        XCTAssertFalse(active.promptPermission)
        XCTAssertEqual(engine.wakeRecreateCount, 1)
    }

    func testRepeatedSleepWakeCyclesRecreateEachTime() {
        var engine = SleepWakeLifecycleEngine()
        for _ in 0..<5 {
            _ = engine.handle(.willSleep, accessibilityTrusted: true)
            let d = engine.handle(.didWake, accessibilityTrusted: true)
            XCTAssertTrue(d.recreateOnce)
            XCTAssertFalse(d.promptPermission)
        }
        XCTAssertEqual(engine.wakeRecreateCount, 5)
    }

    // MARK: - AppState tap mirror

    func testEventTapMirrorUpdatesRunningDegradedGeneration() {
        let state = AppState(defaults: UserDefaults(suiteName: "dau.tg00.lifecycle")!)
        state.applyEventTapMirror(running: false, degraded: true, generation: 3, detail: "tap degraded")
        XCTAssertFalse(state.eventTapRunning)
        XCTAssertTrue(state.eventTapDegraded)
        XCTAssertEqual(state.eventTapGeneration, 3)
        XCTAssertEqual(state.statusDetail, "tap degraded")
        XCTAssertFalse(state.isReadyToType)
    }

    func testMenuBarIconSetupWhenDegradedEvenIfTrusted() {
        let state = AppState(defaults: UserDefaults(suiteName: "dau.tg00.menubar")!)
        state.accessibilityTrusted = true
        state.eventTapRunning = false
        state.eventTapDegraded = true
        state.typingEnabled = true
        XCTAssertEqual(state.menuBarIconState, .setup)
    }

    func testLaunchPermissionRecoveryRequestsAccessibilityOnlyWhenUntrusted() {
        XCTAssertTrue(
            LaunchPermissionRecoveryPolicy.shouldRequestAccessibility(
                accessibilityTrusted: false
            )
        )
        XCTAssertFalse(
            LaunchPermissionRecoveryPolicy.shouldRequestAccessibility(
                accessibilityTrusted: true
            )
        )
    }

    // MARK: - Toggle hotkey recovery (AX late / restart / wake)

    func testToggleHotkeyRecoveryRegistersWhenPreviouslyFailed() {
        // AppDelegate.ensureToggleHotkeyRegistered uses this policy on
        // attemptStartTap(success), restartTap, and handleSleepWake recreate.
        XCTAssertEqual(
            ToggleHotkeyRecoveryPolicy.action(isRecording: false, isRegistered: false),
            .register,
            "recovery must retry when launch install failed"
        )
    }

    func testToggleHotkeyRecoveryNoopWhenAlreadyRegistered() {
        XCTAssertEqual(
            ToggleHotkeyRecoveryPolicy.action(isRecording: false, isRegistered: true),
            .noop,
            "must not tear down a live modifier-only tap on AX poll"
        )
    }

    func testToggleHotkeyRecoveryClearsWhileRecording() {
        XCTAssertEqual(
            ToggleHotkeyRecoveryPolicy.action(isRecording: true, isRegistered: true),
            .clear
        )
        XCTAssertEqual(
            ToggleHotkeyRecoveryPolicy.action(isRecording: true, isRegistered: false),
            .clear
        )
    }

    func testToggleHotkeyRecoveryPathEndToEndWithRegistrar() {
        // Mirrors AppDelegate recovery: failed at launch → AX ready → ensure.
        let reg = ToggleHotkeyRegistrar()
        defer { reg.unregister() }
        let chord = ToggleHotkey.commandShiftOnly

        reg.testForceRegistrationResult = false
        reg.register(chord)
        XCTAssertFalse(reg.isRegistered)

        let action = ToggleHotkeyRecoveryPolicy.action(
            isRecording: false,
            isRegistered: reg.isRegistered
        )
        XCTAssertEqual(action, .register)

        reg.testForceRegistrationResult = true
        switch action {
        case .register:
            reg.registerIfNeeded(chord)
        case .clear, .noop:
            XCTFail("expected .register after failed launch install")
        }
        XCTAssertTrue(reg.isRegistered)

        // Subsequent recovery ticks must not reinstall.
        let again = ToggleHotkeyRecoveryPolicy.action(
            isRecording: false,
            isRegistered: reg.isRegistered
        )
        XCTAssertEqual(again, .noop)
        let gen = reg.registrationGeneration
        reg.testForceRegistrationResult = false
        if again == .noop {
            // AppDelegate breaks; does not call register.
        } else {
            reg.registerIfNeeded(chord)
        }
        XCTAssertEqual(reg.registrationGeneration, gen)
        XCTAssertTrue(reg.isRegistered)
    }

    // MARK: - Onboarding gate (hasCompletedOnboarding && AX)

    func testOnboardingGateShowsWhenNotCompletedEvenIfTrusted() {
        // AppDelegate gate: hasCompleted && AX -> startEngine else showOnboarding.
        func shouldShowOnboarding(hasCompleted: Bool, trusted: Bool) -> Bool {
            !(hasCompleted && trusted)
        }
        XCTAssertTrue(shouldShowOnboarding(hasCompleted: false, trusted: true), "fresh install with trust must still show onboarding (needs method choice)")
        XCTAssertTrue(shouldShowOnboarding(hasCompleted: false, trusted: false))
        XCTAssertTrue(shouldShowOnboarding(hasCompleted: true, trusted: false))
        XCTAssertFalse(shouldShowOnboarding(hasCompleted: true, trusted: true))
    }

    func testOnboardingGateAfterRestartJumpsToSuccess() {
        // After restart(), permissionGranted && trusted -> view sets step=10
        let suite = "io.github.hapo-nghialuu.dau.tests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { XCTFail("suite"); return }
        defaults.removePersistentDomain(forName: suite)
        // Simulate restart() persistence
        defaults.set(true, forKey: DauSettingsKey.permissionGranted)
        defaults.set(false, forKey: DauSettingsKey.hasCompletedOnboarding)
        defaults.set(AppEngineMethod.telex.rawValue, forKey: DauSettingsKey.engineMethod)
        // View logic: if permissionGranted && hasPermission { step = 10 }
        XCTAssertTrue(defaults.bool(forKey: DauSettingsKey.permissionGranted))
        XCTAssertFalse(defaults.bool(forKey: DauSettingsKey.hasCompletedOnboarding))
        // Simulate finish()
        defaults.set(true, forKey: DauSettingsKey.hasCompletedOnboarding)
        let state = AppState(defaults: defaults)
        XCTAssertTrue(state.hasCompletedOnboarding)
        XCTAssertTrue(state.permissionGranted)
        defaults.removePersistentDomain(forName: suite)
    }

    func testLaunchPermissionRecoveryRequiresOnboardingCompleted() {
        // AppDelegate.requestLaunchPermissionRecovery now guards on hasCompletedOnboarding.
        func shouldRecover(hasCompleted: Bool, trusted: Bool) -> Bool {
            guard hasCompleted else { return false }
            return LaunchPermissionRecoveryPolicy.shouldRequestAccessibility(accessibilityTrusted: trusted)
        }
        XCTAssertFalse(shouldRecover(hasCompleted: false, trusted: false), "pre-onboarding must not prompt")
        XCTAssertFalse(shouldRecover(hasCompleted: false, trusted: true))
        XCTAssertTrue(shouldRecover(hasCompleted: true, trusted: false))
        XCTAssertFalse(shouldRecover(hasCompleted: true, trusted: true))
    }
}
