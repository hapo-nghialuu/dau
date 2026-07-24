// Dấu macOS — status item + popup menu (MENU-02 / Gõ-Nhanh-style layout, original code).
// Header: brand logo + name + method subtitle + VI/EN switch. No gonhanh source.

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
    /// Opens settings window (SET-06). Not onboarding.
    var onShowSettings: (() -> Void)?
    /// Opens settings on Giới thiệu page.
    var onShowAbout: (() -> Void)?
    /// Optional first-run guide (kept for recovery; not the main Cài đặt entry).
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

        // Logo always; show VI/EN text only when ready to type (user request).
        let title = state.menuBarTitle
        button.image = Self.statusItemImage(named: state.menuBarIconState.assetName)
        button.title = title
        if title.isEmpty {
            button.imagePosition = .imageOnly
            statusItem?.length = NSStatusItem.squareLength
        } else {
            button.imagePosition = .imageLeading
            statusItem?.length = NSStatusItem.variableLength
        }
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

        // Header: logo + "Dấu" + method/shortcut + ON/OFF switch (Gõ Nhanh layout pattern).
        let header = NSMenuItem()
        header.view = MenuHeaderView(
            subtitle: state.menuHeaderSubtitle,
            typingEnabled: state.typingEnabled,
            target: self,
            toggleAction: #selector(handleToggleTyping)
        )
        menu.addItem(header)

        // Keyboard toggle (⌘⇧E) — works even though primary UI is the header switch.
        let toggleHotkey = NSMenuItem(
            title: "Bật/Tắt tiếng Việt",
            action: #selector(handleToggleTyping),
            keyEquivalent: "e"
        )
        toggleHotkey.keyEquivalentModifierMask = [.command, .shift]
        toggleHotkey.target = self
        toggleHotkey.isHidden = true
        menu.addItem(toggleHotkey)

        menu.addItem(.separator())

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

        let axItem = NSMenuItem(
            title: state.accessibilityMenuLabel,
            action: #selector(handleAccessibility),
            keyEquivalent: ""
        )
        axItem.target = self
        menu.addItem(axItem)

        if state.inputSourceBlocked {
            let blocked = NSMenuItem(
                title: "Tạm tắt theo nguồn bàn phím (IME)",
                action: nil,
                keyEquivalent: ""
            )
            blocked.isEnabled = false
            menu.addItem(blocked)
        }

        let restart = NSMenuItem(
            title: "Khởi động lại bộ gõ",
            action: #selector(handleRestartTap),
            keyEquivalent: ""
        )
        restart.target = self
        menu.addItem(restart)

        // SET-06: real settings window (not onboarding).
        let settings = NSMenuItem(
            title: "Cài đặt…",
            action: #selector(handleSettings),
            keyEquivalent: ","
        )
        settings.keyEquivalentModifierMask = [.command]
        settings.target = self
        menu.addItem(settings)

        // Keep recovery path for Accessibility guide when setup is incomplete.
        if !state.isReadyToType {
            let setup = NSMenuItem(
                title: "Thiết lập quyền…",
                action: #selector(handleOnboarding),
                keyEquivalent: ""
            )
            setup.target = self
            menu.addItem(setup)
        }

        menu.addItem(.separator())

        let about = NSMenuItem(
            title: "Giới thiệu",
            action: #selector(handleAbout),
            keyEquivalent: ""
        )
        about.target = self
        menu.addItem(about)

        // YAGNI: no update checker. Greyed placeholder kept out of menu.

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
    @objc private func handleSettings() { onShowSettings?() }
    @objc private func handleOnboarding() { onShowOnboarding?() }

    @objc private func handleAbout() {
        if let onShowAbout {
            onShowAbout()
            return
        }
        // Fallback: standard About panel.
        var options: [NSApplication.AboutPanelOptionKey: Any] = [:]
        options[.applicationName] = "Dấu"
        if let marketing = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            options[.version] = marketing
        }
        if let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
            options[.applicationVersion] = build
        }
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

// MARK: - Header view (logo + title + method + switch)

/// Custom menu header: logo + app name + method/shortcut subtitle + VI/EN switch.
private final class MenuHeaderView: NSView {
    private let logoView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "Dấu")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let toggle = NSSwitch()

    init(
        subtitle: String,
        typingEnabled: Bool,
        target: AnyObject?,
        toggleAction: Selector
    ) {
        super.init(frame: NSRect(x: 0, y: 0, width: 280, height: 56))

        wantsLayer = true

        // Logo (AppLogo brand color).
        if let logo = NSImage(named: "AppLogo") {
            logo.isTemplate = false
            logo.size = NSSize(width: 28, height: 28)
            logoView.image = logo
        } else if let fallback = NSImage(named: "MenuBarActive") {
            fallback.isTemplate = false
            fallback.size = NSSize(width: 28, height: 28)
            logoView.image = fallback
        }
        logoView.imageScaling = .scaleProportionallyUpOrDown
        logoView.frame = NSRect(x: 14, y: 14, width: 28, height: 28)
        addSubview(logoView)

        titleLabel.stringValue = "Dấu"
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.isBezeled = false
        titleLabel.drawsBackground = false
        titleLabel.isEditable = false
        titleLabel.isSelectable = false
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.frame = NSRect(x: 50, y: 28, width: 160, height: 18)
        addSubview(titleLabel)

        subtitleLabel.stringValue = subtitle
        subtitleLabel.font = .systemFont(ofSize: 11, weight: .regular)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.isBezeled = false
        subtitleLabel.drawsBackground = false
        subtitleLabel.isEditable = false
        subtitleLabel.isSelectable = false
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.frame = NSRect(x: 50, y: 10, width: 160, height: 16)
        addSubview(subtitleLabel)

        toggle.controlSize = .small
        toggle.state = typingEnabled ? .on : .off
        toggle.target = target
        toggle.action = toggleAction
        toggle.setAccessibilityLabel("Bật hoặc tắt gõ tiếng Việt")
        // Right-align switch.
        toggle.sizeToFit()
        let switchSize = toggle.fittingSize
        toggle.frame = NSRect(
            x: bounds.width - switchSize.width - 14,
            y: (bounds.height - switchSize.height) / 2,
            width: switchSize.width,
            height: switchSize.height
        )
        toggle.autoresizingMask = [.minXMargin]
        addSubview(toggle)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
