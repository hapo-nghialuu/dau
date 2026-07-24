// Dấu macOS — published app settings / runtime status (WP-06 / MENU-02 / SET-06).
// UI (menu bar / onboarding / settings) observes this; does not own the event-tap callback.

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

/// UserDefaults keys for SET-06 persisted preferences.
enum DauSettingsKey {
    static let typingEnabled = "dau.settings.typingEnabled"
    static let engineMethod = "dau.settings.engineMethod"
    static let autoRestore = "dau.settings.autoRestore"
    static let autoCapitalize = "dau.settings.autoCapitalize"
    /// Last user intent for launch-at-login (actual status still from SMAppService).
    static let launchAtLoginDesired = "dau.settings.launchAtLoginDesired"
    /// JSON-encoded `ToggleHotkey` for global VI/EN shortcut.
    static let toggleHotkey = "dau.settings.toggleHotkey"
}

/// Shared observable state for menu bar + onboarding + settings. Thread: main queue for mutations.
final class AppState: ObservableObject {
    private let defaults: UserDefaults
    private var suppressPersist = false

    /// VI = true (typing on), EN = false (passthrough). Toggle clears compose via AppDelegate.
    @Published var typingEnabled: Bool {
        didSet { persistBool(typingEnabled, key: DauSettingsKey.typingEnabled) }
    }

    /// Global Telex / VNI (per-app override can still change engine method at resolve time).
    @Published var engineMethod: AppEngineMethod {
        didSet { persistString(engineMethod.rawValue, key: DauSettingsKey.engineMethod) }
    }

    /// English auto-restore on word break (core `dau_set_auto_restore`).
    @Published var autoRestore: Bool {
        didSet { persistBool(autoRestore, key: DauSettingsKey.autoRestore) }
    }

    /// Auto-capitalize after sentence end (core `dau_set_auto_capitalize`). Default off.
    @Published var autoCapitalize: Bool {
        didSet { persistBool(autoCapitalize, key: DauSettingsKey.autoCapitalize) }
    }

    /// Last desired launch-at-login from settings UI (not SMAppService truth).
    @Published var launchAtLoginDesired: Bool {
        didSet { persistBool(launchAtLoginDesired, key: DauSettingsKey.launchAtLoginDesired) }
    }

    /// Global VI/EN toggle hotkey (Carbon RegisterEventHotKey; default ⇧⌘E).
    @Published var toggleHotkey: ToggleHotkey {
        didSet { persistToggleHotkey(toggleHotkey) }
    }

    /// True while settings UI is capturing a new hotkey (unregister global hotkey).
    @Published var isRecordingToggleHotkey: Bool = false

    /// TCC Accessibility trust (not an entitlement).
    @Published var accessibilityTrusted: Bool = false

    /// Last known event-tap status for menu diagnostics.
    @Published var eventTapRunning: Bool = false

    /// When true, current input source is non-Latin / foreign Vietnamese IME — do not inject.
    @Published var inputSourceBlocked: Bool = false

    /// Human-readable status line for menu (no key/text content).
    @Published var statusDetail: String = ""

    /// Default display string (tests / fallback). Live UI uses `toggleShortcutDisplay`.
    static let defaultToggleShortcutDisplay = ToggleHotkey.default.displayString

    /// Current hotkey display for menu header / settings.
    var toggleShortcutDisplay: String { toggleHotkey.displayString }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        suppressPersist = true
        typingEnabled = Self.loadBool(defaults, key: DauSettingsKey.typingEnabled, default: true)
        if let raw = defaults.string(forKey: DauSettingsKey.engineMethod),
           let method = AppEngineMethod(rawValue: raw) {
            engineMethod = method
        } else {
            engineMethod = .telex
        }
        autoRestore = Self.loadBool(defaults, key: DauSettingsKey.autoRestore, default: true)
        autoCapitalize = Self.loadBool(defaults, key: DauSettingsKey.autoCapitalize, default: false)
        launchAtLoginDesired = Self.loadBool(
            defaults,
            key: DauSettingsKey.launchAtLoginDesired,
            default: false
        )
        toggleHotkey = Self.loadToggleHotkey(defaults)
        suppressPersist = false
    }

    /// Bundle version string for About.
    var versionLabel: String {
        let marketing = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let core = DauCoreBridge.version
        if core.isEmpty {
            return "Dấu \(marketing)"
        }
        return "Dấu \(marketing) · core \(core)"
    }

    /// Status-item title only (no logo image).
    /// - Ready + VI: **VI**
    /// - Ready + EN / blocked / setup incomplete: **EN**
    var menuBarTitle: String {
        menuBarIconState == .active ? "VI" : "EN"
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

    /// Hover / accessibility description (Vietnamese) — includes toggle shortcut.
    var menuBarToolTip: String {
        let sc = toggleShortcutDisplay
        switch menuBarIconState {
        case .setup:
            if !accessibilityTrusted {
                return "Dấu — cần cấp quyền Accessibility · bật/tắt \(sc)"
            }
            return "Dấu — event tap chưa chạy · bật/tắt \(sc)"
        case .active:
            return "Dấu — VI (đang gõ tiếng Việt) · bật/tắt \(sc)"
        case .inactive:
            if inputSourceBlocked {
                return "Dấu — EN (tạm tắt theo input source) · bật/tắt \(sc)"
            }
            return "Dấu — EN (tắt gõ tiếng Việt) · bật/tắt \(sc)"
        }
    }

    /// VoiceOver / accessibility label for the status item button.
    var menuBarAccessibilityLabel: String {
        let sc = toggleShortcutDisplay
        switch menuBarIconState {
        case .setup:
            return "Dấu — chưa sẵn sàng · bật/tắt \(sc)"
        case .active:
            return "Dấu — VI · bật/tắt \(sc)"
        case .inactive:
            if inputSourceBlocked {
                return "Dấu — EN, tạm tắt · bật/tắt \(sc)"
            }
            return "Dấu — EN · bật/tắt \(sc)"
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

    /// Header subtitle: current method + toggle shortcut hint.
    var menuHeaderSubtitle: String {
        "\(engineMethod.menuLabel) · \(toggleShortcutDisplay)"
    }

    /// Reset toggle hotkey to product default (⇧⌘E).
    func resetToggleHotkeyToDefault() {
        toggleHotkey = .default
    }

    /// True when user has granted Accessibility and the keyboard listener is up.
    var isReadyToType: Bool {
        accessibilityTrusted && eventTapRunning
    }

    // MARK: - Persistence helpers

    private static func loadBool(_ defaults: UserDefaults, key: String, default def: Bool) -> Bool {
        if defaults.object(forKey: key) == nil {
            return def
        }
        return defaults.bool(forKey: key)
    }

    private func persistBool(_ value: Bool, key: String) {
        guard !suppressPersist else { return }
        defaults.set(value, forKey: key)
    }

    private func persistString(_ value: String, key: String) {
        guard !suppressPersist else { return }
        defaults.set(value, forKey: key)
    }

    private static func loadToggleHotkey(_ defaults: UserDefaults) -> ToggleHotkey {
        guard let data = defaults.data(forKey: DauSettingsKey.toggleHotkey) else {
            return .default
        }
        guard let decoded = try? JSONDecoder().decode(ToggleHotkey.self, from: data),
              decoded.isValid else {
            return .default
        }
        return decoded
    }

    private func persistToggleHotkey(_ value: ToggleHotkey) {
        guard !suppressPersist else { return }
        guard value.isValid else { return }
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: DauSettingsKey.toggleHotkey)
        }
    }
}
