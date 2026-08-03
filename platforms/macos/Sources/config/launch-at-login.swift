// Dấu macOS — Launch at Login via SMAppService (SET-06).
// Requires macOS 13+ (deployment target). Does not write TCC.

import AppKit
import Foundation
import ServiceManagement

/// Mirrored login-item status for AppState (UI). Derived from `SMAppService`,
/// never a UserDefaults guess. `launchAtLoginDesired` keeps the user's last intent.
enum LaunchAtLoginState: Equatable, Sendable {
    case disabled
    case enabled
    case notFound
    case requiresApproval
    case error(String)

    var isEnabled: Bool { self == .enabled }
}

/// Pure login-item kind independent of `SMAppService.Status` (unit-testable).
enum LaunchAtLoginKind: Equatable, Sendable {
    case enabled
    case notRegistered
    case notFound
    case requiresApproval
    case unknown
}

/// Pure mappings `SMAppService.Status` → kind → state/label (unit-testable).
enum LaunchAtLoginStatusMapper {
    static func kind(from status: SMAppService.Status) -> LaunchAtLoginKind {
        switch status {
        case .enabled: return .enabled
        case .notRegistered: return .notRegistered
        case .notFound: return .notFound
        case .requiresApproval: return .requiresApproval
        @unknown default: return .unknown
        }
    }

    static func state(kind: LaunchAtLoginKind) -> LaunchAtLoginState {
        switch kind {
        case .enabled: return .enabled
        case .notRegistered: return .disabled
        case .notFound: return .notFound
        case .requiresApproval: return .requiresApproval
        case .unknown: return .error("Không xác định")
        }
    }

    static func label(kind: LaunchAtLoginKind) -> String {
        switch kind {
        case .enabled: return "Đang bật"
        case .notRegistered: return "Đang tắt"
        case .notFound: return "Chưa có mục Login Items (cần app cài đúng bundle)"
        case .requiresApproval: return "Chờ duyệt trong Cài đặt hệ thống"
        case .unknown: return "Không xác định"
        }
    }
}

/// Thin wrapper around `SMAppService.mainApp` for menu-bar login item.
enum LaunchAtLogin {
    /// Current registration status from the system (not a UserDefaults flag).
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Current mirrored UI state.
    static var currentState: LaunchAtLoginState {
        LaunchAtLoginStatusMapper.state(kind: LaunchAtLoginStatusMapper.kind(from: SMAppService.mainApp.status))
    }

    /// Human-readable status for settings UI (from the real SMAppService status).
    static var statusLabel: String {
        LaunchAtLoginStatusMapper.label(kind: LaunchAtLoginStatusMapper.kind(from: SMAppService.mainApp.status))
    }

    /// Register or unregister the main app as a login item.
    /// - Returns: `.success(mirroredState)` on success; `.failure(Error)` on error.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Result<LaunchAtLoginState, Error> {
        do {
            if enabled {
                if SMAppService.mainApp.status == .enabled {
                    return .success(.enabled)
                }
                try SMAppService.mainApp.register()
            } else {
                if SMAppService.mainApp.status == .notRegistered {
                    return .success(.disabled)
                }
                try SMAppService.mainApp.unregister()
            }
            return .success(currentState)
        } catch {
            return .failure(error)
        }
    }

    /// Open System Settings → Login Items (recovery when register needs approval).
    static func openLoginItemsSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.LoginItems-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.general?LoginItems",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension",
        ]
        for s in candidates {
            if let url = URL(string: s), NSWorkspace.shared.open(url) {
                return
            }
        }
    }
}
