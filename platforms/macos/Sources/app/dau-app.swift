// Dấu macOS — @main product entry (WP-06).
// Replaces WP-01 stub: accessory app + AppDelegate orchestration.

import AppKit
import Foundation
import ObjectiveC

@main
enum DauApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        // NSApplication.delegate is weak — keep a strong ref for process lifetime.
        objc_setAssociatedObject(
            app,
            &AssociatedKeys.delegate,
            delegate,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

private enum AssociatedKeys {
    static var delegate: UInt8 = 0
}
