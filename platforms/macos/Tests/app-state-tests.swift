// Dấu macOS — AppState menu labels / engine mapping (WP-06).

import XCTest

final class AppStateTests: XCTestCase {
    func testMenuBarTitleVIEN() {
        let state = AppState()
        state.accessibilityTrusted = true
        state.inputSourceBlocked = false
        state.typingEnabled = true
        XCTAssertEqual(state.menuBarTitle, "VI")
        state.typingEnabled = false
        XCTAssertEqual(state.menuBarTitle, "EN")
    }

    func testMenuBarTitleNeedsAX() {
        let state = AppState()
        state.accessibilityTrusted = false
        XCTAssertEqual(state.menuBarTitle, "Dấu?")
    }

    func testMenuBarTitleBlocked() {
        let state = AppState()
        state.accessibilityTrusted = true
        state.inputSourceBlocked = true
        XCTAssertEqual(state.menuBarTitle, "—")
    }

    func testEngineMethodMapsToDauMethod() {
        XCTAssertEqual(AppEngineMethod.telex.asDauMethod, DauMethod_Telex)
        XCTAssertEqual(AppEngineMethod.vni.asDauMethod, DauMethod_Vni)
        XCTAssertEqual(AppEngineMethod.telex.asOverride, .telex)
        XCTAssertEqual(AppEngineMethod.vni.asOverride, .vni)
    }
}
