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

    func testOnboardingRequiresPostEventPermissionWhenTapIsRunning() {
        let suite = "dau.tg00.onboarding-post-access"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let state = AppState(defaults: defaults)
        state.accessibilityTrusted = true
        state.eventTapRunning = true
        state.postEventAccessGranted = false

        XCTAssertEqual(state.onboardingPhase, .needsPostEventAccess)
        XCTAssertFalse(state.onboardingPhase == .ready)
    }

    // MARK: - SyntheticPostAccess cache (no prompt on hot path default)

    func testSyntheticPostAccessDefaultCheckReadsCacheOnly() {
        SyntheticPostAccess.resetToDefault()
        SyntheticPostAccess.setCachedGranted(false)
        XCTAssertFalse(SyntheticPostAccess.isGranted)
        SyntheticPostAccess.setCachedGranted(true)
        XCTAssertTrue(SyntheticPostAccess.isGranted)
        // Override check still works for tests.
        var calls = 0
        SyntheticPostAccess.check = {
            calls += 1
            return false
        }
        XCTAssertFalse(SyntheticPostAccess.isGranted)
        XCTAssertEqual(calls, 1)
        SyntheticPostAccess.resetToDefault()
        // UI re-prompt tracking resets with the cache.
        XCTAssertFalse(SyntheticPostAccess.didRequestThisProcess)
    }

    func testLaunchPostEventRecoveryRequestsOnlyWhenFinderLaunchIsNotReady() {
        XCTAssertTrue(
            LaunchPostEventRecoveryPolicy.shouldRequest(
                accessibilityTrusted: true,
                eventTapRunning: true,
                postEventAccessGranted: false,
                didRequestThisProcess: false
            )
        )
        XCTAssertFalse(
            LaunchPostEventRecoveryPolicy.shouldRequest(
                accessibilityTrusted: false,
                eventTapRunning: true,
                postEventAccessGranted: false,
                didRequestThisProcess: false
            )
        )
        XCTAssertFalse(
            LaunchPostEventRecoveryPolicy.shouldRequest(
                accessibilityTrusted: true,
                eventTapRunning: false,
                postEventAccessGranted: false,
                didRequestThisProcess: false
            )
        )
        XCTAssertFalse(
            LaunchPostEventRecoveryPolicy.shouldRequest(
                accessibilityTrusted: true,
                eventTapRunning: true,
                postEventAccessGranted: true,
                didRequestThisProcess: false
            )
        )
        XCTAssertFalse(
            LaunchPostEventRecoveryPolicy.shouldRequest(
                accessibilityTrusted: true,
                eventTapRunning: true,
                postEventAccessGranted: false,
                didRequestThisProcess: true
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
}
