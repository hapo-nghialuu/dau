// Dấu macOS — Settings window (SET-06 layout upgrade).
// Pattern: sidebar + content pages (inspired by common menu-bar IMEs).
// Original Dấu UI — no gonhanh source.

import AppKit
import SwiftUI

// MARK: - Navigation

enum SettingsPage: String, CaseIterable, Identifiable {
    case general
    case advanced
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "Cài đặt"
        case .advanced: return "Nâng cao"
        case .about: return "Giới thiệu"
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "gearshape"
        case .advanced: return "wrench.and.screwdriver"
        case .about: return "info.circle"
        }
    }
}

/// Coarse delay presets for Advanced UI (maps to existing `DelayPreset` values).
enum SettingsDelayPreset: Int, CaseIterable, Identifiable {
    case nhanh = 0
    case vua = 1
    case cham = 2

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .nhanh: return "Nhanh"
        case .vua: return "Vừa"
        case .cham: return "Chậm"
        }
    }

    var subtitle: String {
        switch self {
        case .nhanh: return "Terminal / app native"
        case .vua: return "Electron / render chậm"
        case .cham: return "Gõ từng ký tự (chậm hơn)"
        }
    }

    var delays: DelayPreset {
        switch self {
        case .nhanh: return .fast
        case .vua: return .slow
        case .cham: return .charByChar
        }
    }

    var injectionMethod: InjectionMethod {
        switch self {
        case .nhanh: return .backspaceFast
        case .vua: return .backspaceSlow
        case .cham: return .charByChar
        }
    }

    static func matching(delays: DelayPreset, method: InjectionMethod) -> SettingsDelayPreset? {
        for preset in allCases {
            if preset.delays == delays || preset.injectionMethod == method {
                return preset
            }
        }
        // Nearest by settleUs.
        if delays.settleUs <= DelayPreset.fast.settleUs { return .nhanh }
        if delays.settleUs <= DelayPreset.slow.settleUs { return .vua }
        return .cham
    }
}

// MARK: - View model (advanced diagnostics + profile edits)

final class SettingsViewModel: ObservableObject {
    @Published var page: SettingsPage = .general
    @Published var frontmost: AppContextSnapshot = .empty
    @Published var resolved: ResolvedInjectionSettings = ResolvedInjectionSettings(
        typingEnabled: true,
        engineMethod: .telex,
        injectionMethod: .backspaceFast,
        delays: .zero,
        source: .safeDefault
    )
    @Published var userOverrideBundleIds: [String] = []
    @Published var statusMessage: String = ""

    private let profileStore: InjectionProfileStore
    private let profileResolver: InjectionProfileResolver
    private let contextResolver: AppContextResolver
    private let appState: AppState
    /// Last non-Dấu frontmost app (settings window itself steals frontmost).
    private var lastExternalFrontmost: AppContextSnapshot?

    var onProfilesChanged: (() -> Void)?
    var onOpenAccessibilitySettings: (() -> Void)?
    var onOpenAccessibilityGuide: (() -> Void)?
    var onToggleTyping: (() -> Void)?
    var onSelectMethod: ((AppEngineMethod) -> Void)?
    var onAutoRestoreChanged: ((Bool) -> Void)?
    var onAutoCapitalizeChanged: ((Bool) -> Void)?

    init(
        appState: AppState,
        profileStore: InjectionProfileStore,
        profileResolver: InjectionProfileResolver,
        contextResolver: AppContextResolver
    ) {
        self.appState = appState
        self.profileStore = profileStore
        self.profileResolver = profileResolver
        self.contextResolver = contextResolver
        refreshDiagnostics()
    }

    var versionLabel: String { appState.versionLabel }
    var accessibilityMenuLabel: String { appState.accessibilityMenuLabel }
    var coreVersion: String {
        let v = DauCoreBridge.version
        return v.isEmpty ? "—" : v
    }

    /// Call before presenting the settings window so frontmost is not yet Dấu.
    func captureFrontmostBeforeShow() {
        contextResolver.invalidate()
        let snap = contextResolver.refresh()
        let selfId = Bundle.main.bundleIdentifier
        if let bid = snap.bundleId, bid != selfId {
            lastExternalFrontmost = snap
        }
        refreshDiagnostics()
    }

    func refreshDiagnostics() {
        contextResolver.invalidate()
        let snap = contextResolver.refresh()
        let selfId = Bundle.main.bundleIdentifier
        if let bid = snap.bundleId, bid != selfId {
            lastExternalFrontmost = snap
            frontmost = snap
        } else if let last = lastExternalFrontmost {
            // Prefer the app that was frontmost before opening Settings.
            frontmost = last
        } else {
            frontmost = snap
        }
        profileResolver.globalTypingEnabled = appState.typingEnabled
        profileResolver.globalEngineMethod = appState.engineMethod.asOverride
        resolved = profileResolver.resolve(context: frontmost)
        userOverrideBundleIds = profileStore.userOverrides.keys.sorted()
        // Force SwiftUI refresh of @Published even when values equal.
        objectWillChange.send()
    }

    func applyDelayPresetToFrontmost(_ preset: SettingsDelayPreset) {
        guard let bundleId = frontmost.bundleId, !bundleId.isEmpty else {
            statusMessage = "Không có app phía trước để lưu profile."
            return
        }
        var profile = profileStore.profile(forBundleId: bundleId)
            ?? InjectionProfile(
                bundleId: bundleId,
                enabled: true,
                engineMethod: nil,
                injectionMethod: preset.injectionMethod,
                delays: preset.delays
            )
        profile.injectionMethod = preset.injectionMethod
        profile.delays = preset.delays
        profileStore.setProfile(profile, forBundleId: bundleId)
        statusMessage = "Đã lưu profile cho \(bundleId) · \(preset.title)"
        refreshDiagnostics()
        onProfilesChanged?()
    }

    func removeUserOverride(bundleId: String) {
        profileStore.removeProfile(forBundleId: bundleId)
        statusMessage = "Đã xoá override: \(bundleId)"
        refreshDiagnostics()
        onProfilesChanged?()
    }

    func openAccessibilitySettings() {
        onOpenAccessibilitySettings?()
    }

    func openAccessibilityGuide() {
        onOpenAccessibilityGuide?()
    }
}

// MARK: - Window controller

/// Owns the settings `NSWindow` (SwiftUI content via `NSHostingView`).
final class SettingsController: NSObject, NSWindowDelegate {
    private let state: AppState
    private let model: SettingsViewModel
    private var window: NSWindow?
    private var hosting: NSHostingView<SettingsRootView>?

    var onWindowDidClose: (() -> Void)?

    /// Forwarded from `SettingsViewModel` for AppDelegate wiring convenience.
    var onToggleTyping: (() -> Void)? {
        get { model.onToggleTyping }
        set { model.onToggleTyping = newValue }
    }
    var onSelectMethod: ((AppEngineMethod) -> Void)? {
        get { model.onSelectMethod }
        set { model.onSelectMethod = newValue }
    }
    var onAutoRestoreChanged: ((Bool) -> Void)? {
        get { model.onAutoRestoreChanged }
        set { model.onAutoRestoreChanged = newValue }
    }
    var onAutoCapitalizeChanged: ((Bool) -> Void)? {
        get { model.onAutoCapitalizeChanged }
        set { model.onAutoCapitalizeChanged = newValue }
    }
    var onOpenAccessibilitySettings: (() -> Void)? {
        get { model.onOpenAccessibilitySettings }
        set { model.onOpenAccessibilitySettings = newValue }
    }
    var onOpenAccessibilityGuide: (() -> Void)? {
        get { model.onOpenAccessibilityGuide }
        set { model.onOpenAccessibilityGuide = newValue }
    }
    var onProfilesChanged: (() -> Void)? {
        get { model.onProfilesChanged }
        set { model.onProfilesChanged = newValue }
    }

    init(
        state: AppState,
        profileStore: InjectionProfileStore,
        profileResolver: InjectionProfileResolver,
        contextResolver: AppContextResolver
    ) {
        self.state = state
        self.model = SettingsViewModel(
            appState: state,
            profileStore: profileStore,
            profileResolver: profileResolver,
            contextResolver: contextResolver
        )
        super.init()
    }

    func show(page: SettingsPage = .general) {
        model.page = page
        // Capture frontmost *before* this window becomes key (otherwise we only see Dấu).
        model.captureFrontmostBeforeShow()

        if let window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        NSApp.setActivationPolicy(.regular)

        let root = SettingsRootView(state: state, model: model)
        let host = NSHostingView(rootView: root)
        host.frame = NSRect(x: 0, y: 0, width: 700, height: 480)

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        win.title = "Cài đặt Dấu"
        win.titleVisibility = .hidden
        win.titlebarAppearsTransparent = true
        win.isReleasedWhenClosed = false
        win.isMovableByWindowBackground = true
        win.minSize = NSSize(width: 640, height: 420)
        win.contentView = host
        win.delegate = self
        win.center()
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        window = win
        hosting = host
    }

    func close() {
        window?.delegate = nil
        window?.close()
        window = nil
        hosting = nil
        NSApp.setActivationPolicy(.accessory)
        onWindowDidClose?()
    }

    func refresh() {
        model.refreshDiagnostics()
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        hosting = nil
        NSApp.setActivationPolicy(.accessory)
        onWindowDidClose?()
    }
}

// MARK: - SwiftUI root

struct SettingsRootView: View {
    @ObservedObject var state: AppState
    @ObservedObject var model: SettingsViewModel

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 200)
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 640, minHeight: 420)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 8) {
                if let nsImage = NSImage(named: "AppLogo") {
                    Image(nsImage: nsImage)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 72, height: 72)
                } else {
                    Image(systemName: "character.textbox")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                        .frame(width: 72, height: 72)
                }
                Text("Dấu")
                    .font(.system(size: 18, weight: .bold))
                Text(model.versionLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 28)
            .padding(.horizontal, 12)

            Spacer(minLength: 24)

            VStack(spacing: 4) {
                ForEach(SettingsPage.allCases) { page in
                    navButton(page)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 20)
        }
        .background(sidebarBackground)
    }

    private var sidebarBackground: some View {
        VisualEffectView(material: .sidebar, blendingMode: .behindWindow)
    }

    private func navButton(_ page: SettingsPage) -> some View {
        Button {
            model.page = page
            if page == .advanced {
                model.refreshDiagnostics()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: page.systemImage)
                    .font(.system(size: 13))
                    .frame(width: 16)
                Text(page.title)
                    .font(.system(size: 13))
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(model.page == page
                          ? Color(nsColor: .controlBackgroundColor).opacity(0.85)
                          : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var content: some View {
        ScrollView {
            Group {
                switch model.page {
                case .general:
                    SettingsGeneralPage(state: state, model: model)
                case .advanced:
                    SettingsAdvancedPage(state: state, model: model)
                case .about:
                    SettingsAboutPage(model: model)
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - General page

struct SettingsGeneralPage: View {
    @ObservedObject var state: AppState
    @ObservedObject var model: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Cài đặt")
                .font(.system(size: 20, weight: .semibold))

            settingsCard(title: "Bộ gõ") {
                toggleRow(
                    title: "Bật gõ tiếng Việt",
                    subtitle: "Tắt = passthrough (EN)",
                    isOn: Binding(
                        get: { state.typingEnabled },
                        set: { _ in model.onToggleTyping?() }
                    )
                )
                Divider().padding(.leading, 12)
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Kiểu gõ")
                            .font(.system(size: 13))
                        Text("Telex hoặc VNI (toàn cục)")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker("", selection: Binding(
                        get: { state.engineMethod },
                        set: { model.onSelectMethod?($0) }
                    )) {
                        Text("Telex").tag(AppEngineMethod.telex)
                        Text("VNI").tag(AppEngineMethod.vni)
                    }
                    .labelsHidden()
                    .frame(width: 110)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }

            settingsCard(title: "Quy tắc gõ") {
                toggleRow(
                    title: "Tự khôi phục tiếng Anh",
                    subtitle: "Hoàn tác dấu khi gõ nhầm (Space / break)",
                    isOn: Binding(
                        get: { state.autoRestore },
                        set: { model.onAutoRestoreChanged?($0) }
                    )
                )
                Divider().padding(.leading, 12)
                toggleRow(
                    title: "Tự viết hoa đầu câu",
                    subtitle: "Mặc định tắt — phù hợp terminal / AI CLI",
                    isOn: Binding(
                        get: { state.autoCapitalize },
                        set: { model.onAutoCapitalizeChanged?($0) }
                    )
                )
            }

            settingsCard(title: "Hệ thống") {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Accessibility")
                            .font(.system(size: 13))
                        Text(model.accessibilityMenuLabel)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer()
                    Button("Mở Cài đặt…") {
                        model.openAccessibilitySettings()
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

                Divider().padding(.leading, 12)

                Button {
                    model.openAccessibilityGuide()
                } label: {
                    HStack {
                        Text("Hướng dẫn cấp quyền (onboarding)…")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.accentColor)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
            }

            Text("Phím tắt bật/tắt: \(AppState.toggleShortcutDisplay) · recorder sẽ có ở bản sau.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
    }

    private func toggleRow(title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

// MARK: - Advanced page

struct SettingsAdvancedPage: View {
    @ObservedObject var state: AppState
    @ObservedObject var model: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Nâng cao")
                .font(.system(size: 20, weight: .semibold))

            settingsCard(title: "Ứng dụng phía trước") {
                infoRow("Tên", model.frontmost.appName ?? "—")
                Divider().padding(.leading, 12)
                infoRow("Bundle ID", model.frontmost.bundleId ?? "—", mono: true)
                Divider().padding(.leading, 12)
                infoRow("Nguồn profile", sourceLabel(model.resolved.source))
                Divider().padding(.leading, 12)
                infoRow(
                    "Resolved",
                    "\(model.resolved.engineMethod.rawValue) · \(model.resolved.injectionMethod.rawValue) · settle \(model.resolved.delays.settleUs)µs"
                )
                Divider().padding(.leading, 12)
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Preset độ trễ")
                            .font(.system(size: 13))
                        Text("Lưu override cho app phía trước")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker(
                        "",
                        selection: Binding(
                            get: {
                                SettingsDelayPreset.matching(
                                    delays: model.resolved.delays,
                                    method: model.resolved.injectionMethod
                                ) ?? .nhanh
                            },
                            set: { model.applyDelayPresetToFrontmost($0) }
                        )
                    ) {
                        ForEach(SettingsDelayPreset.allCases) { preset in
                            Text(preset.title).tag(preset)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 120)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

                HStack {
                    Button("Làm mới") {
                        model.refreshDiagnostics()
                    }
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }

            settingsCard(title: "User overrides") {
                if model.userOverrideBundleIds.isEmpty {
                    Text("Chưa có override — chọn preset ở trên để lưu app hiện tại.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(12)
                } else {
                    ForEach(Array(model.userOverrideBundleIds.enumerated()), id: \.element) { index, bundleId in
                        if index > 0 {
                            Divider().padding(.leading, 12)
                        }
                        HStack {
                            Text(bundleId)
                                .font(.system(size: 12, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button("Xoá") {
                                model.removeUserOverride(bundleId: bundleId)
                            }
                            .controlSize(.small)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                }
            }

            if !model.statusMessage.isEmpty {
                Text(model.statusMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Text("Không expose full inject matrix (selection / axDirect / …). Chỉ 3 preset Nhanh/Vừa/Chậm.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .onAppear {
            model.refreshDiagnostics()
        }
    }

    private func sourceLabel(_ source: ProfileResolutionSource) -> String {
        switch source {
        case .userOverride: return "user override"
        case .shippedBundle: return "shipped profiles.toml"
        case .safeDefault: return "safe default"
        }
    }

    private func infoRow(_ title: String, _ value: String, mono: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 13))
                .frame(width: 100, alignment: .leading)
            Text(value)
                .font(mono ? .system(size: 12, design: .monospaced) : .system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// MARK: - About page

struct SettingsAboutPage: View {
    @ObservedObject var model: SettingsViewModel

    private let repoURL = URL(string: "https://github.com/hapo-nghialuu/dau")!

    var body: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 12)
            if let nsImage = NSImage(named: "AppLogo") {
                Image(nsImage: nsImage)
                    .resizable()
                    .frame(width: 80, height: 80)
            }
            Text("Dấu")
                .font(.system(size: 22, weight: .bold))
            Text("Bộ gõ tiếng Việt — offline, riêng tư")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Text(model.versionLabel)
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
            Text("Core: \(model.coreVersion)")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.tertiary)

            settingsCard(title: nil) {
                Text("Dấu chạy hoàn toàn trên máy bạn. Không telemetry, không thu thập phím gõ hay nội dung văn bản.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(14)
            }
            .frame(maxWidth: 420)

            Link("GitHub: hapo-nghialuu/dau", destination: repoURL)
                .font(.system(size: 13))

            Text("MIT License · © 2026 Dấu Contributors")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)

            Spacer(minLength: 12)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Shared chrome

private struct SettingsCard<Content: View>: View {
    let title: String?
    @ViewBuilder let content: Content

    init(title: String?, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
                    .padding(.bottom, 4)
            }
            content
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 0.5)
        )
    }
}

@ViewBuilder
private func settingsCard(title: String?, @ViewBuilder content: () -> some View) -> some View {
    SettingsCard(title: title, content: content)
}

/// AppKit visual effect material for sidebar frosted look.
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
