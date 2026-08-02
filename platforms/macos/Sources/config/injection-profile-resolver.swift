// Dấu macOS — resolve enabled / method / delay with fixed precedence (WP-05).
// Precedence: user app override > shipped bundle id > AX role fallback > safe default.

import Foundation

/// Resolves `ResolvedInjectionSettings` for a bundle id / `AppContextSnapshot`.
///
/// Pure merge over store tables — no CGEvent, core, or AX work.
final class InjectionProfileResolver {
    /// Global typing master switch (VI = true, EN = false). WP-06 owns UI toggle.
    var globalTypingEnabled: Bool = true

    /// Default engine method when profile has no override.
    var globalEngineMethod: EngineMethodOverride = .telex

    private let store: InjectionProfileStore

    /// Role → delivered method for apps with no user/shipped bundle profile.
    /// Chosen to minimize lost/duplicated characters per control class. The
    /// shipped default / user override still win when present.
    static let roleMethods: [AXRoleCategory: InjectionMethod] = [
        .terminal: .backspaceFast,
        .editor: .charByChar,
        .textField: .backspaceFast,
        .comboBox: .selection,
        .addressBar: .emptyCharPrefix,
        .other: .backspaceFast,
    ]

    /// Browser AX focus can be inconclusive for web content/editors, especially
    /// contenteditable surfaces. In that case avoid terminal-style bulk rewrite.
    private static let browserBundleIds: Set<String> = [
        "com.apple.Safari",
        "com.apple.SafariTechnologyPreview",
        "com.brave.Browser",
        "com.google.Chrome",
        "com.google.Chrome.beta",
        "com.google.Chrome.canary",
        "com.google.Chrome.dev",
        "com.microsoft.edgemac",
        "com.microsoft.edgemac.Beta",
        "com.microsoft.edgemac.Canary",
        "com.microsoft.edgemac.Dev",
        "org.chromium.Chromium",
        "org.mozilla.firefox",
        "org.mozilla.firefoxdeveloperedition",
        "company.thebrowser.Browser",
    ]

    init(store: InjectionProfileStore) {
        self.store = store
    }

    /// Resolve from an app-context snapshot.
    ///
    /// Precedence (documented in plan §2.5):
    /// 1. User per-app override (`profile(forBundleId:)`).
    /// 2. Shipped `[[apps]]` bundle row.
    /// 3. Role fallback (`context.role`) when both are absent.
    /// 4. Shipped `[default]` / MVP safe default.
    func resolve(context: AppContextSnapshot) -> ResolvedInjectionSettings {
        if let bundleId = context.bundleId {
            if let user = store.profile(forBundleId: bundleId) {
                return materialize(user, source: .userOverride)
            }
            if let shipped = store.shippedByBundle[bundleId] {
                return materialize(shipped, source: .shippedBundle)
            }
        }
        if let role = context.role,
           let method = Self.roleMethods[role] {
            let profile = InjectionProfile(
                bundleId: context.bundleId,
                enabled: true,
                engineMethod: nil,
                injectionMethod: method,
                delays: .zero
            )
            return materialize(profile, source: .roleFallback)
        }
        if let bundleId = context.bundleId,
           Self.browserBundleIds.contains(bundleId) {
            let profile = InjectionProfile(
                bundleId: bundleId,
                enabled: true,
                engineMethod: nil,
                injectionMethod: .charByChar,
                delays: .zero
            )
            return materialize(profile, source: .roleFallback)
        }
        return materialize(store.shippedDefault, source: .safeDefault)
    }

    /// Resolve for an explicit bundle identifier (nil → default only).
    func resolve(bundleId: String?) -> ResolvedInjectionSettings {
        resolve(context: AppContextSnapshot(
            bundleId: bundleId,
            appName: nil,
            role: nil,
            generation: 0
        ))
    }

    // MARK: - Materialize

    private func materialize(
        _ profile: InjectionProfile,
        source: ProfileResolutionSource
    ) -> ResolvedInjectionSettings {
        let engine = profile.engineMethod ?? globalEngineMethod
        let typingEnabled = globalTypingEnabled && profile.enabled
            && profile.injectionMethod != .passthrough

        return ResolvedInjectionSettings(
            typingEnabled: typingEnabled,
            engineMethod: engine,
            injectionMethod: profile.injectionMethod,
            delays: profile.delays,
            source: source
        )
    }
}
