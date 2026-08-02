// Dấu macOS — Codable per-app injection profile models (WP-05).
// Bridge-owned. Reuses InjectionMethod + DelayPreset from output/injection-method.swift.

import Foundation

// MARK: - Engine method override

/// Optional per-app override of the engine input method (Telex / VNI).
/// `nil` on a profile means inherit the global method (AppState / core).
enum EngineMethodOverride: String, Codable, CaseIterable, Sendable, Equatable {
    case telex
    case vni
}

// MARK: - Coarse AX role (optional context)

/// Coarse AX role category used when a role layer is present.
/// MVP AppContext may leave this as `.other` / nil path.
enum AXRoleCategory: String, Codable, CaseIterable, Sendable, Equatable {
    case terminal
    case editor
    case textField
    /// Secure / password field — never compose or inject (hard passthrough EN).
    case secure
    case comboBox
    case addressBar
    case other
}

// MARK: - Profile

/// Per-app (or default) injection profile.
///
/// - `bundleId`: target bundle identifier when stored as an app override / shipped app row.
/// - `enabled`: when false, bridge should treat the app as passthrough.
/// - `engineMethod`: optional Telex/VNI override; nil = inherit global.
/// - `injectionMethod` / `delays`: reuse WP-03 types (no duplicate enums).
struct InjectionProfile: Codable, Equatable, Sendable {
    var bundleId: String?
    var enabled: Bool
    var engineMethod: EngineMethodOverride?
    var injectionMethod: InjectionMethod
    var delays: DelayPreset

    init(
        bundleId: String? = nil,
        enabled: Bool = true,
        engineMethod: EngineMethodOverride? = nil,
        injectionMethod: InjectionMethod = .backspaceFast,
        delays: DelayPreset = .zero
    ) {
        self.bundleId = bundleId
        self.enabled = enabled
        self.engineMethod = engineMethod
        self.injectionMethod = injectionMethod
        self.delays = delays
    }

    /// MVP safe default: backspaceFast with zero delays (plan WP-05 brief).
    static let mvpDefault = InjectionProfile(
        bundleId: nil,
        enabled: true,
        engineMethod: nil,
        injectionMethod: .backspaceFast,
        delays: .zero
    )

    /// Method actually used for delivery (declared-only stubs → explicit implemented fallback).
    var deliveryMethod: InjectionMethod {
        injectionMethod.deliveryImplementation
    }

    /// Profile with stub methods rewritten to an implemented delivery path.
    /// Logs once when rewriting (metadata only — no typed content).
    func sanitizedForDelivery(logFallback: Bool = true) -> InjectionProfile {
        let delivered = deliveryMethod
        guard delivered != injectionMethod else { return self }
        if logFallback {
            let bundle = bundleId ?? "-"
            fputs(
                "[dau] profile method fallback: bundle=\(bundle) " +
                    "requested=\(injectionMethod.rawValue) → delivered=\(delivered.rawValue)\n",
                stderr
            )
        }
        var copy = self
        copy.injectionMethod = delivered
        return copy
    }
}

// MARK: - Resolution result

/// Where the final settings came from (diagnostics / tests; no PII beyond bundle id).
enum ProfileResolutionSource: String, Sendable, Equatable {
    case userOverride
    case shippedBundle
    /// Role-based fallback for apps with no user / shipped bundle profile.
    case roleFallback
    /// Secure / password field — hard passthrough (never compose or inject).
    case securePassthrough
    case safeDefault
}

/// Fully resolved injection settings for the current frontmost context.
struct ResolvedInjectionSettings: Equatable, Sendable {
    /// Whether the bridge should process keys (false → passthrough).
    var typingEnabled: Bool
    /// Concrete engine method after applying optional override + global fallback.
    var engineMethod: EngineMethodOverride
    var injectionMethod: InjectionMethod
    var delays: DelayPreset
    var source: ProfileResolutionSource

    /// Effective injector method when typing is off.
    var effectiveInjectionMethod: InjectionMethod {
        typingEnabled ? injectionMethod : .passthrough
    }

    /// Delivery method after stub fallback (never a declared-only stub).
    var deliveryMethod: InjectionMethod {
        effectiveInjectionMethod.deliveryImplementation
    }

    /// Settings safe for `TypingSession.applyRuntimeSettings` (stubs rewritten).
    func sanitizedForDelivery(logFallback: Bool = true) -> ResolvedInjectionSettings {
        let requested = injectionMethod
        let delivered = requested.deliveryImplementation
        guard delivered != requested else { return self }
        if logFallback {
            fputs(
                "[dau] resolve method fallback: source=\(source.rawValue) " +
                    "requested=\(requested.rawValue) → delivered=\(delivered.rawValue)\n",
                stderr
            )
        }
        var copy = self
        copy.injectionMethod = delivered
        return copy
    }
}

// MARK: - App context snapshot

/// Cached frontmost-app / AX context for the hot path (P2.3).
struct AppContextSnapshot: Equatable, Sendable {
    var bundleId: String?
    var appName: String?
    /// Optional AX role; MVP may leave `.other` when AX is unavailable / stubbed.
    var role: AXRoleCategory?
    /// Generation token; increments on each invalidate/refresh for cache tests.
    var generation: UInt64

    static let empty = AppContextSnapshot(
        bundleId: nil,
        appName: nil,
        role: nil,
        generation: 0
    )
}
