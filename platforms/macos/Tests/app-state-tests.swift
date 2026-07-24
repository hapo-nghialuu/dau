// Dấu macOS — AppState menu icon / label mapping (MENU-02).

import XCTest

final class AppStateTests: XCTestCase {
    private func makeTrustedRunning(state: AppState) {
        state.accessibilityTrusted = true
        state.eventTapRunning = true
        state.inputSourceBlocked = false
    }

    // MARK: - Icon state mapping

    func testIconStateSetupWhenNotTrusted() {
        let state = AppState()
        state.accessibilityTrusted = false
        state.eventTapRunning = false
        state.typingEnabled = true
        XCTAssertEqual(state.menuBarIconState, .setup)
        XCTAssertEqual(state.menuBarIconState.assetName, "MenuBarSetup")
    }

    func testIconStateSetupWhenTrustedButTapStopped() {
        let state = AppState()
        state.accessibilityTrusted = true
        state.eventTapRunning = false
        state.typingEnabled = true
        state.inputSourceBlocked = false
        // Tap failed / stopped must not look like active VI.
        XCTAssertEqual(state.menuBarIconState, .setup)
        XCTAssertNotEqual(state.menuBarIconState, .active)
        XCTAssertEqual(state.menuBarIconState.assetName, "MenuBarSetup")
    }

    func testIconStateActiveVI() {
        let state = AppState()
        makeTrustedRunning(state: state)
        state.typingEnabled = true
        XCTAssertEqual(state.menuBarIconState, .active)
        XCTAssertEqual(state.menuBarIconState.assetName, "MenuBarActive")
    }

    func testIconStateInactiveEN() {
        let state = AppState()
        makeTrustedRunning(state: state)
        state.typingEnabled = false
        XCTAssertEqual(state.menuBarIconState, .inactive)
        XCTAssertEqual(state.menuBarIconState.assetName, "MenuBarInactive")
        XCTAssertNotEqual(state.menuBarIconState, .active)
    }

    func testIconStateBlockedNotActive() {
        let state = AppState()
        makeTrustedRunning(state: state)
        state.typingEnabled = true
        state.inputSourceBlocked = true
        // Blocked must never map to active VI icon.
        XCTAssertEqual(state.menuBarIconState, .inactive)
        XCTAssertNotEqual(state.menuBarIconState, .active)
        XCTAssertEqual(state.menuBarIconState.assetName, "MenuBarInactive")
    }

    func testIconStateBlockedWinsOverTypingEnabled() {
        let state = AppState()
        makeTrustedRunning(state: state)
        state.typingEnabled = true
        state.inputSourceBlocked = true
        XCTAssertEqual(state.menuBarIconState, .inactive)

        state.typingEnabled = false
        state.inputSourceBlocked = true
        XCTAssertEqual(state.menuBarIconState, .inactive)
    }

    // MARK: - Status-item title badge (logo + VI/EN when ready)

    func testMenuBarTitleEmptyWhenSetup() {
        let state = AppState()
        state.accessibilityTrusted = false
        state.eventTapRunning = false
        state.typingEnabled = true
        XCTAssertEqual(state.menuBarTitle, "")

        state.accessibilityTrusted = true
        state.eventTapRunning = false
        XCTAssertEqual(state.menuBarTitle, "")
    }

    func testMenuBarTitleVIWhenActive() {
        let state = AppState()
        makeTrustedRunning(state: state)
        state.typingEnabled = true
        XCTAssertEqual(state.menuBarTitle, "VI")
        XCTAssertTrue(state.isReadyToType)
    }

    func testMenuBarTitleEmptyWhenInactiveEN() {
        let state = AppState()
        makeTrustedRunning(state: state)
        state.typingEnabled = false
        // User: only show VI when ready to type VN; EN/setup = logo only.
        XCTAssertEqual(state.menuBarTitle, "")
    }

    func testMenuBarTitleEmptyWhenBlocked() {
        let state = AppState()
        makeTrustedRunning(state: state)
        state.typingEnabled = true
        state.inputSourceBlocked = true
        XCTAssertEqual(state.menuBarTitle, "")
    }

    // MARK: - toolTip / a11y labels

    func testToolTipAndAccessibilityForSetup() {
        let state = AppState()
        state.accessibilityTrusted = false
        state.eventTapRunning = false
        XCTAssertEqual(state.menuBarAccessibilityLabel, "Dấu — chưa sẵn sàng")
        XCTAssertTrue(state.menuBarToolTip.contains("Accessibility"))
    }

    func testToolTipAndAccessibilityForTapStopped() {
        let state = AppState()
        state.accessibilityTrusted = true
        state.eventTapRunning = false
        XCTAssertEqual(state.menuBarIconState, .setup)
        XCTAssertEqual(state.menuBarAccessibilityLabel, "Dấu — chưa sẵn sàng")
        XCTAssertTrue(state.menuBarToolTip.contains("event tap") || state.menuBarToolTip.contains("chưa chạy"))
    }

    func testToolTipAndAccessibilityForVI() {
        let state = AppState()
        makeTrustedRunning(state: state)
        state.typingEnabled = true
        XCTAssertEqual(state.menuBarToolTip, "Dấu — VI (đang gõ tiếng Việt)")
        XCTAssertEqual(state.menuBarAccessibilityLabel, "Dấu — VI")
    }

    func testToolTipAndAccessibilityForEN() {
        let state = AppState()
        makeTrustedRunning(state: state)
        state.typingEnabled = false
        XCTAssertEqual(state.menuBarToolTip, "Dấu — EN (tắt gõ tiếng Việt)")
        XCTAssertEqual(state.menuBarAccessibilityLabel, "Dấu — EN")
    }

    func testToolTipAndAccessibilityForBlocked() {
        let state = AppState()
        makeTrustedRunning(state: state)
        state.typingEnabled = true
        state.inputSourceBlocked = true
        XCTAssertTrue(state.menuBarToolTip.contains("tạm tắt") || state.menuBarToolTip.contains("EN"))
        XCTAssertEqual(state.menuBarAccessibilityLabel, "Dấu — EN, tạm tắt")
    }

    // MARK: - Accessibility menu label

    func testAccessibilityMenuLabelWhenGrantedAndRunning() {
        let state = AppState()
        makeTrustedRunning(state: state)
        XCTAssertEqual(state.accessibilityMenuLabel, "Accessibility: đã cấp quyền · đang gõ")
    }

    func testMenuHeaderSubtitleIncludesMethodAndShortcut() {
        let state = AppState()
        state.engineMethod = .telex
        XCTAssertEqual(state.menuHeaderSubtitle, "Telex · ⌘⇧E")
        state.engineMethod = .vni
        XCTAssertEqual(state.menuHeaderSubtitle, "VNI · ⌘⇧E")
    }

    func testAccessibilityMenuLabelWhenUntrusted() {
        let state = AppState()
        state.accessibilityTrusted = false
        state.eventTapRunning = false
        XCTAssertEqual(state.accessibilityMenuLabel, "Accessibility: chưa cấp quyền…")
    }

    func testAccessibilityMenuLabelWhenTrustedButTapDown() {
        let state = AppState()
        state.accessibilityTrusted = true
        state.eventTapRunning = false
        XCTAssertEqual(state.accessibilityMenuLabel, "Accessibility: đã cấp — đang khởi động…")
    }

    // MARK: - Asset name table (stable contract for menu bar controller)

    func testAssetNamesStable() {
        XCTAssertEqual(MenuBarIconState.setup.assetName, "MenuBarSetup")
        XCTAssertEqual(MenuBarIconState.active.assetName, "MenuBarActive")
        XCTAssertEqual(MenuBarIconState.inactive.assetName, "MenuBarInactive")
    }

    // MARK: - Engine mapping (unchanged)

    func testEngineMethodMapsToDauMethod() {
        XCTAssertEqual(AppEngineMethod.telex.asDauMethod, DauMethod_Telex)
        XCTAssertEqual(AppEngineMethod.vni.asDauMethod, DauMethod_Vni)
        XCTAssertEqual(AppEngineMethod.telex.asOverride, .telex)
        XCTAssertEqual(AppEngineMethod.vni.asOverride, .vni)
    }
}
