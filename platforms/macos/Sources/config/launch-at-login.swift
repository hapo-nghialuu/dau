// Dấu macOS — Launch at Login via SMAppService (SET-06).
// Requires macOS 13+ (deployment target). Does not write TCC.

import AppKit
import Foundation
import ServiceManagement

/// Thin wrapper around `SMAppService.mainApp` for menu-bar login item.
enum LaunchAtLogin {
    /// Current registration status from the system (not a UserDefaults flag).
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Human-readable status for settings UI.
    static var statusLabel: String {
        switch SMAppService.mainApp.status {
        case .enabled:
            return "Đang bật"
        case .notRegistered:
            return "Đang tắt"
        case .notFound:
            return "Chưa có mục Login Items (cần app cài đúng bundle)"
        case .requiresApproval:
            return "Chờ duyệt trong Cài đặt hệ thống"
        @unknown default:
            return "Không xác định"
        }
    }

    /// Register or unregister the main app as a login item.
    /// - Returns: `nil` on success; localized error description on failure.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> String? {
        do {
            if enabled {
                if SMAppService.mainApp.status == .enabled {
                    return nil
                }
                try SMAppService.mainApp.register()
            } else {
                if SMAppService.mainApp.status == .notRegistered {
                    return nil
                }
                try SMAppService.mainApp.unregister()
            }
            return nil
        } catch {
            return error.localizedDescription
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
