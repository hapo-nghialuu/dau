// Dấu macOS — published app settings / runtime status (WP-06).
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

    /// Menu bar title: VI / EN (and optional blocked marker).
    var menuBarTitle: String {
        if !accessibilityTrusted {
            return "Dấu?"
        }
        if inputSourceBlocked {
            return "—"
        }
        return typingEnabled ? "VI" : "EN"
    }
}
