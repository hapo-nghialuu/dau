// Dấu macOS — InjectionProfile / store / resolver unit tests (WP-05).

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
        XCTAssertTrue(InjectionMethod.selection.requiresDeliveryFallback)
        XCTAssertTrue(InjectionMethod.emptyCharPrefix.requiresDeliveryFallback)
        XCTAssertTrue(InjectionMethod.syncProxy.requiresDeliveryFallback)
        XCTAssertFalse(InjectionMethod.backspaceFast.requiresDeliveryFallback)
        XCTAssertFalse(InjectionMethod.backspaceSlow.requiresDeliveryFallback)
        XCTAssertFalse(InjectionMethod.charByChar.requiresDeliveryFallback)
        XCTAssertFalse(InjectionMethod.axDirect.requiresDeliveryFallback)
        XCTAssertFalse(InjectionMethod.passthrough.requiresDeliveryFallback)
    }

    func testProfileSanitizedForDeliveryRewritesStubs() {
        let raw = InjectionProfile(
            bundleId: "com.example.App",
            enabled: true,
            injectionMethod: .selection,
            delays: .fast
        )
        XCTAssertEqual(raw.injectionMethod, .selection)
        let clean = raw.sanitizedForDelivery(logFallback: false)
        XCTAssertEqual(clean.injectionMethod, .backspaceFast)
        XCTAssertEqual(clean.delays, .fast)
        XCTAssertEqual(clean.bundleId, "com.example.App")
    }

    func testResolvedSettingsSanitizedForDelivery() {
        let resolved = ResolvedInjectionSettings(
            typingEnabled: true,
            engineMethod: .telex,
            injectionMethod: .emptyCharPrefix,
            delays: .zero,
            source: .userOverride
        )
        XCTAssertEqual(resolved.injectionMethod, .emptyCharPrefix)
        XCTAssertEqual(resolved.deliveryMethod, .backspaceFast)
        let clean = resolved.sanitizedForDelivery(logFallback: false)
        XCTAssertEqual(clean.injectionMethod, .backspaceFast)
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
}
