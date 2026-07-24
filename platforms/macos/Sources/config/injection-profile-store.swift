// Dấu macOS — UserDefaults + shipped profiles.toml for injection profiles (WP-05).
// User overrides win at resolve time; shipped table is read-only from the app bundle.

import Foundation

/// Loads and saves user per-app injection overrides; holds shipped defaults.
///
/// - User overrides: `UserDefaults` (JSON), key `dau.injectionProfiles.v1`.
/// - Shipped: `profiles.toml` from the main bundle (or an injected URL/string for tests).
final class InjectionProfileStore {
    static let defaultsKey = "dau.injectionProfiles.v1"
    static let shippedResourceName = "profiles"
    static let shippedResourceExtension = "toml"

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    /// In-memory user overrides keyed by bundle id.
    private(set) var userOverrides: [String: InjectionProfile] = [:]

    /// Shipped per-bundle profiles (from TOML).
    private(set) var shippedByBundle: [String: InjectionProfile] = [:]

    /// Shipped / baked-in default profile.
    private(set) var shippedDefault: InjectionProfile = .mvpDefault

    init(
        defaults: UserDefaults = .standard,
        shippedTOMLURL: URL? = nil,
        shippedTOMLString: String? = nil
    ) {
        self.defaults = defaults
        reloadUserOverrides()
        loadShipped(
            url: shippedTOMLURL ?? Self.bundledProfilesURL(),
            string: shippedTOMLString
        )
    }

    // MARK: - User overrides

    /// Re-read user overrides from UserDefaults (empty map if missing/corrupt).
    @discardableResult
    func reloadUserOverrides() -> [String: InjectionProfile] {
        guard let data = defaults.data(forKey: Self.defaultsKey) else {
            userOverrides = [:]
            return userOverrides
        }
        do {
            let decoded = try decoder.decode([String: InjectionProfile].self, from: data)
            userOverrides = decoded
        } catch {
            // Corrupt payload: start empty rather than crash; do not log content.
            userOverrides = [:]
        }
        return userOverrides
    }

    func profile(forBundleId bundleId: String) -> InjectionProfile? {
        userOverrides[bundleId]
    }

    /// Insert or replace a per-app override and persist.
    func setProfile(_ profile: InjectionProfile, forBundleId bundleId: String) {
        var next = profile
        next.bundleId = bundleId
        userOverrides[bundleId] = next
        persistUserOverrides()
    }

    /// Remove a per-app override (falls back to shipped/default).
    func removeProfile(forBundleId bundleId: String) {
        userOverrides.removeValue(forKey: bundleId)
        persistUserOverrides()
    }

    /// Drop all user overrides.
    func resetAllUserOverrides() {
        userOverrides = [:]
        defaults.removeObject(forKey: Self.defaultsKey)
    }

    private func persistUserOverrides() {
        do {
            let data = try encoder.encode(userOverrides)
            defaults.set(data, forKey: Self.defaultsKey)
        } catch {
            // Leave in-memory state; caller can retry.
        }
    }

    // MARK: - Shipped TOML

    /// Load shipped default + app map from URL and/or raw string.
    /// String wins when both are provided (tests). On parse failure, keep MVP default.
    func loadShipped(url: URL? = nil, string: String? = nil) {
        let raw: String?
        if let string {
            raw = string
        } else if let url, let contents = try? String(contentsOf: url, encoding: .utf8) {
            raw = contents
        } else {
            raw = nil
        }

        guard let raw else {
            shippedDefault = .mvpDefault
            shippedByBundle = [:]
            return
        }

        let parsed = ShippedProfilesTOML.parse(raw)
        shippedDefault = parsed.defaultProfile
        shippedByBundle = parsed.apps
    }

    /// Bundle resource URL for `profiles.toml`, if present.
    static func bundledProfilesURL(
        bundle: Bundle = .main
    ) -> URL? {
        bundle.url(
            forResource: shippedResourceName,
            withExtension: shippedResourceExtension
        )
    }
}

// MARK: - Minimal TOML subset for shipped profiles

/// Line-oriented parser for the MVP `profiles.toml` shape:
///
/// ```toml
/// [default]
/// enabled = true
/// injection_method = "backspaceFast"
/// backspace_us = 0
/// settle_us = 0
/// text_us = 0
///
/// [[apps]]
/// bundle_id = "com.apple.Terminal"
/// enabled = true
/// injection_method = "backspaceSlow"
/// backspace_us = 1000
/// settle_us = 3000
/// text_us = 1000
/// engine_method = "telex"   # optional
/// ```
enum ShippedProfilesTOML {
    struct Parsed: Equatable {
        var defaultProfile: InjectionProfile
        var apps: [String: InjectionProfile]
    }

    static func parse(_ text: String) -> Parsed {
        var defaultFields: [String: String] = [:]
        var apps: [String: InjectionProfile] = [:]
        var currentSection: Section = .none
        var appFields: [String: String] = [:]

        func flushApp() {
            guard currentSection == .apps else { return }
            if let profile = profile(from: appFields, requireBundleId: true),
               let id = profile.bundleId {
                apps[id] = profile
            }
            appFields = [:]
        }

        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = stripComment(String(rawLine)).trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            if line == "[default]" {
                flushApp()
                currentSection = .defaultSection
                continue
            }
            if line == "[[apps]]" {
                flushApp()
                currentSection = .apps
                appFields = [:]
                continue
            }
            if line.hasPrefix("[") {
                // Unknown section — stop applying keys until a known header.
                flushApp()
                currentSection = .none
                continue
            }

            guard let (key, value) = parseKeyValue(line) else { continue }
            switch currentSection {
            case .defaultSection:
                defaultFields[key] = value
            case .apps:
                appFields[key] = value
            case .none:
                break
            }
        }
        flushApp()

        let defaultProfile = profile(from: defaultFields, requireBundleId: false)
            ?? .mvpDefault

        return Parsed(defaultProfile: defaultProfile, apps: apps)
    }

    // MARK: - Helpers

    private enum Section {
        case none
        case defaultSection
        case apps
    }

    private static func stripComment(_ line: String) -> String {
        // Strip unquoted `#` comments.
        var inQuote = false
        var result = ""
        for ch in line {
            if ch == "\"" {
                inQuote.toggle()
                result.append(ch)
                continue
            }
            if ch == "#", !inQuote { break }
            result.append(ch)
        }
        return result
    }

    private static func parseKeyValue(_ line: String) -> (String, String)? {
        guard let eq = line.firstIndex(of: "=") else { return nil }
        let key = line[..<eq].trimmingCharacters(in: .whitespaces)
        var value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
            value = String(value.dropFirst().dropLast())
        }
        guard !key.isEmpty else { return nil }
        return (key, String(value))
    }

    private static func profile(
        from fields: [String: String],
        requireBundleId: Bool
    ) -> InjectionProfile? {
        if requireBundleId, fields["bundle_id"] == nil {
            return nil
        }

        let enabled = parseBool(fields["enabled"]) ?? true
        let method = parseInjectionMethod(fields["injection_method"]) ?? .backspaceFast
        let delays = DelayPreset(
            backspaceUs: parseUInt32(fields["backspace_us"]) ?? (method == .backspaceFast ? 0 : method.defaultDelays.backspaceUs),
            settleUs: parseUInt32(fields["settle_us"]) ?? (method == .backspaceFast ? 0 : method.defaultDelays.settleUs),
            textUs: parseUInt32(fields["text_us"]) ?? (method == .backspaceFast ? 0 : method.defaultDelays.textUs)
        )
        // If method is backspaceFast and no delay keys at all, force zero (MVP default).
        let resolvedDelays: DelayPreset
        if method == .backspaceFast,
           fields["backspace_us"] == nil,
           fields["settle_us"] == nil,
           fields["text_us"] == nil {
            resolvedDelays = .zero
        } else {
            resolvedDelays = delays
        }

        let engine = parseEngineMethod(fields["engine_method"])
        let bundleId = fields["bundle_id"]

        return InjectionProfile(
            bundleId: bundleId,
            enabled: enabled,
            engineMethod: engine,
            injectionMethod: method,
            delays: resolvedDelays
        )
    }

    private static func parseBool(_ raw: String?) -> Bool? {
        guard let raw = raw?.lowercased() else { return nil }
        switch raw {
        case "true", "1", "yes": return true
        case "false", "0", "no": return false
        default: return nil
        }
    }

    private static func parseUInt32(_ raw: String?) -> UInt32? {
        guard let raw else { return nil }
        return UInt32(raw)
    }

    private static func parseInjectionMethod(_ raw: String?) -> InjectionMethod? {
        guard let raw else { return nil }
        return InjectionMethod(rawValue: raw)
    }

    private static func parseEngineMethod(_ raw: String?) -> EngineMethodOverride? {
        guard let raw else { return nil }
        return EngineMethodOverride(rawValue: raw.lowercased())
    }
}
