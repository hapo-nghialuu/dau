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

    func testMenuBarTitleENWhenSetup() {
        let state = AppState()
        state.accessibilityTrusted = false
        state.eventTapRunning = false
        state.typingEnabled = true
        XCTAssertEqual(state.menuBarTitle, "EN")

        state.accessibilityTrusted = true
        state.eventTapRunning = false
        XCTAssertEqual(state.menuBarTitle, "EN")
    }

    func testMenuBarTitleVIWhenActive() {
        let state = AppState()
        makeTrustedRunning(state: state)
        state.typingEnabled = true
        XCTAssertEqual(state.menuBarTitle, "VI")
        XCTAssertTrue(state.isReadyToType)
    }

    func testMenuBarTitleENWhenInactive() {
        let state = AppState()
        makeTrustedRunning(state: state)
        state.typingEnabled = false
        XCTAssertEqual(state.menuBarTitle, "EN")
    }

    func testMenuBarTitleENWhenBlocked() {
        let state = AppState()
        makeTrustedRunning(state: state)
        state.typingEnabled = true
        state.inputSourceBlocked = true
        XCTAssertEqual(state.menuBarTitle, "EN")
    }

    // MARK: - toolTip / a11y labels

    func testToolTipAndAccessibilityForSetup() {
        let state = AppState()
        state.accessibilityTrusted = false
        state.eventTapRunning = false
        XCTAssertTrue(state.menuBarAccessibilityLabel.contains("chưa sẵn sàng"))
        XCTAssertTrue(state.menuBarAccessibilityLabel.contains(state.toggleShortcutDisplay))
        XCTAssertTrue(state.menuBarToolTip.contains("Accessibility"))
        XCTAssertTrue(state.menuBarToolTip.contains(state.toggleShortcutDisplay))
    }

    func testToolTipAndAccessibilityForTapStopped() {
        let state = AppState()
        state.accessibilityTrusted = true
        state.eventTapRunning = false
        XCTAssertEqual(state.menuBarIconState, .setup)
        XCTAssertTrue(state.menuBarAccessibilityLabel.contains("chưa sẵn sàng"))
        XCTAssertTrue(state.menuBarToolTip.contains("event tap") || state.menuBarToolTip.contains("chưa chạy"))
        XCTAssertTrue(state.menuBarToolTip.contains(state.toggleShortcutDisplay))
    }

    func testToolTipAndAccessibilityForVI() {
        let state = AppState()
        makeTrustedRunning(state: state)
        state.typingEnabled = true
        XCTAssertTrue(state.menuBarToolTip.contains("VI (đang gõ tiếng Việt)"))
        XCTAssertTrue(state.menuBarToolTip.contains(state.toggleShortcutDisplay))
        XCTAssertTrue(state.menuBarAccessibilityLabel.contains("VI"))
        XCTAssertTrue(state.menuBarAccessibilityLabel.contains(state.toggleShortcutDisplay))
    }

    func testToolTipAndAccessibilityForEN() {
        let state = AppState()
        makeTrustedRunning(state: state)
        state.typingEnabled = false
        XCTAssertTrue(state.menuBarToolTip.contains("EN (tắt gõ tiếng Việt)"))
        XCTAssertTrue(state.menuBarToolTip.contains(state.toggleShortcutDisplay))
        XCTAssertTrue(state.menuBarAccessibilityLabel.hasPrefix("Dấu — EN"))
        XCTAssertTrue(state.menuBarAccessibilityLabel.contains(state.toggleShortcutDisplay))
    }

    func testToolTipAndAccessibilityForBlocked() {
        let state = AppState()
        makeTrustedRunning(state: state)
        state.typingEnabled = true
        state.inputSourceBlocked = true
        XCTAssertTrue(state.menuBarToolTip.contains("tạm tắt") || state.menuBarToolTip.contains("EN"))
        XCTAssertTrue(state.menuBarToolTip.contains(state.toggleShortcutDisplay))
        XCTAssertTrue(state.menuBarAccessibilityLabel.contains("EN"))
        XCTAssertTrue(state.menuBarAccessibilityLabel.contains("tạm tắt"))
        XCTAssertTrue(state.menuBarAccessibilityLabel.contains(state.toggleShortcutDisplay))
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
        XCTAssertEqual(state.menuHeaderSubtitle, "Telex · \(state.toggleShortcutDisplay)")
        state.engineMethod = .vni
        XCTAssertEqual(state.menuHeaderSubtitle, "VNI · \(state.toggleShortcutDisplay)")
        XCTAssertEqual(state.toggleHotkey, .default)
        XCTAssertEqual(state.toggleShortcutDisplay, "⇧⌘E")
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

    // MARK: - SET-06 preferences persistence

    func testDefaultsWhenKeysMissing() {
        let suite = "io.github.hapo-nghialuu.dau.tests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            XCTFail("suite")
            return
        }
        defaults.removePersistentDomain(forName: suite)
        let state = AppState(defaults: defaults)
        XCTAssertTrue(state.typingEnabled)
        XCTAssertEqual(state.engineMethod, .telex)
        XCTAssertTrue(state.autoRestore)
        XCTAssertFalse(state.autoCapitalize)
        XCTAssertFalse(state.launchAtLoginDesired)
        XCTAssertEqual(state.toggleHotkey, .default)
        XCTAssertEqual(state.toggleShortcutDisplay, AppState.defaultToggleShortcutDisplay)
        defaults.removePersistentDomain(forName: suite)
    }

    func testPersistsAndReloadsPreferences() {
        let suite = "io.github.hapo-nghialuu.dau.tests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            XCTFail("suite")
            return
        }
        defaults.removePersistentDomain(forName: suite)

        let writer = AppState(defaults: defaults)
        writer.typingEnabled = false
        writer.engineMethod = .vni
        writer.autoRestore = false
        writer.autoCapitalize = true
        writer.launchAtLoginDesired = true
        writer.toggleHotkey = ToggleHotkey(
            keyCode: 49,
            command: false,
            control: true,
            option: false,
            shift: false
        )

        let reader = AppState(defaults: defaults)
        XCTAssertFalse(reader.typingEnabled)
        XCTAssertEqual(reader.engineMethod, .vni)
        XCTAssertFalse(reader.autoRestore)
        XCTAssertTrue(reader.autoCapitalize)
        XCTAssertTrue(reader.launchAtLoginDesired)
        XCTAssertEqual(reader.toggleHotkey.keyCode, 49)
        XCTAssertTrue(reader.toggleHotkey.control)
        XCTAssertFalse(reader.toggleHotkey.command)
        XCTAssertEqual(reader.toggleShortcutDisplay, "⌃Space")

        defaults.removePersistentDomain(forName: suite)
    }

    func testMenuHeaderSubtitleUsesSharedShortcutConstant() {
        let suite = "io.github.hapo-nghialuu.dau.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let state = AppState(defaults: defaults)
        state.engineMethod = .telex
        XCTAssertEqual(state.menuHeaderSubtitle, "Telex · \(state.toggleShortcutDisplay)")
        defaults.removePersistentDomain(forName: suite)
    }

    func testResetToggleHotkeyToDefault() {
        let suite = "io.github.hapo-nghialuu.dau.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let state = AppState(defaults: defaults)
        state.toggleHotkey = ToggleHotkey(
            keyCode: 49,
            command: false,
            control: true,
            option: false,
            shift: false
        )
        state.resetToggleHotkeyToDefault()
        XCTAssertEqual(state.toggleHotkey, .default)
        XCTAssertEqual(state.toggleShortcutDisplay, "⇧⌘E")
        defaults.removePersistentDomain(forName: suite)
    }
}
