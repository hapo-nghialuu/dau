// Dấu macOS — first-run Accessibility onboarding (ONBOARD-03).
// Explains TCC grant; does not write the TCC database.

import AppKit
import Foundation

/// First-run / setup window: welcome → grant permission → ready, or error with retry.
/// Primary copy stays Vietnamese and free of “event tap” / “inject” jargon.
final class OnboardingController: NSObject {
    /// At most three user-facing phases.
    enum Phase: Equatable {
        /// Welcome + privacy + grant CTAs (Accessibility not trusted yet).
        case needsPermission
        /// AX trusted and keyboard listener running.
        case ready
        /// AX trusted, but synthetic post-event access is missing.
        case needsPostEventPermission
        /// AX trusted but listener failed to start — actionable retry.
        case setupFailed
    }

    private let state: AppState
    private var window: NSWindow?

    private var logoView: NSImageView?
    private var titleLabel: NSTextField?
    private var bodyLabel: NSTextField?
    private var statusLabel: NSTextField?
    private var primaryButton: NSButton?
    private var secondaryButton: NSButton?

    /// Avoid stacking multiple auto-close timers when status refreshes while ready.
    private var readyCloseWorkItem: DispatchWorkItem?

    var onRequestAccessibilityPrompt: (() -> Void)?
    var onOpenSystemSettings: (() -> Void)?
    var onRetryTap: (() -> Void)?

    init(state: AppState) {
        self.state = state
        super.init()
    }

    // MARK: - Public

    func show() {
        if let window, window.isVisible {
            applyPhase(currentPhase())
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 360),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Dấu — Thiết lập"
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.minSize = NSSize(width: 420, height: 320)

        let root = buildContentView()
        panel.contentView = root
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = panel

        applyPhase(currentPhase())
    }

    func close() {
        readyCloseWorkItem?.cancel()
        readyCloseWorkItem = nil
        window?.close()
        window = nil
        logoView = nil
        titleLabel = nil
        bodyLabel = nil
        statusLabel = nil
        primaryButton = nil
        secondaryButton = nil
    }

    /// Refresh labels / CTAs after trust or listener status changes.
    func refreshStatus() {
        guard window != nil else { return }
        applyPhase(currentPhase())
    }

    func currentPhase() -> Phase {
        switch state.onboardingPhase {
        case .needsAccessibility:
            return .needsPermission
        case .needsPostEventAccess:
            return .needsPostEventPermission
        case .ready:
            return .ready
        case .setupFailed:
            return .setupFailed
        }
    }

    // MARK: - Layout

    private func buildContentView() -> NSView {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 460, height: 360))
        root.autoresizingMask = [.width, .height]

        let logo = NSImageView()
        logo.translatesAutoresizingMaskIntoConstraints = false
        logo.imageScaling = .scaleProportionallyUpOrDown
        logo.imageAlignment = .alignCenter
        if let brand = NSImage(named: "AppLogo") {
            logo.image = brand
            logo.isHidden = false
        } else if let appIcon = NSApp.applicationIconImage {
            logo.image = appIcon
            logo.isHidden = false
        } else {
            logo.isHidden = true
        }
        logo.setContentHuggingPriority(.required, for: .vertical)
        logoView = logo

        let title = makeLabel("", style: .title)
        title.identifier = NSUserInterfaceItemIdentifier("onboarding.title")
        titleLabel = title

        let body = makeLabel("", style: .body)
        body.identifier = NSUserInterfaceItemIdentifier("onboarding.body")
        bodyLabel = body

        let status = makeLabel("", style: .status)
        status.identifier = NSUserInterfaceItemIdentifier("onboarding.status")
        statusLabel = status

        let primary = NSButton(title: "", target: self, action: #selector(handlePrimary))
        primary.translatesAutoresizingMaskIntoConstraints = false
        primary.bezelStyle = .rounded
        primary.keyEquivalent = "\r"
        primary.identifier = NSUserInterfaceItemIdentifier("onboarding.primary")
        primaryButton = primary

        let secondary = NSButton(title: "", target: self, action: #selector(handleSecondary))
        secondary.translatesAutoresizingMaskIntoConstraints = false
        secondary.bezelStyle = .rounded
        secondary.identifier = NSUserInterfaceItemIdentifier("onboarding.secondary")
        secondaryButton = secondary

        let buttonRow = NSStackView(views: [secondary, primary])
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.spacing = 12
        buttonRow.distribution = .gravityAreas
        buttonRow.translatesAutoresizingMaskIntoConstraints = false
        buttonRow.setViews([secondary], in: .leading)
        buttonRow.setViews([primary], in: .trailing)

        let stack = NSStackView(views: [logo, title, body, status, buttonRow])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 24, left: 28, bottom: 24, right: 28)
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.setCustomSpacing(18, after: logo)
        stack.setCustomSpacing(8, after: title)
        stack.setCustomSpacing(16, after: body)
        stack.setCustomSpacing(20, after: status)

        root.addSubview(stack)

        let maxLabelWidth: CGFloat = 404
        title.preferredMaxLayoutWidth = maxLabelWidth
        body.preferredMaxLayoutWidth = maxLabelWidth
        status.preferredMaxLayoutWidth = maxLabelWidth

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stack.topAnchor.constraint(equalTo: root.topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor),

            logo.widthAnchor.constraint(equalToConstant: 64),
            logo.heightAnchor.constraint(equalToConstant: 64),

            buttonRow.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -56),
            primary.widthAnchor.constraint(greaterThanOrEqualToConstant: 120),
            secondary.widthAnchor.constraint(greaterThanOrEqualToConstant: 160),
        ])

        return root
    }

    private enum LabelStyle {
        case title
        case body
        case status
    }

    private func makeLabel(_ text: String, style: LabelStyle) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.translatesAutoresizingMaskIntoConstraints = false
        field.isEditable = false
        field.isSelectable = false
        field.isBordered = false
        field.drawsBackground = false
        field.maximumNumberOfLines = 0
        field.lineBreakMode = .byWordWrapping
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        switch style {
        case .title:
            field.font = .systemFont(ofSize: 17, weight: .semibold)
            field.textColor = .labelColor
        case .body:
            field.font = .systemFont(ofSize: 13)
            field.textColor = .secondaryLabelColor
        case .status:
            field.font = .systemFont(ofSize: 12, weight: .medium)
            field.textColor = .labelColor
        }
        return field
    }

    // MARK: - Phase content

    private func applyPhase(_ phase: Phase) {
        guard titleLabel != nil else { return }

        switch phase {
        case .needsPermission:
            readyCloseWorkItem?.cancel()
            readyCloseWorkItem = nil
            titleLabel?.stringValue = "Chào mừng đến với Dấu"
            bodyLabel?.stringValue =
                "Dấu cần quyền Trợ năng (Accessibility) để gõ tiếng Việt trong mọi ứng dụng. "
                + "Quyền chỉ dùng để hỗ trợ gõ trên máy bạn — Dấu không thu thập nội dung, "
                + "không gửi dữ liệu, chạy offline 100%."
            statusLabel?.stringValue = "Chưa cấp quyền. Hãy bật Dấu trong Cài đặt hệ thống."
            statusLabel?.textColor = .secondaryLabelColor
            primaryButton?.title = "Cấp quyền…"
            primaryButton?.isHidden = false
            primaryButton?.isEnabled = true
            secondaryButton?.title = "Mở Cài đặt hệ thống…"
            secondaryButton?.isHidden = false
            secondaryButton?.isEnabled = true
            window?.title = "Dấu — Cấp quyền"

        case .ready:
            titleLabel?.stringValue = "Sẵn sàng"
            bodyLabel?.stringValue =
                "Đã cấp quyền. Dấu đang chạy trên thanh menu — chọn VI và Telex hoặc VNI để bắt đầu gõ."
            statusLabel?.stringValue = "Hoàn tất thiết lập."
            statusLabel?.textColor = .systemGreen
            primaryButton?.title = "Xong"
            primaryButton?.isHidden = false
            primaryButton?.isEnabled = true
            secondaryButton?.isHidden = true
            window?.title = "Dấu — Sẵn sàng"
            scheduleReadyCloseIfNeeded()

        case .needsPostEventPermission:
            readyCloseWorkItem?.cancel()
            readyCloseWorkItem = nil
            titleLabel?.stringValue = "Cần thêm quyền để gõ"
            bodyLabel?.stringValue =
                "Dấu đã có quyền Trợ năng và đang theo dõi bàn phím, nhưng cần quyền gửi sự kiện "
                + "để thay thế chữ đang gõ. Bấm Cấp quyền để tiếp tục."
            statusLabel?.stringValue = "Thiếu quyền gửi sự kiện — chưa sẵn sàng."
            statusLabel?.textColor = .systemOrange
            primaryButton?.title = "Cấp quyền…"
            primaryButton?.isHidden = false
            primaryButton?.isEnabled = true
            secondaryButton?.title = "Mở Cài đặt hệ thống…"
            secondaryButton?.isHidden = false
            secondaryButton?.isEnabled = true
            window?.title = "Dấu — Cần quyền gửi sự kiện"

        case .setupFailed:
            readyCloseWorkItem?.cancel()
            readyCloseWorkItem = nil
            titleLabel?.stringValue = "Chưa khởi động được"
            bodyLabel?.stringValue =
                "Đã có quyền Trợ năng nhưng Dấu chưa bắt đầu theo dõi bàn phím. "
                + "Bấm Thử lại. Nếu vẫn lỗi, tắt rồi bật lại Dấu trong Cài đặt hệ thống "
                + "(Privacy & Security → Accessibility)."
            statusLabel?.stringValue = "Cần thử lại — chưa sẵn sàng."
            statusLabel?.textColor = .systemOrange
            primaryButton?.title = "Thử lại"
            primaryButton?.isHidden = false
            primaryButton?.isEnabled = true
            secondaryButton?.title = "Mở Cài đặt hệ thống…"
            secondaryButton?.isHidden = false
            secondaryButton?.isEnabled = true
            window?.title = "Dấu — Cần thử lại"
        }
    }

    private func scheduleReadyCloseIfNeeded() {
        guard readyCloseWorkItem == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.readyCloseWorkItem = nil
            // Only auto-close when still fully ready (trusted + listener running).
            guard self.currentPhase() == .ready else { return }
            self.close()
        }
        readyCloseWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: work)
    }

    // MARK: - Actions

    @objc private func handlePrimary() {
        switch currentPhase() {
        case .needsPermission:
            // Valid AX prompt path (does not write TCC DB).
            onRequestAccessibilityPrompt?()
            refreshStatus()
        case .needsPostEventPermission:
            // Reuse the existing setup path; it prompts for post-event access too.
            onRequestAccessibilityPrompt?()
            refreshStatus()
        case .ready:
            close()
        case .setupFailed:
            onRetryTap?()
            refreshStatus()
        }
    }

    @objc private func handleSecondary() {
        switch currentPhase() {
        case .needsPermission, .needsPostEventPermission, .setupFailed:
            onOpenSystemSettings?()
        case .ready:
            break
        }
    }
}
