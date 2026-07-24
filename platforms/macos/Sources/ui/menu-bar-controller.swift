// Dấu macOS — status item menu: icon states, VI/EN, Telex/VNI, AX, About, quit (MENU-02).

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
            refresh()
            return
        }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem = item
        applyButtonAppearance()
        rebuildMenu()

        // Rebuild icon/menu when AppState publishes changes (main thread).
        stateObserver = NotificationCenter.default.addObserver(
            forName: nil,
            object: state,
            queue: .main
        ) { [weak self] _ in
            self?.refresh()
        }
        // Combine-less fallback: AppDelegate calls refresh() after mutations.
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

    /// Update icon + accessibility + menu contents from current state.
    func refresh() {
        applyButtonAppearance()
        rebuildMenu()
    }

    // MARK: - Status button

    private func applyButtonAppearance() {
        guard let button = statusItem?.button else { return }

        button.title = ""
        button.imagePosition = .imageOnly
        button.image = Self.statusItemImage(named: state.menuBarIconState.assetName)
        button.toolTip = state.menuBarToolTip
        button.setAccessibilityLabel(state.menuBarAccessibilityLabel)
        button.setAccessibilityTitle(state.menuBarAccessibilityLabel)
    }

    /// Load catalog brand image in **original** colors (red logo), not template mono.
    /// User request: menubar matches AppIcon / Linux brand (full color).
    static func statusItemImage(named name: String) -> NSImage? {
        guard let image = NSImage(named: name) else {
            return nil
        }
        image.isTemplate = false
        // Keep status-item scale ~18 pt; color logo stays legible on light/dark bars.
        let side: CGFloat = 18
        image.size = NSSize(width: side, height: side)
        return image
    }

    // MARK: - Menu

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

        let about = NSMenuItem(
            title: "Giới thiệu Dấu",
            action: #selector(handleAbout),
            keyEquivalent: ""
        )
        about.target = self
        menu.addItem(about)

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

    @objc private func handleAbout() {
        var options: [NSApplication.AboutPanelOptionKey: Any] = [:]
        options[.applicationName] = "Dấu"
        if let marketing = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            options[.version] = marketing
        }
        if let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
            options[.applicationVersion] = build
        }
        // Prefer app icon from catalog / bundle; fall back to AppLogo.
        if let icon = NSApp.applicationIconImage {
            options[.applicationIcon] = icon
        } else if let logo = NSImage(named: "AppLogo") {
            options[.applicationIcon] = logo
        }
        let copyright = Bundle.main.infoDictionary?["NSHumanReadableCopyright"] as? String
            ?? "Copyright © 2026 Dấu Contributors. MIT License."
        options[.credits] = NSAttributedString(string: copyright)
        NSApp.orderFrontStandardAboutPanel(options: options)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func handleQuit() { onQuit?() }
}
