// Dấu macOS — status item menu: VI/EN, Telex/VNI, AX status, quit (WP-06).

import AppKit
import Foundation

/// Owns `NSStatusItem` and rebuilds the menu from `AppState`.
final class MenuBarController: NSObject {
    private let state: AppState
    private var statusItem: NSStatusItem?

    var onToggleTyping: (() -> Void)?
    var onSelectTelex: (() -> Void)?
    var onSelectVNI: (() -> Void)?
    var onOpenAccessibilitySettings: (() -> Void)?
    var onRestartTap: (() -> Void)?
    var onShowOnboarding: (() -> Void)?
    var onQuit: (() -> Void)?

    private var stateObserver: NSObjectProtocol?

    init(state: AppState) {
        self.state = state
        super.init()
    }

    deinit {
        stop()
    }

    func start() {
        guard statusItem == nil else {
            rebuildMenu()
            return
        }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        if let button = item.button {
            button.title = state.menuBarTitle
            button.toolTip = "Dấu — bộ gõ tiếng Việt"
        }
        rebuildMenu()

        // Rebuild title/menu when AppState publishes changes (main thread).
        stateObserver = NotificationCenter.default.addObserver(
            forName: nil,
            object: state,
            queue: .main
        ) { [weak self] _ in
            self?.refresh()
        }
        // Combine-less fallback: poll lightly via a timer is overkill; AppDelegate calls refresh().
    }

    func stop() {
        if let stateObserver {
            NotificationCenter.default.removeObserver(stateObserver)
            self.stateObserver = nil
        }
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
    }

    /// Update title + menu contents from current state.
    func refresh() {
        statusItem?.button?.title = state.menuBarTitle
        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let header = NSMenuItem(
            title: state.versionLabel,
            action: nil,
            keyEquivalent: ""
        )
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        let toggleTitle = state.typingEnabled ? "Chế độ: VI (bật)" : "Chế độ: EN (tắt)"
        let toggle = NSMenuItem(
            title: toggleTitle,
            action: #selector(handleToggleTyping),
            keyEquivalent: "e"
        )
        toggle.keyEquivalentModifierMask = [.command, .shift]
        toggle.target = self
        toggle.state = state.typingEnabled ? .on : .off
        menu.addItem(toggle)

        let telex = NSMenuItem(
            title: "Telex",
            action: #selector(handleTelex),
            keyEquivalent: ""
        )
        telex.target = self
        telex.state = state.engineMethod == .telex ? .on : .off
        menu.addItem(telex)

        let vni = NSMenuItem(
            title: "VNI",
            action: #selector(handleVNI),
            keyEquivalent: ""
        )
        vni.target = self
        vni.state = state.engineMethod == .vni ? .on : .off
        menu.addItem(vni)

        menu.addItem(.separator())

        let axTitle: String
        if state.accessibilityTrusted {
            axTitle = state.eventTapRunning
                ? "Accessibility: OK · tap running"
                : "Accessibility: OK · tap stopped"
        } else {
            axTitle = "Accessibility: chưa cấp quyền…"
        }
        let axItem = NSMenuItem(
            title: axTitle,
            action: #selector(handleAccessibility),
            keyEquivalent: ""
        )
        axItem.target = self
        menu.addItem(axItem)

        if state.inputSourceBlocked {
            let blocked = NSMenuItem(
                title: "Input source: tạm tắt (IME/non-Latin)",
                action: nil,
                keyEquivalent: ""
            )
            blocked.isEnabled = false
            menu.addItem(blocked)
        }

        if !state.statusDetail.isEmpty {
            let detail = NSMenuItem(
                title: state.statusDetail,
                action: nil,
                keyEquivalent: ""
            )
            detail.isEnabled = false
            menu.addItem(detail)
        }

        let restart = NSMenuItem(
            title: "Khởi động lại event tap",
            action: #selector(handleRestartTap),
            keyEquivalent: ""
        )
        restart.target = self
        menu.addItem(restart)

        if !state.accessibilityTrusted {
            let onboard = NSMenuItem(
                title: "Hướng dẫn cấp quyền…",
                action: #selector(handleOnboarding),
                keyEquivalent: ""
            )
            onboard.target = self
            menu.addItem(onboard)
        }

        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: "Thoát Dấu",
            action: #selector(handleQuit),
            keyEquivalent: "q"
        )
        quit.target = self
        menu.addItem(quit)

        statusItem?.menu = menu
    }

    // MARK: - Actions

    @objc private func handleToggleTyping() { onToggleTyping?() }
    @objc private func handleTelex() { onSelectTelex?() }
    @objc private func handleVNI() { onSelectVNI?() }
    @objc private func handleAccessibility() { onOpenAccessibilitySettings?() }
    @objc private func handleRestartTap() { onRestartTap?() }
    @objc private func handleOnboarding() { onShowOnboarding?() }
    @objc private func handleQuit() { onQuit?() }
}
