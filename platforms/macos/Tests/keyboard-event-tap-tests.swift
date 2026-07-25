// Dấu macOS — KeyboardEventTap recovery / watchdog unit tests (TG-00).
// No real CGEventTapCreate; uses FakeEventTapPortControl + ManualEventTapClock.

import XCTest

final class KeyboardEventTapTests: XCTestCase {
    private var tap: KeyboardEventTap!
    private var fakePort: FakeEventTapPortControl!
    private var clock: ManualEventTapClock!
    private var resetCount = 0
    private var healthOk = true

    override func setUp() {
        super.setUp()
        tap = KeyboardEventTap()
        fakePort = FakeEventTapPortControl()
        clock = ManualEventTapClock()
        clock.now = 100
        tap.clock = clock
        healthOk = true
        tap.healthCheck = { [weak self] in self?.healthOk ?? false }
        resetCount = 0
        tap.onTapReset = { [weak self] in self?.resetCount += 1 }
        tap.installFakePortForTesting(fakePort)
    }

    override func tearDown() {
        tap.stopClean()
        tap = nil
        fakePort = nil
        clock = nil
        super.tearDown()
    }

    // MARK: - Pure recovery policy

    func testSystemTimeoutUnhealthyStopsDegradedWithoutReenable() {
        var state = EventTapRecoveryState()
        state.noteStarted(now: 0)
        let action = state.onSystemDisabled(reason: .timeout, healthOk: false, now: 1)
        XCTAssertEqual(action, .stopDegraded)
        XCTAssertTrue(state.isDegraded)
    }

    func testSystemTimeoutHealthyRecreatesOnceThenStopsStorm() {
        var state = EventTapRecoveryState()
        state.maxRecreatesPerWindow = 1
        state.stormWindowSeconds = 5
        state.noteStarted(now: 0)

        let first = state.onSystemDisabled(reason: .timeout, healthOk: true, now: 1)
        XCTAssertEqual(first, .recreate)
        state.noteRecreateAttempt(succeeded: true, now: 1)

        let second = state.onSystemDisabled(reason: .timeout, healthOk: true, now: 2)
        XCTAssertEqual(second, .stopDegraded, "no restart storm inside window")
    }

    func testWatchdogReenableWhenHealthy() {
        var state = EventTapRecoveryState()
        state.noteStarted(now: 0)
        let action = state.onWatchdogTick(
            portEnabled: false,
            healthOk: true,
            reenableSucceeded: true,
            now: 1
        )
        XCTAssertEqual(action, .reenable)
        XCTAssertFalse(state.isDegraded)
    }

    func testWatchdogRecreateFailurePath() {
        var state = EventTapRecoveryState()
        state.noteStarted(now: 0)
        let action = state.onWatchdogTick(
            portEnabled: false,
            healthOk: true,
            reenableSucceeded: false,
            now: 1
        )
        XCTAssertEqual(action, .recreate)
        state.noteRecreateAttempt(succeeded: false, now: 1)
        XCTAssertTrue(state.isDegraded)
    }

    // MARK: - Fake port integration

    func testSystemDisabledHealthyRecreatesFakePort() {
        let genBefore = tap.generation
        healthOk = true
        fakePort.allowEnable = true
        fakePort.isEnabled = false

        tap.handleSystemDisabled(reason: .timeout)

        XCTAssertTrue(tap.isRunning)
        XCTAssertGreaterThan(tap.generation, genBefore)
        XCTAssertFalse(tap.isDegraded)
        XCTAssertGreaterThanOrEqual(resetCount, 1)
    }

    func testSystemDisabledUnhealthyLeavesDegradedStopped() {
        healthOk = false
        fakePort.isEnabled = false

        tap.handleSystemDisabled(reason: .timeout)

        XCTAssertFalse(tap.isRunning)
        if case .degradedStopped = tap.status {
            // expected
        } else {
            XCTFail("expected degradedStopped, got \(tap.status)")
        }
        XCTAssertTrue(tap.isDegraded)
        XCTAssertEqual(fakePort.isEnabled, false)
    }

    func testWatchdogReenableHealthyWithoutRecreateStorm() {
        healthOk = true
        fakePort.allowEnable = true
        fakePort.isEnabled = false
        let genBefore = tap.generation
        let enableBefore = fakePort.enableCallCount

        tap.watchdogTick()

        XCTAssertTrue(fakePort.isEnabled)
        XCTAssertGreaterThan(fakePort.enableCallCount, enableBefore)
        XCTAssertEqual(tap.generation, genBefore, "re-enable must not bump generation")
        XCTAssertTrue(tap.isRunning)
    }

    func testWatchdogRecreateFailureSetsDegradedAndReflectsNotRunning() {
        healthOk = true
        fakePort.allowEnable = false
        fakePort.isEnabled = false

        tap.watchdogTick()

        // First tick: re-enable fails → recreate; fake start also fails enable → degraded.
        XCTAssertFalse(tap.isRunning)
        if case .degradedStopped = tap.status {
            // expected
        } else {
            XCTFail("expected degradedStopped after recreate failure, got \(tap.status)")
        }
        XCTAssertTrue(tap.isDegraded)
    }

    func testNoRestartStormAcrossWatchdogTicks() {
        healthOk = true
        fakePort.allowEnable = false
        fakePort.isEnabled = false

        tap.watchdogTick()
        let genAfterFirst = tap.generation
        let invalidateAfterFirst = fakePort.invalidateCallCount

        clock.advance(0.5)
        tap.watchdogTick()
        tap.watchdogTick()

        // Still degraded; must not keep inventing new generations / storm recreates.
        XCTAssertEqual(tap.generation, genAfterFirst)
        XCTAssertEqual(fakePort.invalidateCallCount, invalidateAfterFirst)
        if case .degradedStopped = tap.status {
            // expected
        } else {
            XCTFail("expected stay degradedStopped, got \(tap.status)")
        }
    }

    func testStormWindowAllowsRecreateAfterCooldown() {
        var state = EventTapRecoveryState()
        state.maxRecreatesPerWindow = 1
        state.stormWindowSeconds = 5
        state.noteStarted(now: 0)
        _ = state.onSystemDisabled(reason: .timeout, healthOk: true, now: 1)
        state.noteRecreateAttempt(succeeded: true, now: 1)

        let blocked = state.onSystemDisabled(reason: .timeout, healthOk: true, now: 2)
        XCTAssertEqual(blocked, .stopDegraded)

        let afterWindow = state.onSystemDisabled(reason: .timeout, healthOk: true, now: 10)
        XCTAssertEqual(afterWindow, .recreate)
    }

    func testInstallFakePortReportsRunningGeneration() {
        XCTAssertTrue(tap.isRunning)
        XCTAssertGreaterThan(tap.generation, 0)
        XCTAssertEqual(tap.status, .running(.session))
    }
}
