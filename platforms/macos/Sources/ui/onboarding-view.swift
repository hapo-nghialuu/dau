// Dấu macOS — Accessibility onboarding window (WP-06 / P2.1).
// Explains TCC grant; does not write the TCC database.

import AppKit
import Foundation

/// Small utility window: trust status, open System Settings, retry tap.
final class OnboardingController: NSObject {
    private let state: AppState
    private var window: NSWindow?

    var onRequestAccessibilityPrompt: (() -> Void)?
    var onOpenSystemSettings: (() -> Void)?
    var onRetryTap: (() -> Void)?

    init(state: AppState) {
        self.state = state
        super.init()
    }

    func show() {
        if let window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 280),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Dấu — Cấp quyền Accessibility"
        panel.isReleasedWhenClosed = false
        panel.level = .floating

        let content = NSView(frame: panel.contentView?.bounds ?? .zero)
        content.autoresizingMask = [.width, .height]

        let title = makeLabel(
            "Dấu cần quyền Accessibility để bắt phím system-wide và inject text.",
            frame: NSRect(x: 20, y: 200, width: 400, height: 48),
            bold: true
        )
        content.addSubview(title)

        let body = makeLabel(
            "Quyền này chỉ dùng để đọc role/focus khi cần và thay text đang gõ. "
                + "Dấu không thu thập nội dung, không telemetry, chạy offline.",
            frame: NSRect(x: 20, y: 130, width: 400, height: 64),
            bold: false
        )
        content.addSubview(body)

        let status = makeLabel(
            statusText(),
            frame: NSRect(x: 20, y: 90, width: 400, height: 28),
            bold: false
        )
        status.identifier = NSUserInterfaceItemIdentifier("onboarding.status")
        content.addSubview(status)

        let openBtn = NSButton(
            frame: NSRect(x: 20, y: 40, width: 200, height: 32)
        )
        openBtn.title = "Mở System Settings…"
        openBtn.bezelStyle = .rounded
        openBtn.target = self
        openBtn.action = #selector(handleOpenSettings)
        content.addSubview(openBtn)

        let promptBtn = NSButton(
            frame: NSRect(x: 230, y: 40, width: 90, height: 32)
        )
        promptBtn.title = "Prompt"
        promptBtn.bezelStyle = .rounded
        promptBtn.target = self
        promptBtn.action = #selector(handlePrompt)
        content.addSubview(promptBtn)

        let retryBtn = NSButton(
            frame: NSRect(x: 330, y: 40, width: 90, height: 32)
        )
        retryBtn.title = "Thử lại"
        retryBtn.bezelStyle = .rounded
        retryBtn.target = self
        retryBtn.action = #selector(handleRetry)
        content.addSubview(retryBtn)

        panel.contentView = content
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = panel
    }

    func close() {
        window?.close()
        window = nil
    }

    /// Refresh status label after trust / tap change.
    func refreshStatus() {
        guard let content = window?.contentView else { return }
        for view in content.subviews {
            if view.identifier?.rawValue == "onboarding.status", let label = view as? NSTextField {
                label.stringValue = statusText()
            }
        }
    }

    private func statusText() -> String {
        if state.accessibilityTrusted {
            return state.eventTapRunning
                ? "Trạng thái: đã cấp quyền · event tap đang chạy."
                : "Trạng thái: đã cấp quyền · event tap chưa chạy (bấm Thử lại)."
        }
        return "Trạng thái: chưa thấy quyền Accessibility."
    }

    private func makeLabel(_ text: String, frame: NSRect, bold: Bool) -> NSTextField {
        let field = NSTextField(frame: frame)
        field.stringValue = text
        field.isEditable = false
        field.isBordered = false
        field.drawsBackground = false
        field.font = bold
            ? .systemFont(ofSize: 13, weight: .semibold)
            : .systemFont(ofSize: 12)
        field.textColor = .labelColor
        field.maximumNumberOfLines = 0
        field.lineBreakMode = .byWordWrapping
        return field
    }

    @objc private func handleOpenSettings() { onOpenSystemSettings?() }
    @objc private func handlePrompt() { onRequestAccessibilityPrompt?() }
    @objc private func handleRetry() { onRetryTap?() }
}
