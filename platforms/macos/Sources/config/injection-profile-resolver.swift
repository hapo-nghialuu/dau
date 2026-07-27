// Dấu macOS — resolve enabled / method / delay with fixed precedence (WP-05).
// Precedence: user app override > shipped bundle id > default.

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

    init(store: InjectionProfileStore) {
        self.store = store
    }

    /// Resolve from an app-context snapshot (uses `bundleId` only for MVP precedence).
    func resolve(context: AppContextSnapshot) -> ResolvedInjectionSettings {
        resolve(bundleId: context.bundleId)
    }

    /// Resolve for an explicit bundle identifier (nil → default only).
    func resolve(bundleId: String?) -> ResolvedInjectionSettings {
        if let bundleId,
           let user = store.profile(forBundleId: bundleId) {
            return materialize(user, source: .userOverride)
        }
        if let bundleId,
           let shipped = store.shippedByBundle[bundleId] {
            return materialize(shipped, source: .shippedBundle)
        }
        return materialize(store.shippedDefault, source: .safeDefault)
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
