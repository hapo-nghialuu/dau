// Dấu macOS — InjectionProfile / store / resolver unit tests (WP-05).

import Foundation
import XCTest

final class InjectionProfileTests: XCTestCase {

    // MARK: - Codable / defaults

    func testMVPDefaultIsBackspaceFastWithZeroDelays() {
        let d = InjectionProfile.mvpDefault
        XCTAssertTrue(d.enabled)
        XCTAssertNil(d.engineMethod)
        XCTAssertEqual(d.injectionMethod, .backspaceFast)
        XCTAssertEqual(d.delays, .zero)
        XCTAssertNil(d.bundleId)
        XCTAssertEqual(d.deliveryMethod, .backspaceFast)
    }

    // MARK: - TG-05 delivery fallback

    func testStubMethodsRequireDeliveryFallback() {
        // Only syncProxy remains a declared-only stub; selection/emptyCharPrefix are real now.
        XCTAssertTrue(InjectionMethod.syncProxy.requiresDeliveryFallback)
        XCTAssertFalse(InjectionMethod.selection.requiresDeliveryFallback)
        XCTAssertFalse(InjectionMethod.emptyCharPrefix.requiresDeliveryFallback)
        XCTAssertFalse(InjectionMethod.backspaceFast.requiresDeliveryFallback)
        XCTAssertFalse(InjectionMethod.backspaceSlow.requiresDeliveryFallback)
        XCTAssertFalse(InjectionMethod.charByChar.requiresDeliveryFallback)
        XCTAssertFalse(InjectionMethod.axDirect.requiresDeliveryFallback)
        XCTAssertFalse(InjectionMethod.passthrough.requiresDeliveryFallback)
    }

    func testProfileSanitizedForDeliveryKeepsImplementedMethods() {
        let raw = InjectionProfile(
            bundleId: "com.example.App",
            enabled: true,
            injectionMethod: .selection,
            delays: .fast
        )
        XCTAssertEqual(raw.injectionMethod, .selection)
        let clean = raw.sanitizedForDelivery(logFallback: false)
        XCTAssertEqual(clean.injectionMethod, .selection)
        XCTAssertEqual(clean.delays, .fast)
        XCTAssertEqual(clean.bundleId, "com.example.App")

        let rawPrefix = InjectionProfile(
            bundleId: "com.example.App",
            enabled: true,
            injectionMethod: .emptyCharPrefix,
            delays: .fast
        )
        let cleanPrefix = rawPrefix.sanitizedForDelivery(logFallback: false)
        XCTAssertEqual(cleanPrefix.injectionMethod, .emptyCharPrefix)
    }

    func testResolvedSettingsSanitizedKeepsEmptyCharPrefix() {
        let resolved = ResolvedInjectionSettings(
            typingEnabled: true,
            engineMethod: .telex,
            injectionMethod: .emptyCharPrefix,
            delays: .zero,
            source: .userOverride
        )
        XCTAssertEqual(resolved.injectionMethod, .emptyCharPrefix)
        XCTAssertEqual(resolved.deliveryMethod, .emptyCharPrefix)
        let clean = resolved.sanitizedForDelivery(logFallback: false)
        XCTAssertEqual(clean.injectionMethod, .emptyCharPrefix)
        XCTAssertEqual(clean.source, .userOverride)
    }

    func testShippedProfilesOnlyUseImplementedMethods() {
        // Load real shipped profiles.toml content via file if present; else sample.
        let url = Bundle.main.url(forResource: "profiles", withExtension: "toml")
        let raw: String
        if let url, let contents = try? String(contentsOf: url, encoding: .utf8) {
            raw = contents
        } else {
            // Fallback: parse the repo-shipped sample shape used by store tests.
            raw = """
            [default]
            injection_method = "backspaceFast"
            [[apps]]
            bundle_id = "com.apple.Terminal"
            injection_method = "backspaceSlow"
            """
        }
        let parsed = ShippedProfilesTOML.parse(raw)
        XCTAssertTrue(
            parsed.defaultProfile.injectionMethod.isMVPImplemented,
            "default must not be a declared-only stub"
        )
        for (bundle, profile) in parsed.apps {
            XCTAssertTrue(
                profile.injectionMethod.isMVPImplemented,
                "shipped \(bundle) uses unimplemented method \(profile.injectionMethod.rawValue)"
            )
            XCTAssertEqual(
                profile.deliveryMethod,
                profile.injectionMethod,
                "shipped \(bundle) should not need fallback rewrite"
            )
        }
    }

    func testProfileCodableRoundTrip() throws {
        let original = InjectionProfile(
            bundleId: "com.apple.Terminal",
            enabled: false,
            engineMethod: .vni,
            injectionMethod: .backspaceSlow,
            delays: DelayPreset(backspaceUs: 10, settleUs: 20, textUs: 30)
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(InjectionProfile.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testUserOverridesDictionaryCodable() throws {
        let map: [String: InjectionProfile] = [
            "com.example.A": InjectionProfile(
                bundleId: "com.example.A",
                enabled: true,
                engineMethod: .telex,
                injectionMethod: .charByChar,
                delays: .charByChar
            ),
        ]
        let data = try JSONEncoder().encode(map)
        let decoded = try JSONDecoder().decode([String: InjectionProfile].self, from: data)
        XCTAssertEqual(decoded, map)
    }

    // MARK: - TOML parse

    func testShippedTOMLParsesDefaultAndApps() {
        let toml = """
        [default]
        enabled = true
        injection_method = "backspaceFast"
        backspace_us = 0
        settle_us = 0
        text_us = 0

        [[apps]]
        bundle_id = "com.apple.Terminal"
        enabled = true
        injection_method = "backspaceSlow"
        backspace_us = 1000
        settle_us = 3000
        text_us = 1000
        engine_method = "vni"
        """
        let parsed = ShippedProfilesTOML.parse(toml)
        XCTAssertEqual(parsed.defaultProfile.injectionMethod, .backspaceFast)
        XCTAssertEqual(parsed.defaultProfile.delays, .zero)
        XCTAssertTrue(parsed.defaultProfile.enabled)

        let term = parsed.apps["com.apple.Terminal"]
        XCTAssertNotNil(term)
        XCTAssertEqual(term?.injectionMethod, .backspaceSlow)
        XCTAssertEqual(term?.delays.settleUs, 3000)
        XCTAssertEqual(term?.engineMethod, .vni)
        XCTAssertEqual(term?.bundleId, "com.apple.Terminal")
    }

    func testShippedTOMLIgnoresCommentsAndUnknownSections() {
        let toml = """
        # header comment
        [default]
        enabled = true # inline
        injection_method = "backspaceFast"

        [unknown]
        injection_method = "charByChar"

        [[apps]]
        bundle_id = "net.kovidgoyal.kitty"
        injection_method = "backspaceSlow"
        settle_us = 2500
        """
        let parsed = ShippedProfilesTOML.parse(toml)
        XCTAssertEqual(parsed.defaultProfile.injectionMethod, .backspaceFast)
        // Missing delay keys + backspaceFast → zero delays
        XCTAssertEqual(parsed.defaultProfile.delays, .zero)
        XCTAssertEqual(parsed.apps.count, 1)
        XCTAssertEqual(parsed.apps["net.kovidgoyal.kitty"]?.delays.settleUs, 2500)
    }

    // MARK: - Store

    func testStoreUserOverridesPersistInSuite() {
        let suiteName = "dau.tests.injection.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("suite")
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = InjectionProfileStore(
            defaults: defaults,
            shippedTOMLString: ""
        )
        XCTAssertTrue(store.userOverrides.isEmpty)

        let profile = InjectionProfile(
            enabled: false,
            engineMethod: .telex,
            injectionMethod: .passthrough,
            delays: .zero
        )
        store.setProfile(profile, forBundleId: "com.example.App")
        XCTAssertEqual(store.profile(forBundleId: "com.example.App")?.enabled, false)
        XCTAssertEqual(store.profile(forBundleId: "com.example.App")?.bundleId, "com.example.App")

        // Reload from same suite
        let store2 = InjectionProfileStore(defaults: defaults, shippedTOMLString: "")
        XCTAssertEqual(store2.profile(forBundleId: "com.example.App")?.injectionMethod, .passthrough)

        store2.removeProfile(forBundleId: "com.example.App")
        XCTAssertNil(store2.profile(forBundleId: "com.example.App"))
    }

    func testStoreLoadsShippedString() {
        let toml = """
        [default]
        injection_method = "backspaceFast"
        backspace_us = 0
        settle_us = 0
        text_us = 0

        [[apps]]
        bundle_id = "com.googlecode.iterm2"
        injection_method = "backspaceSlow"
        backspace_us = 1000
        settle_us = 3000
        text_us = 1000
        """
        let suiteName = "dau.tests.shipped.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = InjectionProfileStore(defaults: defaults, shippedTOMLString: toml)
        XCTAssertEqual(store.shippedDefault.delays, .zero)
        XCTAssertEqual(store.shippedByBundle["com.googlecode.iterm2"]?.injectionMethod, .backspaceSlow)
    }

    // MARK: - Resolver precedence

    private func makeStore(
        shipped: String,
        suite: String = UUID().uuidString
    ) -> (InjectionProfileStore, UserDefaults, String) {
        let suiteName = "dau.tests.resolver.\(suite)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = InjectionProfileStore(defaults: defaults, shippedTOMLString: shipped)
        return (store, defaults, suiteName)
    }

    /// Sample shipped TOML fixture. Delay values are deliberately non-zero so
    /// resolver/session wiring is distinguishable from the zero-delay default
    /// (the real shipped recipe lives in `Resources/profiles.toml`).
    private let sampleShipped = """
    [default]
    enabled = true
    injection_method = "backspaceFast"
    backspace_us = 0
    settle_us = 0
    text_us = 0

    [[apps]]
    bundle_id = "com.apple.Terminal"
    enabled = true
    injection_method = "backspaceSlow"
    backspace_us = 1000
    settle_us = 3000
    text_us = 1000
    """

    func testResolverUsesSafeDefaultWhenUnknownBundle() {
        let (store, defaults, suite) = makeStore(shipped: sampleShipped)
        defer { defaults.removePersistentDomain(forName: suite) }

        let resolver = InjectionProfileResolver(store: store)
        let r = resolver.resolve(bundleId: "com.unknown.App")
        XCTAssertEqual(r.source, .safeDefault)
        XCTAssertEqual(r.injectionMethod, .backspaceFast)
        XCTAssertEqual(r.delays, .zero)
        XCTAssertTrue(r.typingEnabled)
        XCTAssertEqual(r.engineMethod, .telex) // global default
    }

    func testResolverUsesShippedBundleOverDefault() {
        let (store, defaults, suite) = makeStore(shipped: sampleShipped)
        defer { defaults.removePersistentDomain(forName: suite) }

        let resolver = InjectionProfileResolver(store: store)
        let r = resolver.resolve(bundleId: "com.apple.Terminal")
        XCTAssertEqual(r.source, .shippedBundle)
        XCTAssertEqual(r.injectionMethod, .backspaceSlow)
        XCTAssertEqual(r.delays.settleUs, 3000)
    }

    func testResolverUserOverrideBeatsShipped() {
        let (store, defaults, suite) = makeStore(shipped: sampleShipped)
        defer { defaults.removePersistentDomain(forName: suite) }

        store.setProfile(
            InjectionProfile(
                enabled: true,
                engineMethod: .vni,
                injectionMethod: .charByChar,
                delays: .charByChar
            ),
            forBundleId: "com.apple.Terminal"
        )

        let resolver = InjectionProfileResolver(store: store)
        let r = resolver.resolve(bundleId: "com.apple.Terminal")
        XCTAssertEqual(r.source, .userOverride)
        XCTAssertEqual(r.injectionMethod, .charByChar)
        XCTAssertEqual(r.engineMethod, .vni)
        XCTAssertEqual(r.delays, .charByChar)
    }

    func testResolverDisabledProfileDisablesTyping() {
        let (store, defaults, suite) = makeStore(shipped: sampleShipped)
        defer { defaults.removePersistentDomain(forName: suite) }

        store.setProfile(
            InjectionProfile(enabled: false, injectionMethod: .backspaceFast, delays: .zero),
            forBundleId: "com.example.Off"
        )
        let resolver = InjectionProfileResolver(store: store)
        let r = resolver.resolve(bundleId: "com.example.Off")
        XCTAssertFalse(r.typingEnabled)
        XCTAssertEqual(r.effectiveInjectionMethod, .passthrough)
    }

    func testResolverRespectsGlobalTypingOff() {
        let (store, defaults, suite) = makeStore(shipped: sampleShipped)
        defer { defaults.removePersistentDomain(forName: suite) }

        let resolver = InjectionProfileResolver(store: store)
        resolver.globalTypingEnabled = false
        let r = resolver.resolve(bundleId: "com.apple.Terminal")
        XCTAssertFalse(r.typingEnabled)
        XCTAssertEqual(r.source, .shippedBundle)
    }

    func testResolverNilBundleUsesDefault() {
        let (store, defaults, suite) = makeStore(shipped: sampleShipped)
        defer { defaults.removePersistentDomain(forName: suite) }

        let resolver = InjectionProfileResolver(store: store)
        let r = resolver.resolve(bundleId: nil)
        XCTAssertEqual(r.source, .safeDefault)
        XCTAssertEqual(r.delays, .zero)
        // Unknown context must stay ENABLED on the safe default profile —
        // a nil bundle id right after focus change must never turn typing off.
        XCTAssertTrue(r.typingEnabled)
        XCTAssertEqual(r.injectionMethod, .backspaceFast)
    }

    func testResolverViaAppContextSnapshot() {
        let (store, defaults, suite) = makeStore(shipped: sampleShipped)
        defer { defaults.removePersistentDomain(forName: suite) }

        let resolver = InjectionProfileResolver(store: store)
        let ctx = AppContextSnapshot(
            bundleId: "com.apple.Terminal",
            appName: "Terminal",
            role: .terminal,
            generation: 1
        )
        let r = resolver.resolve(context: ctx)
        XCTAssertEqual(r.source, .shippedBundle)
        XCTAssertEqual(r.injectionMethod, .backspaceSlow)
    }

    // MARK: - Role fallback layer (P2.3)

    /// Sample shipped TOML with NO per-app rows, so role fallback can be isolated.
    private let defaultOnlyShipped = """
    [default]
    enabled = true
    injection_method = "backspaceFast"
    backspace_us = 0
    settle_us = 0
    text_us = 0
    """

    func testRoleFallbackWhenNoBundleProfile() {
        let (store, defaults, suite) = makeStore(shipped: defaultOnlyShipped)
        defer { defaults.removePersistentDomain(forName: suite) }

        let resolver = InjectionProfileResolver(store: store)
        let ctx = AppContextSnapshot(
            bundleId: "com.unknown.Editor",
            appName: "Editor",
            role: .editor,
            generation: 1
        )
        let r = resolver.resolve(context: ctx)
        XCTAssertEqual(r.source, .roleFallback)
        XCTAssertEqual(r.injectionMethod, .charByChar)
        XCTAssertTrue(r.typingEnabled)
        XCTAssertEqual(r.delays, .zero)
    }

    func testRoleFallbackMappingPerCategory() {
        let (store, defaults, suite) = makeStore(shipped: defaultOnlyShipped)
        defer { defaults.removePersistentDomain(forName: suite) }

        let resolver = InjectionProfileResolver(store: store)
        let expectations: [AXRoleCategory: InjectionMethod] = [
            .terminal: .backspaceFast,
            .editor: .charByChar,
            .textField: .backspaceFast,
            .comboBox: .selection,
            .addressBar: .emptyCharPrefix,
            .other: .backspaceFast,
        ]
        for (role, method) in expectations {
            let ctx = AppContextSnapshot(bundleId: "com.role.\(role.rawValue)", appName: nil, role: role, generation: 1)
            let r = resolver.resolve(context: ctx)
            XCTAssertEqual(r.source, .roleFallback, "role \(role.rawValue)")
            XCTAssertEqual(r.injectionMethod, method, "role \(role.rawValue)")
        }
    }

    func testRoleFallbackRespectsGlobalTypingOff() {
        let (store, defaults, suite) = makeStore(shipped: defaultOnlyShipped)
        defer { defaults.removePersistentDomain(forName: suite) }

        let resolver = InjectionProfileResolver(store: store)
        resolver.globalTypingEnabled = false
        let ctx = AppContextSnapshot(bundleId: "com.x.Editor", appName: nil, role: .editor, generation: 1)
        let r = resolver.resolve(context: ctx)
        XCTAssertEqual(r.source, .roleFallback)
        XCTAssertFalse(r.typingEnabled)
        XCTAssertEqual(r.effectiveInjectionMethod, .passthrough)
    }

    // MARK: - Secure field hard passthrough (Phase 2)

    /// Secure/password role must resolve to hard passthrough EN: typing off,
    /// passthrough delivery, zero delays — and a dedicated source.
    func testSecureRoleResolvesToHardPassthrough() {
        let (store, defaults, suite) = makeStore(shipped: defaultOnlyShipped)
        defer { defaults.removePersistentDomain(forName: suite) }

        let resolver = InjectionProfileResolver(store: store)
        let ctx = AppContextSnapshot(bundleId: "com.unknown.Login", appName: nil, role: .secure, generation: 1)
        let r = resolver.resolve(context: ctx)
        XCTAssertEqual(r.source, .securePassthrough)
        XCTAssertFalse(r.typingEnabled)
        XCTAssertEqual(r.injectionMethod, .passthrough)
        XCTAssertEqual(r.effectiveInjectionMethod, .passthrough)
        XCTAssertEqual(r.delays, .zero)
    }

    /// Secure must win over a user override that would otherwise type in that app.
    func testSecureRoleBeatsUserOverride() {
        let (store, defaults, suite) = makeStore(shipped: defaultOnlyShipped)
        defer { defaults.removePersistentDomain(forName: suite) }

        store.setProfile(
            InjectionProfile(
                enabled: true,
                engineMethod: .telex,
                injectionMethod: .charByChar,
                delays: .charByChar
            ),
            forBundleId: "com.example.Login"
        )
        let resolver = InjectionProfileResolver(store: store)
        let ctx = AppContextSnapshot(bundleId: "com.example.Login", appName: nil, role: .secure, generation: 1)
        let r = resolver.resolve(context: ctx)
        XCTAssertEqual(r.source, .securePassthrough)
        XCTAssertFalse(r.typingEnabled)
        XCTAssertEqual(r.effectiveInjectionMethod, .passthrough)
    }

    /// Secure must win over a shipped bundle row (e.g. Terminal shipped profile
    /// must not inject into a password prompt inside that terminal).
    func testSecureRoleBeatsShippedBundle() {
        let (store, defaults, suite) = makeStore(shipped: sampleShipped) // Terminal → backspaceSlow
        defer { defaults.removePersistentDomain(forName: suite) }

        let resolver = InjectionProfileResolver(store: store)
        let ctx = AppContextSnapshot(bundleId: "com.apple.Terminal", appName: "Terminal", role: .secure, generation: 1)
        let r = resolver.resolve(context: ctx)
        XCTAssertEqual(r.source, .securePassthrough)
        XCTAssertFalse(r.typingEnabled)
        XCTAssertEqual(r.effectiveInjectionMethod, .passthrough)
    }

    // MARK: - Browser host regression (no broad browser bundle rows)

    /// Known browser address bar must resolve to emptyCharPrefix via role — NOT be
    /// shadowed by a broad browser bundle row. The real shipped profiles.toml has no
    /// Safari/Chrome/Chromium rows so the AX role decides browser behavior.
    func testKnownBrowserAddressBarResolvesToEmptyCharPrefix() {
        let (store, defaults, suite) = makeStore(shipped: defaultOnlyShipped)
        defer { defaults.removePersistentDomain(forName: suite) }

        let resolver = InjectionProfileResolver(store: store)
        let browsers = ["com.apple.Safari", "com.google.Chrome", "org.chromium.Chromium"]
        for bundleId in browsers {
            let ctx = AppContextSnapshot(
                bundleId: bundleId,
                appName: nil,
                role: .addressBar,
                generation: 1
            )
            let r = resolver.resolve(context: ctx)
            XCTAssertEqual(r.source, .roleFallback, "bundle \(bundleId) address bar")
            XCTAssertEqual(
                r.injectionMethod,
                .emptyCharPrefix,
                "bundle \(bundleId) address bar must use emptyCharPrefix"
            )
            XCTAssertTrue(r.typingEnabled)
        }
    }

    /// Normal browser text input (editor/textarea role) must resolve to charByChar via role.
    func testKnownBrowserTextInputResolvesViaRolePolicy() {
        let (store, defaults, suite) = makeStore(shipped: defaultOnlyShipped)
        defer { defaults.removePersistentDomain(forName: suite) }

        let resolver = InjectionProfileResolver(store: store)
        let ctx = AppContextSnapshot(
            bundleId: "com.apple.Safari",
            appName: nil,
            role: .editor,
            generation: 1
        )
        let r = resolver.resolve(context: ctx)
        XCTAssertEqual(r.source, .roleFallback)
        XCTAssertEqual(r.injectionMethod, .charByChar)
    }

    /// Browser AX focus may be inconclusive for contenteditable web inputs. In
    /// that case use the web-safe text path instead of the terminal-style default.
    func testKnownBrowserNilRoleUsesCharByCharFallback() {
        let (store, defaults, suite) = makeStore(shipped: defaultOnlyShipped)
        defer { defaults.removePersistentDomain(forName: suite) }

        let resolver = InjectionProfileResolver(store: store)
        let browsers = [
            "com.brave.Browser",
            "com.google.Chrome",
            "com.microsoft.edgemac",
            "org.mozilla.firefox",
            "company.thebrowser.Browser",
        ]
        for bundleId in browsers {
            let ctx = AppContextSnapshot(
                bundleId: bundleId,
                appName: nil,
                role: nil,
                generation: 1
            )
            let r = resolver.resolve(context: ctx)
            XCTAssertEqual(r.source, .roleFallback, "bundle \(bundleId)")
            XCTAssertEqual(r.injectionMethod, .charByChar, "bundle \(bundleId)")
            XCTAssertTrue(r.typingEnabled, "bundle \(bundleId)")
        }
    }

    /// A broad Safari bundle row must NOT appear in the shipped table (would shadow
    /// the addressBar role). Guards the shipped file against regression.
    func testShippedProfilesContainNoBrowserRows() {
        let url = Bundle.main.url(forResource: "profiles", withExtension: "toml")
        let raw: String
        if let url, let contents = try? String(contentsOf: url, encoding: .utf8) {
            raw = contents
        } else {
            // Fallback: parse the repo-shipped shape (no browser rows expected).
            raw = """
            [default]
            injection_method = "backspaceFast"
            [[apps]]
            bundle_id = "com.apple.Terminal"
            injection_method = "backspaceFast"
            """
        }
        let parsed = ShippedProfilesTOML.parse(raw)
        let browserBundleIds = [
            "com.apple.Safari",
            "com.apple.SafariTechnologyPreview",
            "com.brave.Browser",
            "com.google.Chrome",
            "org.chromium.Chromium",
        ]
        for bundleId in browserBundleIds {
            XCTAssertNil(
                parsed.apps[bundleId],
                "shipped must not pin browser bundle \(bundleId) — AX role decides"
            )
        }
    }

    /// User override for a known browser must still win over the role policy.
    func testUserOverrideBeatsBrowserRolePolicy() {
        let (store, defaults, suite) = makeStore(shipped: defaultOnlyShipped)
        defer { defaults.removePersistentDomain(forName: suite) }

        store.setProfile(
            InjectionProfile(
                enabled: true,
                engineMethod: .telex,
                injectionMethod: .backspaceSlow,
                delays: .slow
            ),
            forBundleId: "com.apple.Safari"
        )
        let resolver = InjectionProfileResolver(store: store)
        let ctx = AppContextSnapshot(
            bundleId: "com.apple.Safari",
            appName: nil,
            role: .addressBar,
            generation: 1
        )
        let r = resolver.resolve(context: ctx)
        XCTAssertEqual(r.source, .userOverride)
        XCTAssertEqual(r.injectionMethod, .backspaceSlow)
    }

    func testRoleFallbackEngineInheritsGlobal() {
        let (store, defaults, suite) = makeStore(shipped: defaultOnlyShipped)
        defer { defaults.removePersistentDomain(forName: suite) }

        let resolver = InjectionProfileResolver(store: store)
        resolver.globalEngineMethod = .vni
        let ctx = AppContextSnapshot(bundleId: "com.x.Field", appName: nil, role: .textField, generation: 1)
        let r = resolver.resolve(context: ctx)
        XCTAssertEqual(r.source, .roleFallback)
        XCTAssertEqual(r.engineMethod, .vni)
    }

    func testShippedBundleBeatsRoleFallback() {
        let (store, defaults, suite) = makeStore(shipped: sampleShipped) // com.apple.Terminal → backspaceSlow
        defer { defaults.removePersistentDomain(forName: suite) }

        let resolver = InjectionProfileResolver(store: store)
        let ctx = AppContextSnapshot(
            bundleId: "com.apple.Terminal",
            appName: "Terminal",
            role: .editor, // conflicting role must NOT beat the shipped bundle row
            generation: 1
        )
        let r = resolver.resolve(context: ctx)
        XCTAssertEqual(r.source, .shippedBundle)
        XCTAssertEqual(r.injectionMethod, .backspaceSlow)
    }

    func testUserOverrideBeatsRoleFallback() {
        let (store, defaults, suite) = makeStore(shipped: defaultOnlyShipped)
        defer { defaults.removePersistentDomain(forName: suite) }

        store.setProfile(
            InjectionProfile(
                enabled: true,
                engineMethod: .telex,
                injectionMethod: .backspaceSlow,
                delays: .slow
            ),
            forBundleId: "com.x.Editor"
        )
        let resolver = InjectionProfileResolver(store: store)
        let ctx = AppContextSnapshot(bundleId: "com.x.Editor", appName: nil, role: .editor, generation: 1)
        let r = resolver.resolve(context: ctx)
        XCTAssertEqual(r.source, .userOverride)
        XCTAssertEqual(r.injectionMethod, .backspaceSlow)
    }

    func testRoleFallbackOnlyForKnownRole() {
        let (store, defaults, suite) = makeStore(shipped: defaultOnlyShipped)
        defer { defaults.removePersistentDomain(forName: suite) }

        let resolver = InjectionProfileResolver(store: store)
        let ctx = AppContextSnapshot(bundleId: "com.x.Unknown", appName: nil, role: nil, generation: 1)
        let r = resolver.resolve(context: ctx)
        XCTAssertEqual(r.source, .safeDefault)
        XCTAssertEqual(r.injectionMethod, .backspaceFast)
    }

    // MARK: - AppContextResolver cache

    private final class FakeFrontmost: FrontmostAppProviding {
        var bundleId: String?
        var appName: String?
        var callCount = 0
        func frontmostApp() -> (bundleId: String?, appName: String?) {
            callCount += 1
            return (bundleId, appName)
        }
    }

    private final class FakeRole: AXRoleProviding {
        var role: AXRoleCategory?
        var callCount = 0
        func focusedRoleCategory() -> AXRoleCategory? {
            callCount += 1
            return role
        }
    }

    func testAppContextResolverCachesUntilInvalidate() {
        let front = FakeFrontmost()
        front.bundleId = "com.apple.Terminal"
        front.appName = "Terminal"
        let role = FakeRole()
        role.role = .terminal

        let resolver = AppContextResolver(frontmostProvider: front, roleProvider: role)
        let a = resolver.current
        let b = resolver.current
        XCTAssertEqual(front.callCount, 1)
        XCTAssertEqual(role.callCount, 1)
        XCTAssertEqual(a.bundleId, "com.apple.Terminal")
        XCTAssertEqual(a.role, .terminal)
        XCTAssertEqual(a.generation, b.generation)

        resolver.invalidate()
        front.bundleId = "com.googlecode.iterm2"
        role.role = nil
        let c = resolver.current
        XCTAssertEqual(front.callCount, 2)
        XCTAssertEqual(role.callCount, 2)
        XCTAssertEqual(c.bundleId, "com.googlecode.iterm2")
        XCTAssertNil(c.role)
        XCTAssertEqual(c.generation, a.generation + 1)
    }

    // MARK: - FocusChangeObserver

    func testFocusChangeObserverSeedsCacheAndNotifies() {
        let front = FakeFrontmost()
        front.bundleId = "com.a"
        let context = AppContextResolver(
            frontmostProvider: front,
            roleProvider: StubAXRoleProvider()
        )
        _ = context.refresh()
        XCTAssertTrue(context.hasValidCache)

        let observer = FocusChangeObserver(contextResolver: context)
        var seen: [(String?, String?)] = []
        observer.onFocusChange = { prev, next in
            seen.append((prev, next))
        }

        observer.simulateActivation(bundleId: "com.b")
        // Activation seeds the cache from the notification id (no provider re-query required).
        XCTAssertTrue(context.hasValidCache)
        XCTAssertEqual(context.current.bundleId, "com.b")
        XCTAssertEqual(seen.count, 1)
        XCTAssertEqual(seen[0].0, "com.a")
        XCTAssertEqual(seen[0].1, "com.b")
    }

    /// AX fail-safe: a focused-element change inside the current app must stale the
    /// cache (role re-classified lazily) and fire the hook with the same bundle id.
    func testFocusChangeObserverAXFocusChangeInvalidatesSameBundle() {
        let front = FakeFrontmost()
        front.bundleId = "com.a"
        let context = AppContextResolver(
            frontmostProvider: front,
            roleProvider: StubAXRoleProvider()
        )
        _ = context.refresh()
        XCTAssertTrue(context.hasValidCache)

        let observer = FocusChangeObserver(contextResolver: context)
        var seen: [(String?, String?)] = []
        observer.onFocusChange = { prev, next in
            seen.append((prev, next))
        }
        // Establish lastBundleId without a workspace round-trip.
        observer.simulateActivation(bundleId: "com.a")
        XCTAssertTrue(context.hasValidCache)
        let countBefore = seen.count

        observer.simulateAXFocusChange()

        XCTAssertFalse(context.hasValidCache, "AX focus change must stale the resolver cache")
        XCTAssertEqual(seen.count, countBefore + 1)
        XCTAssertEqual(seen.last?.0, "com.a", "previous bundle must be the same-app bundle")
        XCTAssertEqual(seen.last?.1, "com.a", "new bundle must equal the same-app bundle")
        // Re-resolve re-classifies; must still report the same frontmost bundle.
        XCTAssertEqual(context.current.bundleId, "com.a")
    }

    /// start()/stop() are idempotent: double-start does not double-register and
    /// double-stop is a safe no-op (AX registration is guarded by pid/trust).
    func testFocusChangeObserverStartStopIsIdempotent() {
        let front = FakeFrontmost()
        front.bundleId = "com.a"
        let context = AppContextResolver(
            frontmostProvider: front,
            roleProvider: StubAXRoleProvider()
        )
        let observer = FocusChangeObserver(contextResolver: context)

        observer.start()
        observer.start()
        XCTAssertTrue(observer.isRunning)

        observer.stop()
        observer.stop()
        XCTAssertFalse(observer.isRunning)
    }

    /// Terminal shipped profile must resolve to backspaceSlow + TOML delays, and the
    /// session must receive a non-nil bundle id when context has an app (profile wiring).
    func testTerminalProfileAppliesToSessionWithBundleId() {
        let (store, defaults, suite) = makeStore(shipped: sampleShipped)
        defer { defaults.removePersistentDomain(forName: suite) }

        let front = FakeFrontmost()
        front.bundleId = "com.apple.Terminal"
        front.appName = "Terminal"
        let context = AppContextResolver(
            frontmostProvider: front,
            roleProvider: StubAXRoleProvider()
        )
        let snapshot = context.refresh()
        XCTAssertEqual(snapshot.bundleId, "com.apple.Terminal")

        let resolver = InjectionProfileResolver(store: store)
        let resolved = resolver.resolve(context: snapshot)
        XCTAssertEqual(resolved.source, .shippedBundle)
        XCTAssertEqual(resolved.injectionMethod, .backspaceSlow)
        XCTAssertEqual(resolved.delays.backspaceUs, 1000)
        XCTAssertEqual(resolved.delays.settleUs, 3000)
        XCTAssertEqual(resolved.delays.textUs, 1000)

        // Mirror AppDelegate.refreshProfileCache: pass method/delays/bundle from resolve.
        let session = TypingSession()
        session.applyRuntimeSettings(
            typingEnabled: resolved.typingEnabled,
            injectionMethod: resolved.effectiveInjectionMethod,
            delays: resolved.delays,
            engineMethod: DauMethod_Telex,
            frontmostBundleId: snapshot.bundleId
        )
        XCTAssertEqual(session.currentInjectionMethod(), .backspaceSlow)
        XCTAssertEqual(session.currentDelays().backspaceUs, 1000)
        XCTAssertEqual(session.currentDelays().settleUs, 3000)
        XCTAssertEqual(session.currentDelays().textUs, 1000)
        XCTAssertEqual(session.currentFrontmostBundleId(), "com.apple.Terminal")
        XCTAssertNotNil(session.currentFrontmostBundleId())
    }

    func testUpdateFrontmostSeedsCacheWithoutProvider() {
        let front = FakeFrontmost()
        front.bundleId = "com.old"
        let context = AppContextResolver(
            frontmostProvider: front,
            roleProvider: StubAXRoleProvider()
        )
        _ = context.refresh()
        XCTAssertEqual(front.callCount, 1)

        let seeded = context.updateFrontmost(bundleId: "com.apple.Terminal", appName: "Terminal")
        XCTAssertEqual(seeded.bundleId, "com.apple.Terminal")
        XCTAssertEqual(seeded.appName, "Terminal")
        XCTAssertTrue(context.hasValidCache)
        // updateFrontmost must not re-query the workspace provider.
        XCTAssertEqual(front.callCount, 1)
        XCTAssertEqual(context.current.bundleId, "com.apple.Terminal")
        XCTAssertEqual(front.callCount, 1)
    }

    // MARK: - AX role token classification (pure)

    func testClassifyAddressBarTokens() {
        XCTAssertEqual(AXFocusedRoleProvider.category(role: "AXTextField", identifier: "url-field"), .addressBar)
        XCTAssertEqual(AXFocusedRoleProvider.category(role: "AXTextField", description: "Address and Search"), .addressBar)
        XCTAssertEqual(AXFocusedRoleProvider.category(role: "AXTextField", identifier: "address_bar"), .addressBar)
    }

    func testClassifyComboBoxAndSearchField() {
        XCTAssertEqual(AXFocusedRoleProvider.category(role: kAXComboBoxRole as String), .comboBox)
        XCTAssertEqual(AXFocusedRoleProvider.category(role: "AXUnknown", description: "combobox"), .comboBox)
        XCTAssertEqual(AXFocusedRoleProvider.category(role: "AXTextField", subrole: kAXSearchFieldSubrole as String), .textField)
    }

    func testClassifyTerminalTokens() {
        XCTAssertEqual(AXFocusedRoleProvider.category(role: "AXTextArea", description: "terminal"), .terminal)
        XCTAssertEqual(AXFocusedRoleProvider.category(role: "AXTextArea", identifier: "tty"), .terminal)
    }

    func testClassifyEditorTextArea() {
        XCTAssertEqual(AXFocusedRoleProvider.category(role: kAXTextAreaRole as String), .editor)
        XCTAssertEqual(AXFocusedRoleProvider.category(role: "AXTextArea", identifier: "code-editor"), .editor)
    }

    func testClassifyPlainTextField() {
        XCTAssertEqual(AXFocusedRoleProvider.category(role: kAXTextFieldRole as String), .textField)
        XCTAssertEqual(AXFocusedRoleProvider.category(role: "AXTextField", identifier: "search"), .textField)
    }

    func testClassifySecureTextField() {
        // kAXSecureTextFieldRole is not exposed in Swift — use the literal role name.
        XCTAssertEqual(AXFocusedRoleProvider.category(role: "AXSecureTextField"), .secure)
        XCTAssertEqual(AXFocusedRoleProvider.category(role: "AXSecureTextField", description: "password"), .secure)
    }

    /// Secure must win over address/text-field tokens that would otherwise classify first.
    func testClassifySecureBeatsAddressBarAndTextField() {
        XCTAssertEqual(
            AXFocusedRoleProvider.category(role: "AXSecureTextField", identifier: "url"),
            .secure
        )
        XCTAssertEqual(
            AXFocusedRoleProvider.category(role: "AXTextField", description: "password"),
            .secure
        )
    }

    func testClassifyInconclusiveReturnsNil() {
        XCTAssertNil(AXFocusedRoleProvider.category(role: "AXWindow"))
        XCTAssertNil(AXFocusedRoleProvider.category(role: "AXButton"))
        XCTAssertNil(AXFocusedRoleProvider.category(role: ""))
    }

    func testClassifyAddressBarBeatsTextField() {
        // AddressBar check precedes textField so a URL-ish text field maps to addressBar.
        XCTAssertEqual(AXFocusedRoleProvider.category(role: "AXTextField", description: "url address"), .addressBar)
    }

    // MARK: - AXFocusedRoleProvider production wiring (bounded, no real AX in tests)

    func testAXFocusedRoleProviderDefaultsToBoundedAccessor() {
        // The class is constructible without arguments and its init uses the real
        // AXTextAccessor with a capped messaging timeout — never blocks the hot path.
        let provider = AXFocusedRoleProvider()
        XCTAssertNotNil(provider)
    }

    // MARK: - Shipped developer-surface contract (real profiles.toml on disk)

    /// Locate the real repo-shipped `Resources/profiles.toml` from the test source
    /// path. The test bundle has no resource-copy phase (see Dau.xcodeproj), so
    /// `Bundle.main` cannot reach it — resolving relative to `#filePath` keeps the
    /// shipped-file guards honest instead of silently falling back to a sample.
    private func loadRealShippedProfiles() throws -> ShippedProfilesTOML.Parsed {
        let sourceDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let resourcesDir = sourceDir
            .deletingLastPathComponent()   // Tests/
            .appendingPathComponent("Resources")
        let url = resourcesDir.appendingPathComponent("profiles.toml")
        let raw = try String(contentsOf: url, encoding: .utf8)
        return ShippedProfilesTOML.parse(raw)
    }

    /// Terminal / AI CLI hosts ship backspaceFast + zero delays (north star).
    /// Zero-delay is required: ordering vs. physical keys is guaranteed by
    /// session-tap posting, and any non-zero delay blows the 12ms callback budget.
    func testShippedTerminalHostsAreBackspaceFastZeroDelay() throws {
        let parsed = try loadRealShippedProfiles()
        let terminalHosts = [
            "com.apple.Terminal",
            "com.googlecode.iterm2",
            "net.kovidgoyal.kitty",
            "com.mitchellh.ghostty",
            "org.alacritty",
            "io.alacritty",
            "com.github.wez.wezterm",
            "dev.warp.Warp-Stable",
            "co.zeit.hyper",
            "org.tabby",
        ]
        for bundleId in terminalHosts {
            let profile = try XCTUnwrap(parsed.apps[bundleId], "shipped row missing for \(bundleId)")
            XCTAssertEqual(profile.injectionMethod, .backspaceFast, "\(bundleId)")
            XCTAssertEqual(profile.delays, .zero, "\(bundleId) must ship zero delay")
        }
    }

    /// Electron editor / chat hosts ship charByChar — Monaco/Electron textareas are
    /// repaint-heavy, so per-scalar delivery keeps the provisional display in sync.
    func testShippedElectronEditorAndChatRowsAreCharByChar() throws {
        let parsed = try loadRealShippedProfiles()
        let electronHosts = [
            "com.microsoft.VSCode",
            "com.microsoft.VSCodeInsiders",
            "com.todesktop.cursor",
            "com.todesktop.230313mzl4w4u92",
            "notion.id",
        ]
        for bundleId in electronHosts {
            let profile = try XCTUnwrap(parsed.apps[bundleId], "shipped row missing for \(bundleId)")
            XCTAssertEqual(profile.injectionMethod, .charByChar, "\(bundleId)")
            XCTAssertEqual(profile.delays, .zero, "\(bundleId)")
        }
    }

    /// Native (non-Electron) editor Zed ships backspaceFast — bulk path is reliable.
    func testShippedNativeEditorZedIsBackspaceFastZeroDelay() throws {
        let parsed = try loadRealShippedProfiles()
        let zed = try XCTUnwrap(parsed.apps["dev.zed.Zed"])
        XCTAssertEqual(zed.injectionMethod, .backspaceFast)
        XCTAssertEqual(zed.delays, .zero)
    }

    /// Shipped default stays backspaceFast + zero delay (safe fallback for unknown apps).
    func testShippedDefaultIsBackspaceFastZeroDelay() throws {
        let parsed = try loadRealShippedProfiles()
        XCTAssertEqual(parsed.defaultProfile.injectionMethod, .backspaceFast)
        XCTAssertEqual(parsed.defaultProfile.delays, .zero)
    }

    /// Real shipped file: no broad browser bundle rows (would shadow the AX role
    /// policy). Same guard as the sample-based test, but against the actual file.
    func testRealShippedProfilesContainNoBrowserRows() throws {
        let parsed = try loadRealShippedProfiles()
        let browserBundleIds = [
            "com.apple.Safari",
            "com.apple.SafariTechnologyPreview",
            "com.google.Chrome",
            "org.chromium.Chromium",
        ]
        for bundleId in browserBundleIds {
            XCTAssertNil(parsed.apps[bundleId], "shipped must not pin browser bundle \(bundleId) — AX role decides")
        }
    }

    /// Real shipped file: every row uses an implemented delivery method — no
    /// declared-only stub that would need a fallback rewrite at runtime.
    func testRealShippedProfilesUseOnlyImplementedMethods() throws {
        let parsed = try loadRealShippedProfiles()
        XCTAssertTrue(
            parsed.defaultProfile.injectionMethod.isMVPImplemented,
            "default must not be a declared-only stub"
        )
        for (bundle, profile) in parsed.apps {
            XCTAssertTrue(
                profile.injectionMethod.isMVPImplemented,
                "shipped \(bundle) uses unimplemented method \(profile.injectionMethod.rawValue)"
            )
            XCTAssertEqual(
                profile.deliveryMethod,
                profile.injectionMethod,
                "shipped \(bundle) should not need fallback rewrite"
            )
        }
    }
}
