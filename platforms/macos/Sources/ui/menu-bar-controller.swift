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
    /// Manual update check (UPDATE-01).
    var onCheckForUpdates: (() -> Void)?
    /// Open latest release on GitHub.
    var onOpenLatestRelease: (() -> Void)?
    /// Open Homebrew update guide.
    var onOpenUpdateGuide: (() -> Void)?

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

        // Text-only badge: VI when ready+typing, EN otherwise (no status-item logo).
        button.image = nil
        button.attributedTitle = statusBadgeTitle(state.menuBarTitle)
        button.imagePosition = .noImage
        statusItem?.length = NSStatusItem.variableLength
        button.toolTip = state.menuBarToolTip
        button.setAccessibilityLabel(state.menuBarAccessibilityLabel)
        button.setAccessibilityTitle(state.menuBarAccessibilityLabel)
    }

    private func statusBadgeTitle(_ title: String) -> NSAttributedString {
        let menuBarPointSize = NSFont.menuBarFont(ofSize: 0).pointSize
        return NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.boldSystemFont(ofSize: menuBarPointSize),
                .foregroundColor: NSColor.dauBrandOrange,
            ]
        )
    }

    // MARK: - Menu

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        // Header: logo + "Dấu" + method/shortcut + ON/OFF switch (GoNhanh layout).
        let header = NSMenuItem()
        header.view = MenuHeaderView(
            subtitle: state.menuHeaderSubtitle,
            typingEnabled: state.typingEnabled,
            target: self,
            toggleAction: #selector(handleToggleTyping)
        )
        menu.addItem(header)
        menu.addItem(.separator())

        let telex = NSMenuItem(title: "Telex", action: #selector(handleTelex), keyEquivalent: "")
        telex.target = self
        telex.state = state.engineMethod == .telex ? .on : .off
        menu.addItem(telex)

        let vni = NSMenuItem(title: "VNI", action: #selector(handleVNI), keyEquivalent: "")
        vni.target = self
        vni.state = state.engineMethod == .vni ? .on : .off
        menu.addItem(vni)

        menu.addItem(.separator())

        let settings = NSMenuItem(title: "Cài đặt…", action: #selector(handleSettings), keyEquivalent: ",")
        settings.keyEquivalentModifierMask = [.command]
        settings.target = self
        menu.addItem(settings)

        let about = NSMenuItem(title: "Giới thiệu", action: #selector(handleAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)

        // UPDATE-01: single dynamic row — title changes when update is available.
        let updateTitle = state.updateAvailable
            ? (state.updateNotice ?? "Có bản mới — xem trên GitHub")
            : "Kiểm tra bản cập nhật…"
        let updateAction = state.updateAvailable
            ? #selector(handleOpenLatestRelease)
            : #selector(handleCheckForUpdates)
        let check = NSMenuItem(title: updateTitle, action: updateAction, keyEquivalent: "")
        check.target = self
        menu.addItem(check)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Thoát Dấu", action: #selector(handleQuit), keyEquivalent: "q")
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
        }        // Fallback: standard About panel.
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
    @objc private func handleCheckForUpdates() { onCheckForUpdates?() }
    @objc private func handleOpenLatestRelease() { onOpenLatestRelease?() }
    @objc private func handleOpenUpdateGuide() { onOpenUpdateGuide?() }
}

// MARK: - Header view (logo + title + method + switch)

/// Custom menu header: logo + app name + method/shortcut subtitle + VI/EN switch.
private final class MenuHeaderView: NSView {
    private let logoView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "Dấu")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let toggle = BrandSwitchButton()

    init(
        subtitle: String,
        typingEnabled: Bool,
        target: AnyObject?,
        toggleAction: Selector
    ) {
        super.init(frame: NSRect(x: 0, y: 0, width: 320, height: 44))

        wantsLayer = true

        // Logo (AppLogo brand color).
        if let logo = NSImage(named: "AppLogo") {
            logo.isTemplate = false
            logo.size = NSSize(width: 32, height: 32)
            logoView.image = logo
        } else if let fallback = NSImage(named: "MenuBarActive") {
            fallback.isTemplate = false
            fallback.size = NSSize(width: 32, height: 32)
            logoView.image = fallback
        }
        logoView.imageScaling = .scaleProportionallyUpOrDown

        titleLabel.stringValue = "Dấu"
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.isBezeled = false
        titleLabel.drawsBackground = false
        titleLabel.isEditable = false
        titleLabel.isSelectable = false
        titleLabel.lineBreakMode = .byTruncatingTail

        subtitleLabel.stringValue = subtitle
        subtitleLabel.font = .systemFont(ofSize: 11, weight: .regular)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.isBezeled = false
        subtitleLabel.drawsBackground = false
        subtitleLabel.isEditable = false
        subtitleLabel.isSelectable = false
        subtitleLabel.lineBreakMode = .byTruncatingTail

        toggle.state = typingEnabled ? .on : .off
        toggle.target = target
        toggle.action = toggleAction
        toggle.setAccessibilityLabel("Bật hoặc tắt gõ tiếng Việt")

        for subview in [logoView, titleLabel, subtitleLabel, toggle] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            addSubview(subview)
        }
        NSLayoutConstraint.activate([
            logoView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            logoView.centerYAnchor.constraint(equalTo: centerYAnchor),
            logoView.widthAnchor.constraint(equalToConstant: 32),
            logoView.heightAnchor.constraint(equalToConstant: 32),

            // Title on top, subtitle below — mirrors GoNhanh layout.
            titleLabel.leadingAnchor.constraint(equalTo: logoView.trailingAnchor, constant: 8),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 5),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: toggle.leadingAnchor, constant: -8),

            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 1),
            subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: toggle.leadingAnchor, constant: -8),

            toggle.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            toggle.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private final class BrandSwitchButton: NSButton {
    override var intrinsicContentSize: NSSize {
        NSSize(width: 38, height: 22)
    }

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 38, height: 22))
        setButtonType(.toggle)
        title = ""
        isBordered = false
        isTransparent = false
        focusRingType = .none
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var state: NSControl.StateValue {
        didSet { needsDisplay = true }
    }

    override var isHighlighted: Bool {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        let isOn = state == .on
        let trackRect = bounds.insetBy(dx: 1, dy: 2)
        let trackColor: NSColor = isOn ? .dauBrandOrange : .dauSwitchOffTrack
        trackColor.withAlphaComponent(isHighlighted ? 0.82 : 1.0).setFill()
        NSBezierPath(roundedRect: trackRect, xRadius: trackRect.height / 2, yRadius: trackRect.height / 2).fill()

        let knobSize = trackRect.height - 4
        let knobX = isOn ? trackRect.maxX - knobSize - 2 : trackRect.minX + 2
        let knobRect = NSRect(x: knobX, y: trackRect.minY + 2, width: knobSize, height: knobSize)
        NSColor.white.setFill()
        NSBezierPath(ovalIn: knobRect).fill()
    }
}

extension NSColor {
    static let dauBrandOrange = NSColor(
        calibratedRed: 232.0 / 255.0,
        green: 83.0 / 255.0,
        blue: 30.0 / 255.0,
        alpha: 1.0
    )

    static let dauSwitchOffTrack = NSColor(
        calibratedRed: 0.42,
        green: 0.44,
        blue: 0.46,
        alpha: 1.0
    )
}
