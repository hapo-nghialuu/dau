// Dấu macOS — published app settings / runtime status (WP-06 / MENU-02).
// UI (menu bar / onboarding) observes this; does not own the event-tap callback.

import Combine
import Foundation

/// Global engine method as stored in UI (maps to `DauMethod` / `EngineMethodOverride`).
enum AppEngineMethod: String, Codable, CaseIterable, Sendable, Equatable {
    case telex
    case vni

    var asOverride: EngineMethodOverride {
        switch self {
        case .telex: return .telex
        case .vni: return .vni
        }
    }

    var asDauMethod: DauMethod {
        switch self {
        case .telex: return DauMethod_Telex
        case .vni: return DauMethod_Vni
        }
    }

    var menuLabel: String {
        switch self {
        case .telex: return "Telex"
        case .vni: return "VNI"
        }
    }
}

/// Semantic status-item visual state (MENU-02). Maps to template images in Assets.xcassets.
enum MenuBarIconState: String, Sendable, Equatable, CaseIterable {
    /// Accessibility chưa trust, hoặc event tap không chạy — không nhìn như VI active.
    case setup
    /// Đang gõ tiếng Việt (VI), trusted + tap running + không bị block.
    case active
    /// EN / input source blocked / không inject — không nhìn như VI active.
    case inactive

    /// Asset catalog imageset name (`MenuBarSetup` / `MenuBarActive` / `MenuBarInactive`).
    var assetName: String {
        switch self {
        case .setup: return "MenuBarSetup"
        case .active: return "MenuBarActive"
        case .inactive: return "MenuBarInactive"
        }
    }
}

/// Shared observable state for menu bar + onboarding. Thread: main queue for mutations.
final class AppState: ObservableObject {
    /// VI = true (typing on), EN = false (passthrough). Toggle clears compose via AppDelegate.
    @Published var typingEnabled: Bool = true

    /// Global Telex / VNI (per-app override can still change engine method at resolve time).
    @Published var engineMethod: AppEngineMethod = .telex

    /// TCC Accessibility trust (not an entitlement).
    @Published var accessibilityTrusted: Bool = false

    /// Last known event-tap status for menu diagnostics.
    @Published var eventTapRunning: Bool = false

    /// When true, current input source is non-Latin / foreign Vietnamese IME — do not inject.
    @Published var inputSourceBlocked: Bool = false

    /// Human-readable status line for menu (no key/text content).
    @Published var statusDetail: String = ""

    /// Bundle version string for About.
    var versionLabel: String {
        let marketing = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let core = DauCoreBridge.version
        if core.isEmpty {
            return "Dấu \(marketing)"
        }
        return "Dấu \(marketing) · core \(core)"
    }

    /// Short badge on the status item next to the logo.
    /// - Ready + VI typing: **VI**
    /// - Ready + EN / blocked: **EN**
    /// - Not ready (no Accessibility or tap down): empty (logo only)
    var menuBarTitle: String {
        switch menuBarIconState {
        case .setup:
            return ""
        case .active:
            return "VI"
        case .inactive:
            return "EN"
        }
    }

    /// Icon state: setup before active VI; blocked/tap-failed never map to `.active`.
    var menuBarIconState: MenuBarIconState {
        // Setup incomplete: no AX trust, or tap not running after trust.
        if !accessibilityTrusted || !eventTapRunning {
            return .setup
        }
        // Trusted + tap up, but must not look like active VI when blocked or EN.
        if inputSourceBlocked || !typingEnabled {
            return .inactive
        }
        return .active
    }

    /// Hover / accessibility description (Vietnamese).
    var menuBarToolTip: String {
        switch menuBarIconState {
        case .setup:
            if !accessibilityTrusted {
                return "Dấu — cần cấp quyền Accessibility"
            }
            return "Dấu — event tap chưa chạy"
        case .active:
            return "Dấu — VI (đang gõ tiếng Việt)"
        case .inactive:
            if inputSourceBlocked {
                return "Dấu — EN (tạm tắt theo input source)"
            }
            return "Dấu — EN (tắt gõ tiếng Việt)"
        }
    }

    /// VoiceOver / accessibility label for the status item button.
    var menuBarAccessibilityLabel: String {
        switch menuBarIconState {
        case .setup:
            return "Dấu — chưa sẵn sàng"
        case .active:
            return "Dấu — VI"
        case .inactive:
            if inputSourceBlocked {
                return "Dấu — EN, tạm tắt"
            }
            return "Dấu — EN"
        }
    }

    /// Menu row for Accessibility diagnostic.
    /// Trusted + listener running = "đã cấp quyền · đang gõ" (not merely "đã cấp").
    var accessibilityMenuLabel: String {
        if accessibilityTrusted && eventTapRunning {
            return "Accessibility: đã cấp quyền · đang gõ"
        }
        if accessibilityTrusted && !eventTapRunning {
            return "Accessibility: đã cấp — đang khởi động…"
        }
        return "Accessibility: chưa cấp quyền…"
    }

    /// Header subtitle: current method + optional toggle shortcut hint.
    var menuHeaderSubtitle: String {
        "\(engineMethod.menuLabel) · ⌘⇧E"
    }

    /// True when user has granted Accessibility and the keyboard listener is up.
    var isReadyToType: Bool {
        accessibilityTrusted && eventTapRunning
    }
}
