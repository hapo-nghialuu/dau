// Dấu macOS — 5-step SwiftUI onboarding (port 1:1 GoNhanh OnboardingView.swift).
// Welcome → Permission → Ready → Success → Setup(Telex/VNI). Timer 1s poll AX.

import AppKit
import ApplicationServices
import SwiftUI

// MARK: - Notification

extension Notification.Name {
    static let onboardingCompleted = Notification.Name("onboardingCompleted")
}

// MARK: - Wrapper (keeps AppDelegate callsite)

final class OnboardingController: NSObject {
    enum Phase: Equatable {
        case needsPermission
        case ready
        case setupFailed
    }

    private let state: AppState
    private var window: NSWindow?
    private var onboardingObserver: NSObjectProtocol?

    // Legacy callbacks — kept for compatibility; new SwiftUI view uses direct System Settings URL.
    var onRequestAccessibilityPrompt: (() -> Void)?
    var onOpenSystemSettings: (() -> Void)?
    var onRetryTap: (() -> Void)?

    init(state: AppState) {
        self.state = state
        super.init()
    }

    deinit {
        if let observer = onboardingObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func show() {
        if let window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let view = OnboardingView(appState: state)
        let controller = NSHostingController(rootView: view)
        let win = NSWindow(contentViewController: controller)
        win.title = "Dấu — Thiết lập"
        win.styleMask = [.titled, .closable]
        win.isReleasedWhenClosed = false
        win.level = .floating
        // SwiftUI view is 440×~370; let NSWindow fit it.
        win.setContentSize(NSSize(width: 440, height: 380))
        win.center()
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = win
        if onboardingObserver == nil {
            onboardingObserver = NotificationCenter.default.addObserver(
                forName: .onboardingCompleted, object: nil, queue: .main
            ) { [weak self] _ in
                self?.close()
            }
        }
    }

    func close() {
        if let observer = onboardingObserver {
            NotificationCenter.default.removeObserver(observer)
            onboardingObserver = nil
        }
        window?.close()
        window = nil
    }

    func refreshStatus() {
        // SwiftUI timer polls AX; nothing to do here.
    }

    func currentPhase() -> Phase {
        switch state.onboardingPhase {
        case .needsAccessibility: return .needsPermission
        case .ready: return .ready
        case .setupFailed: return .setupFailed
        }
    }

    static func contentSize(for phase: Phase) -> NSSize {
        switch phase {
        case .needsPermission: return NSSize(width: 460, height: 300)
        case .ready: return NSSize(width: 460, height: 280)
        case .setupFailed: return NSSize(width: 460, height: 380)
        }
    }
}

// MARK: - SwiftUI Onboarding

struct OnboardingView: View {
    @ObservedObject var appState: AppState
    @State private var step = 0
    @State private var hasPermission = false
    @State private var hasAutoRestarted = false
    @State private var selectedMode: AppEngineMethod = .telex

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var totalSteps: Int { step >= 10 ? 2 : 3 }
    private var stepIndex: Int { step >= 10 ? step - 10 : step }

    init(appState: AppState) {
        _appState = ObservedObject(wrappedValue: appState)
        _selectedMode = State(initialValue: appState.engineMethod)
    }

    var body: some View {
        VStack(spacing: 0) {
            content.frame(height: 320)
            Divider()
            footer
        }
        .frame(width: 440)
        .onAppear {
            selectedMode = appState.engineMethod
            hasPermission = KeyboardEventTap.isAccessibilityTrusted(prompt: false)
            if UserDefaults.standard.bool(forKey: DauSettingsKey.permissionGranted), hasPermission {
                // Already granted before and still trusted → jump to Success.
                step = 10
            } else if UserDefaults.standard.bool(forKey: DauSettingsKey.permissionGranted), !hasPermission {
                // Returning user (previously granted) but AX lost trust (e.g. after upgrade).
                // Skip Welcome and go straight to Permission step — no need to re-explain the app.
                step = 1
            }
        }
        .onReceive(timer) { _ in
            hasPermission = KeyboardEventTap.isAccessibilityTrusted(prompt: false)
            if step == 1, hasPermission { step = 2 }
        }
        .onChange(of: step) { newStep in
            // Auto-restart when reaching Ready (step 2) after granting permission — GoNhanh parity without manual click.
            if newStep == 2, !hasAutoRestarted {
                hasAutoRestarted = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                    if step == 2 {
                        restart()
                    }
                }
            }
            if newStep != 2 {
                hasAutoRestarted = false
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case 0: WelcomeStep()
        case 1: PermissionStep()
        case 2: ReadyStep()
        case 10: SuccessStep()
        case 11: SetupStep(selectedMode: $selectedMode)
        default: EmptyView()
        }
    }

    private var footer: some View {
        HStack {
            HStack(spacing: 6) {
                ForEach(0..<totalSteps, id: \.self) { i in
                    Circle()
                        .fill(i == stepIndex ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 6, height: 6)
                }
            }
            Spacer()
            if step == 1 {
                Button("Quay lại") { step = 0 }
            }
            primaryButton
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    @ViewBuilder
    private var primaryButton: some View {
        switch step {
        case 0: Button("Tiếp tục") { step = 1 }.buttonStyle(.borderedProminent)
        case 1: Button("Mở Cài đặt") { openSettings() }.buttonStyle(.borderedProminent)
        case 2: Button("Khởi động lại") { restart() }.buttonStyle(.borderedProminent)
        case 10: Button("Tiếp tục") { step = 11 }.buttonStyle(.borderedProminent)
        case 11: Button("Hoàn tất") { finish() }.buttonStyle(.borderedProminent)
        default: EmptyView()
        }
    }

    private func openSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
        ]
        for s in urls {
            if let url = URL(string: s), NSWorkspace.shared.open(url) { return }
        }
    }

    private func restart() {
        // Persist chosen method + permission flag before relaunch (mirrors GoNhanh).
        appState.engineMethod = selectedMode
        appState.permissionGranted = true
        appState.hasCompletedOnboarding = false
        let path = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 0.5; /usr/bin/open \"$1\"", "_", path]
        try? task.run()
        NSApp.terminate(nil)
    }

    private func finish() {
        appState.setMethod(selectedMode)
        appState.hasCompletedOnboarding = true
        NotificationCenter.default.post(name: .onboardingCompleted, object: nil)
        NSApp.keyWindow?.close()
    }
}

// MARK: - Steps

private struct WelcomeStep: View {
    var body: some View {
        StepLayout {
            if let img = NSImage(named: "AppLogo") {
                Image(nsImage: img)
                    .resizable()
                    .frame(width: 80, height: 80)
            } else if let icon = NSApp.applicationIconImage {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 80, height: 80)
            }
            Text("Chào mừng đến với Dấu")
                .font(.title2.bold())
            Text("Bộ gõ tiếng Việt cho macOS")
                .foregroundStyle(.secondary)
        }
    }
}

private struct PermissionStep: View {
    var body: some View {
        StepLayout {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 40))
                .foregroundStyle(.orange)
            Text("Cấp quyền Accessibility")
                .font(.title2.bold())
            Text("Bật Dấu trong System Settings để gõ tiếng Việt.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            VStack(alignment: .leading, spacing: 8) {
                Label("Mở Privacy & Security → Accessibility", systemImage: "1.circle.fill")
                Label("Bật công tắc bên cạnh Dấu", systemImage: "2.circle.fill")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.top, 4)
        }
    }
}

private struct ReadyStep: View {
    var body: some View {
        StepLayout {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 40))
                .foregroundStyle(.green)
            Text("Đã cấp quyền")
                .font(.title2.bold())
            Text("Nhấn \"Khởi động lại\" để áp dụng.")
                .foregroundStyle(.secondary)
        }
    }
}

private struct SuccessStep: View {
    var body: some View {
        StepLayout {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            Text("Sẵn sàng hoạt động")
                .font(.title2.bold())
            Text("Dấu đã được cấp quyền thành công.")
                .foregroundStyle(.secondary)
        }
    }
}

private struct SetupStep: View {
    @Binding var selectedMode: AppEngineMethod
    var body: some View {
        StepLayout {
            Image(systemName: "keyboard")
                .font(.system(size: 40))
                .foregroundStyle(.blue)
            Text("Chọn kiểu gõ")
                .font(.title2.bold())
            Text("Có thể thay đổi sau trong menu.")
                .foregroundStyle(.secondary)
            VStack(spacing: 8) {
                ForEach(AppEngineMethod.allCases, id: \.rawValue) { mode in
                    ModeOption(mode: mode, isSelected: selectedMode == mode) {
                        selectedMode = mode
                    }
                }
            }
            .frame(maxWidth: 260)
            .padding(.top, 8)
        }
    }
}

private struct ModeOption: View {
    let mode: AppEngineMethod
    let isSelected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.menuLabel).font(.headline)
                    Text(mode.description).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.4))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor.opacity(0.5) : .clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Layout helper

private struct StepLayout<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            content
            Spacer()
        }
        .padding(.horizontal, 40)
    }
}
