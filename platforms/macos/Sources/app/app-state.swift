// Dấu macOS — published app settings / runtime status (WP-06 / MENU-02 / SET-06).
// UI (menu bar / onboarding / settings) observes this; does not own the event-tap callback.

import Combine
import Foundation

enum LaunchPermissionRecoveryPolicy {
    static func shouldRequestAccessibility(accessibilityTrusted: Bool) -> Bool {
        !accessibilityTrusted
    }
}

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

/// Canonical onboarding readiness phase shared with the menu-bar app UI.
enum AppOnboardingPhase: Equatable {
    case needsAccessibility
    case ready
    case setupFailed
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

    /// Real login-item status mirrored from `SMAppService` (not a UserDefaults flag).
    /// AppDelegate refreshes this at launch and after every toggle.
    @Published var launchAtLoginState: LaunchAtLoginState = .disabled

    /// Update-check state (UPDATE-01). Mirrored by AppDelegate; never blocks typing path.
    @Published var releaseCheckState: ReleaseCheckState = .none
    /// Latest release info when an update is available (for menu actions).
    @Published var releaseInfo: DauReleaseInfo?

    /// True when a newer release is known.
    var updateAvailable: Bool {
        if case .updateAvailable = releaseCheckState { return true }
        return false
    }

    /// Menu notice for the compact update row.
    var updateNotice: String? {
        switch releaseCheckState {
        case .updateAvailable(let version): return "Có bản mới \(version) — xem trên GitHub"
        case .upToDate: return "Đã có bản mới nhất"
        case .checking: return "Đang kiểm tra bản cập nhật…"
        case .none, .failed: return nil
        }
    }

    /// Human-readable status label for the Settings System card.
    var launchAtLoginStatusLabel: String {
        switch launchAtLoginState {
        case .error(let message): return message
        default: return LaunchAtLoginStatusMapper.label(
            kind: Self.kind(for: launchAtLoginState)
        )
        }
    }

    /// Apply the real login-item status from AppDelegate (main thread).
    func applyLaunchAtLoginState(_ state: LaunchAtLoginState) {
        launchAtLoginState = state
    }

    /// Pure `LaunchAtLoginState` → kind (for label; `.error` handled by caller).
    private static func kind(for state: LaunchAtLoginState) -> LaunchAtLoginKind {
        switch state {
        case .disabled: return .notRegistered
        case .enabled: return .enabled
        case .notFound: return .notFound
        case .requiresApproval: return .requiresApproval
        case .error: return .unknown
        }
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
    /// Must always reflect real tap status (including failed watchdog restart / degraded stop).
    @Published var eventTapRunning: Bool = false

    /// True when tap was intentionally left down (fail-open) after recovery failure.
    @Published var eventTapDegraded: Bool = false

    /// Current event-tap generation for diagnostics/telemetry (0 = never started).
    @Published var eventTapGeneration: UInt64 = 0

    /// When true, current input source is non-Latin / foreign Vietnamese IME — do not inject.
    @Published var inputSourceBlocked: Bool = false

    /// Human-readable status line for menu (no key/text content).
    @Published var statusDetail: String = ""

    /// Last sleep/wake transition label for metadata telemetry (never key content).
    @Published var lastLifecycleTransition: String = ""

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
    /// Never show **VI** while setup incomplete (would claim typing works when it does not).
    var menuBarTitle: String {
        menuBarIconState == .active ? "VI" : "EN"
    }

    /// Icon state: setup before active VI; blocked/tap-failed never map to `.active`.
    var menuBarIconState: MenuBarIconState {
        // Setup incomplete: Accessibility or event tap is not ready.
        if !accessibilityTrusted || !eventTapRunning {
            return .setup
        }
        // Trusted + tap up, but must not look like active VI when blocked or EN.
        if inputSourceBlocked || !typingEnabled {
            return .inactive
        }
        return .active
    }

    /// User VI/EN intent for UI when the app is not ready to type yet.
    /// Distinct from `menuBarTitle` which must not show VI until inject actually works.
    private var typingIntentLabel: String {
        typingEnabled ? "ý định VI" : "ý định EN"
    }

    /// Hover / accessibility description (Vietnamese) — includes toggle shortcut.
    /// When setup is incomplete, surface VI/EN **intent** so ⌘⇧ toggle is not invisible,
    /// without claiming the app can inject (badge stays EN / not `.active`).
    var menuBarToolTip: String {
        let sc = toggleShortcutDisplay
        switch menuBarIconState {
        case .setup:
            if !accessibilityTrusted {
                return "Dấu — chưa sẵn sàng (\(typingIntentLabel)) · cần cấp quyền Accessibility · bật/tắt \(sc)"
            }
            if !eventTapRunning {
                return "Dấu — chưa sẵn sàng (\(typingIntentLabel)) · event tap chưa chạy · bật/tắt \(sc)"
            }
            return "Dấu — chưa sẵn sàng (\(typingIntentLabel)) · event tap chưa sẵn sàng · bật/tắt \(sc)"
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
            if !accessibilityTrusted {
                return "Dấu — chưa sẵn sàng · \(typingIntentLabel) · cần cấp quyền Accessibility · bật/tắt \(sc)"
            }
            if !eventTapRunning {
                return "Dấu — chưa sẵn sàng · \(typingIntentLabel) · event tap chưa chạy · bật/tắt \(sc)"
            }
            return "Dấu — chưa sẵn sàng · \(typingIntentLabel) · bật/tắt \(sc)"
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
        if !accessibilityTrusted {
            return "Accessibility: chưa cấp quyền…"
        }
        if !eventTapRunning {
            return "Accessibility: đã cấp — đang khởi động…"
        }
        if accessibilityTrusted && eventTapRunning {
            return "Accessibility: đã cấp quyền · đang gõ"
        }
        return "Accessibility: chưa sẵn sàng…"
    }

    /// Header subtitle: current method + toggle shortcut hint.
    /// When not ready, append VI/EN **intent** so the menu reflects ⌘⇧ without a false VI badge.
    var menuHeaderSubtitle: String {
        let base = "\(engineMethod.menuLabel) · \(toggleShortcutDisplay)"
        guard !isReadyToType else { return base }
        return "\(base) · \(typingIntentLabel)"
    }

    /// Reset toggle hotkey to product default (⇧⌘E).
    func resetToggleHotkeyToDefault() {
        toggleHotkey = .default
    }

    /// True when Accessibility and the keyboard listener are ready.
    var isReadyToType: Bool {
        accessibilityTrusted && eventTapRunning && !eventTapDegraded
    }

    /// Readiness phase used by onboarding without querying OS permissions.
    var onboardingPhase: AppOnboardingPhase {
        guard accessibilityTrusted else { return .needsAccessibility }
        return eventTapRunning ? .ready : .setupFailed
    }

    /// Apply live tap mirror fields from `KeyboardEventTap` (main-thread UI).
    func applyEventTapMirror(running: Bool, degraded: Bool, generation: UInt64, detail: String?) {
        eventTapRunning = running
        eventTapDegraded = degraded
        eventTapGeneration = generation
        if let detail {
            statusDetail = detail
        }
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

// MARK: - TG-00 pure lifecycle engines (unit-testable without NSApp)

/// Decision from one AX poll tick. No `AXIsProcessTrusted` call inside — caller supplies snapshot.
struct AccessibilityPollDecision: Equatable, Sendable {
    /// Stop the poll timer (trusted + tap healthy).
    var stopPolling: Bool
    /// Start/restart the event tap without prompting.
    var attemptStartTap: Bool
    /// Tear down tap (trust lost).
    var stopTap: Bool
    /// Refresh onboarding/status UI.
    var refreshUI: Bool
}

/// Pure AX poll policy: stop when trusted && tap healthy; never call AX from the keyboard callback.
enum AccessibilityPollEngine {
    static func evaluate(
        trusted: Bool,
        wasTrusted: Bool,
        tapRunning: Bool,
        tapDegraded: Bool
    ) -> AccessibilityPollDecision {
        // Healthy: trusted + running + not degraded → stop infinite main-loop AX polling.
        if trusted && tapRunning && !tapDegraded {
            return AccessibilityPollDecision(
                stopPolling: true,
                attemptStartTap: false,
                stopTap: false,
                refreshUI: true
            )
        }
        if trusted != wasTrusted {
            if trusted {
                return AccessibilityPollDecision(
                    stopPolling: false,
                    attemptStartTap: true,
                    stopTap: false,
                    refreshUI: true
                )
            }
            return AccessibilityPollDecision(
                stopPolling: false,
                attemptStartTap: false,
                stopTap: true,
                refreshUI: true
            )
        }
        if trusted && !tapRunning {
            // Permission ok but listener not running — recover without prompt spam.
            return AccessibilityPollDecision(
                stopPolling: false,
                attemptStartTap: true,
                stopTap: false,
                refreshUI: true
            )
        }
        // Still untrusted or degraded: keep polling at bounded cadence.
        return AccessibilityPollDecision(
            stopPolling: false,
            attemptStartTap: false,
            stopTap: false,
            refreshUI: false
        )
    }
}

/// Sleep / wake / session lifecycle policy (workspace notifications).
enum SleepWakePhase: String, Equatable, Sendable {
    case willSleep
    case didWake
    case sessionResign
    case sessionActive
}

struct SleepWakeDecision: Equatable, Sendable {
    var stopAndReset: Bool
    var recreateOnce: Bool
    /// Never true for automatic wake recovery — prompts only from setup UI.
    var promptPermission: Bool
    var transitionLabel: String
}

/// Pure sleep/wake coordinator: stop before sleep; re-check trust + recreate once after wake.
/// No automatic permission prompt on wake.
struct SleepWakeLifecycleEngine: Equatable, Sendable {
    private(set) var isAsleep: Bool = false
    private(set) var wakeRecreateCount: Int = 0
    /// Debounce: at most one recreate per wake edge until next sleep.
    private(set) var pendingWakeRecreate: Bool = false

    mutating func handle(_ phase: SleepWakePhase, accessibilityTrusted: Bool) -> SleepWakeDecision {
        switch phase {
        case .willSleep, .sessionResign:
            isAsleep = true
            pendingWakeRecreate = false
            return SleepWakeDecision(
                stopAndReset: true,
                recreateOnce: false,
                promptPermission: false,
                transitionLabel: phase.rawValue
            )
        case .didWake, .sessionActive:
            let wasAsleep = isAsleep
            isAsleep = false
            // Only recreate once per sleep→wake edge.
            let shouldRecreate = wasAsleep && accessibilityTrusted && !pendingWakeRecreate
            if shouldRecreate {
                pendingWakeRecreate = true
                wakeRecreateCount += 1
            }
            return SleepWakeDecision(
                stopAndReset: false,
                recreateOnce: shouldRecreate,
                promptPermission: false,
                transitionLabel: phase.rawValue
            )
        }
    }

    mutating func resetForTests() {
        isAsleep = false
        wakeRecreateCount = 0
        pendingWakeRecreate = false
    }
}
