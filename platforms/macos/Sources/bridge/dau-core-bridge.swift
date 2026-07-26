// Dấu macOS — RAII wrapper around the dau-core C ABI (`Engine*`).
// WP-02: lifecycle, process/break/escape/clear, flags, config, strategy.
// Uses `DauDeltaResult` from dau_core.h (display delta: backspace + insert).
//
// Delta contract layout derived from Gõ Nhanh (BSD-3-Clause,
// Copyright (c) 2025 Gõ Nhanh Contributors). See repo root NOTICE.

import Foundation

/// Swift-side view of one core call after UTF-32 → `String` conversion.
///
/// `text` is the **insert payload only** (not full preedit). Host should delete
/// `backspace` Unicode scalars first, then insert `text`.
struct CoreMappedResult: Equatable {
    var action: DauAction
    /// Unicode scalars to delete before inserting `text`.
    var backspace: Int
    /// Insert-only text from core `chars[0..count]`.
    var text: String
    var capitalizeNext: Bool

    static let empty = CoreMappedResult(
        action: DauAction_None,
        backspace: 0,
        text: "",
        capitalizeNext: false
    )
}

/// Owns a single `Engine*` and exposes null-safe wrappers over the current C ABI.
///
/// Incomplete C type `Engine` is imported as an opaque pointer; we never
/// dereference it in Swift.
final class DauCoreBridge {
    /// Opaque `Engine*` from `dau_engine_new`. Incomplete C struct → no typed pointer.
    private var engine: OpaquePointer?

    init(method: DauMethod = DauMethod_Telex) {
        // Incomplete C `struct Engine *` imports as OpaquePointer?.
        engine = dau_engine_new(method)
    }

    deinit {
        freeEngine()
    }

    /// Crate version string from `dau_version()` (static; never free).
    static var version: String {
        guard let cstr = dau_version() else { return "" }
        return String(cString: cstr)
    }

    var isAlive: Bool { engine != nil }

    // MARK: - Core operations

    func processChar(_ ch: UInt32, caps: Bool = false) -> CoreMappedResult {
        // Core accepts null; still short-circuit for a clean empty result.
        return Self.mapResult(dau_process_char(engineAsC, ch, caps))
    }

    func processChar(_ scalar: Unicode.Scalar, caps: Bool = false) -> CoreMappedResult {
        processChar(scalar.value, caps: caps)
    }

    func onBreak(_ brk: UInt32) -> CoreMappedResult {
        return Self.mapResult(dau_on_break(engineAsC, brk))
    }

    func onBreak(_ scalar: Unicode.Scalar) -> CoreMappedResult {
        onBreak(scalar.value)
    }

    func escape() -> CoreMappedResult {
        return Self.mapResult(dau_escape(engineAsC))
    }

    /// Backspace one display Unicode scalar while composing (`dau_backspace`).
    /// Returns `UpdatePreedit` with a delta (often backspace=1, empty insert), or
    /// `None` when the compose buffer is already empty (host should pass the key).
    func backspace() -> CoreMappedResult {
        return Self.mapResult(dau_backspace(engineAsC))
    }

    func clear() {
        dau_clear(engineAsC)
    }

    // MARK: - Flags / method

    func setEnabled(_ enabled: Bool) {
        dau_set_enabled(engineAsC, enabled)
    }

    func setMethod(_ method: DauMethod) {
        dau_set_method(engineAsC, method)
    }

    func setAutoCapitalize(_ on: Bool) {
        dau_set_auto_capitalize(engineAsC, on)
    }

    func setAutoRestore(_ on: Bool) {
        dau_set_auto_restore(engineAsC, on)
    }

    /// Replace shortcut table. `pairs` are (key, value) UTF-8 strings.
    func setShortcuts(_ pairs: [(String, String)]) {
        if pairs.isEmpty {
            dau_set_shortcuts(engineAsC, nil, 0)
            return
        }
        // Flat layout: key0, value0, key1, value1, ...
        var storage: [UnsafeMutablePointer<CChar>?] = []
        storage.reserveCapacity(pairs.count * 2)
        for (key, value) in pairs {
            storage.append(strdup(key))
            storage.append(strdup(value))
        }
        defer {
            for ptr in storage {
                if let ptr { free(ptr) }
            }
        }
        storage.withUnsafeBufferPointer { buf in
            guard let base = buf.baseAddress else {
                dau_set_shortcuts(engineAsC, nil, 0)
                return
            }
            base.withMemoryRebound(to: UnsafePointer<CChar>?.self, capacity: buf.count) { rebound in
                dau_set_shortcuts(engineAsC, rebound, pairs.count)
            }
        }
    }

    // MARK: - Config / strategy

    /// Load shipped then user TOML. Nil path skips that file.
    @discardableResult
    func loadConfig(shippedPath: String? = nil, userPath: String? = nil) -> Bool {
        return shippedPath.withCStringOrNil { shipped in
            userPath.withCStringOrNil { user in
                dau_load_config(engineAsC, shipped, user)
            }
        }
    }

    func strategyForApp(_ appId: String) -> DauStrategy {
        return appId.withCString { cstr in
            dau_strategy_for_app(engineAsC, cstr)
        }
    }

    // MARK: - UTF-32 helpers

    /// Convert core insert payload `chars[0..count]` into a Swift `String`.
    /// Invalid scalars and out-of-range `count` are skipped/clamped (null-safe).
    static func string(from result: DauDeltaResult) -> String {
        let count = min(Int(result.count), Int(DAU_DELTA_MAX_CHARS))
        guard count > 0 else { return "" }

        var copy = result
        return withUnsafeBytes(of: &copy.chars) { rawBuffer -> String in
            let words = rawBuffer.bindMemory(to: UInt32.self)
            var output = String.UnicodeScalarView()
            output.reserveCapacity(count)
            for i in 0..<count {
                if let scalar = Unicode.Scalar(words[i]) {
                    output.append(scalar)
                }
            }
            return String(output)
        }
    }

    static func mapResult(_ result: DauDeltaResult) -> CoreMappedResult {
        CoreMappedResult(
            action: result.action,
            backspace: Int(result.backspace),
            text: string(from: result),
            capitalizeNext: result.capitalize_next
        )
    }

    // MARK: - Private

    /// Bitcast opaque storage to the C API's incomplete `struct Engine *` parameter type.
    /// Uses `unsafeBitCast` because Swift cannot name the incomplete `Engine` type.
    private var engineAsC: OpaquePointer? { engine }

    private func freeEngine() {
        if let engine {
            dau_engine_free(engine)
            self.engine = nil
        }
    }
}

// MARK: - Optional path → C string

private extension Optional where Wrapped == String {
    func withCStringOrNil<R>(_ body: (UnsafePointer<CChar>?) -> R) -> R {
        switch self {
        case .none:
            return body(nil)
        case .some(let value):
            return value.withCString { body($0) }
        }
    }
}
