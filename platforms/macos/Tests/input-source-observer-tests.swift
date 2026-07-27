// Dấu macOS — InputSourceObserver classification unit tests (WP-06).

import XCTest

final class InputSourceObserverTests: XCTestCase {
    func testAllowsCommonLatinKeylayouts() {
        let latin = [
            "com.apple.keylayout.ABC",
            "com.apple.keylayout.US",
            "com.apple.keylayout.British",
            "com.apple.keylayout.French",
            "com.apple.keylayout.German",
            "com.apple.keylayout.Spanish",
            "com.apple.keylayout.ABC-AZERTY",
        ]
        for id in latin {
            XCTAssertFalse(
                InputSourceObserver.shouldBlock(sourceID: id),
                "should allow \(id)"
            )
        }
    }

    func testBlocksUnicodeHexAndCJK() {
        XCTAssertTrue(InputSourceObserver.shouldBlock(sourceID: "com.apple.keylayout.UnicodeHexInput"))
        XCTAssertTrue(InputSourceObserver.shouldBlock(sourceID: "com.apple.keylayout.Japanese"))
        XCTAssertTrue(InputSourceObserver.shouldBlock(sourceID: "com.apple.inputmethod.SCIM.ITABC"))
        XCTAssertTrue(InputSourceObserver.shouldBlock(sourceID: "com.apple.keylayout.Russian"))
        XCTAssertTrue(InputSourceObserver.shouldBlock(sourceID: "com.apple.keylayout.Korean"))
    }

    func testBlocksVietnameseIMEMarkers() {
        XCTAssertTrue(InputSourceObserver.shouldBlock(sourceID: "com.example.VietnameseTelex"))
        XCTAssertTrue(InputSourceObserver.shouldBlock(sourceID: "org.example.unikey"))
        XCTAssertTrue(InputSourceObserver.shouldBlock(sourceID: "com.apple.inputmethod.VietnameseIM"))
    }

    func testNilSourceFailsOpen() {
        XCTAssertFalse(InputSourceObserver.shouldBlock(sourceID: nil))
        XCTAssertFalse(InputSourceObserver.shouldBlock(sourceID: ""))
    }
}
