// Dấu macOS — serial typing session for EventTap (P0 review + TG-00 fail-open).
// Map keys on `dau.typing`; EventTap callback waits only within a bounded budget.
// Prefer losing a compose over blocking system-wide keyboard.

import Foundation

/// Decision returned to the EventTap callback after a synchronous map step.
struct TypingSessionDecision: Equatable {
    /// Whether the original keyDown must be suppressed.
    var consumeOriginal: Bool
    /// Full bridge result (for tests / diagnostics; never log `text` in production).
    var result: BridgeResult
    /// True when an inject was scheduled or completed for this key (bs > 0 or non-empty text).
    var injectScheduled: Bool
    /// True when the callback budget expired before map/inject finished (fail-open pass).
    var timedOut: Bool

    init(
        consumeOriginal: Bool,
        result: BridgeResult,
        injectScheduled: Bool,
        timedOut: Bool = false
    ) {
        self.consumeOriginal = consumeOriginal
        self.result = result
        self.injectScheduled = injectScheduled
        self.timedOut = timedOut
    }

    static let passthrough = TypingSessionDecision(
        consumeOriginal: false,
        result: .passthrough,
        injectScheduled: false,
        timedOut: false
    )
}

/// Coarse duration bucket for telemetry (metadata only — no key codes / text).
enum TypingCallbackDurationBucket: String, Equatable, Sendable {
    case under1ms = "<1ms"
    case ms1to5 = "1-5ms"
    case ms5toBudget = "5-budget"
    case overBudget = "over-budget"

    static func bucket(nanoseconds: UInt64, budgetNanoseconds: UInt64) -> TypingCallbackDurationBucket {
        if nanoseconds >= budgetNanoseconds { return .overBudget }
        if nanoseconds < 1_000_000 { return .under1ms }
        if nanoseconds < 5_000_000 { return .ms1to5 }
        return .ms5toBudget
    }
}

/// Owns bridge pipeline + injector on a private serial queue.
///
/// Hot-path contract (TG-00):
/// 1. EN / typing-off / pure boundary keys return passthrough **before** `dau.typing`,
///    `SyntheticPostAccess`, AX, or injector.
/// 2. VI map (+ optional zero-delay inject) runs on the session queue with a **bounded wait**.
/// 3. On timeout: pass original, invalidate generation — no late inject / stale mutation.
/// 4. Never call `usleep` on the EventTap callback thread (non-zero delays stay async).
/// 5. Fail-open: if post access denied or zero-delay inject fails, do **not** consume the original key.
final class TypingSession {
    static let queueLabel = "dau.typing"
    /// Default EventTap wait budget for map + zero-delay inject (prefer pass over hang).
    static let defaultCallbackBudgetNanoseconds: UInt64 = 12_000_000 // 12 ms

    private let queue: DispatchQueue
    private let pipeline: MacKeyPipeline
    private let injector: TextInjector
    private let callbackBudgetNanoseconds: UInt64

    private let stateLock = NSLock()
    /// Hot-path mirror of `typingEnabled` (readable without queue.sync).
    private var typingEnabledCached: Bool = true
    /// Live work generation; timeout bumps this so late work skips inject/mutation.
    private var liveGeneration: UInt64 = 0

    /// Injection method for async inject (profile layer sets this; queue-owned).
    private var injectionMethod: InjectionMethod = .backspaceFast
    /// Delays applied only on the inject path (never during pure map when delays > 0).
    private var delays: DelayPreset = .zero

    /// When false, keys pass through and compose is cleared (EN / blocked / per-app off).
    private var typingEnabled: Bool = true

    /// Optional hook after inject (tests / metadata). Not invoked with text content.
    /// Called for both sync (zero-delay) and async inject paths.
    var onInjectCompleted: ((Result<Void, InjectionError>) -> Void)?

    /// Metadata-only telemetry (duration bucket, generation, phase). Never key/text/clipboard.
    var onCallbackTelemetry: ((String) -> Void)?

    /// Test hook: runs on the session queue at the start of bounded work (before access/map).
    var testQueueWorkBegan: (() -> Void)?
    /// Test hook: runs on the session queue immediately before zero-delay inject.
    var testBeforeZeroDelayInject: (() -> Void)?

    init(
        pipeline: MacKeyPipeline = MacKeyPipeline(),
        injector: TextInjector = TextInjector(),
        queue: DispatchQueue = DispatchQueue(label: TypingSession.queueLabel),
        callbackBudgetNanoseconds: UInt64 = TypingSession.defaultCallbackBudgetNanoseconds
    ) {
        self.pipeline = pipeline
        self.injector = injector
        self.queue = queue
        self.callbackBudgetNanoseconds = callbackBudgetNanoseconds
    }

    var provisionalLength: Int {
        queue.sync { pipeline.provisionalLength }
    }

    // MARK: - EventTap entry

    /// Bounded wait for consume/pass. Prefer system keyboard availability over compose fidelity.
    @discardableResult
    func handleKey(_ key: ClassifiedKey) -> TypingSessionDecision {
        // ── Early fail-open (no queue / SyntheticPostAccess / AX / injector) ──
        if !isTypingEnabledCached() {
            scheduleComposeResetAsync()
            emitTelemetry(phase: "early-en-off", generation: currentGeneration(), nanoseconds: 0, timedOut: false)
            return .passthrough
        }

        // Pure boundary / shortcut: always pass original; clear compose off the hot wait path.
        switch key.kind {
        case .modifier, .other:
            scheduleComposeResetAsync()
            emitTelemetry(phase: "early-boundary", generation: currentGeneration(), nanoseconds: 0, timedOut: false)
            return .passthrough
        default:
            break
        }

        let generation = beginGeneration()
        let box = DecisionBox()
        let group = DispatchGroup()
        group.enter()
        queue.async { [weak self] in
            defer { group.leave() }
            guard let self else { return }
            self.testQueueWorkBegan?()
            guard self.isGenerationLive(generation) else {
                // Timed out while waiting to run: drop any in-flight compose mutation.
                self.pipeline.resetCompose()
                return
            }
            self.performBoundedWork(key: key, generation: generation, box: box)
        }

        let start = DispatchTime.now().uptimeNanoseconds
        let waitResult = group.wait(
            timeout: .now() + .nanoseconds(Int(callbackBudgetNanoseconds))
        )
        let elapsed = DispatchTime.now().uptimeNanoseconds &- start

        if waitResult == .timedOut {
            // Quarantine generation so late work cannot inject or keep stale core state.
            invalidateGeneration(generation)
            scheduleComposeResetAsync()
            emitTelemetry(phase: "timeout", generation: generation, nanoseconds: elapsed, timedOut: true)
            fputs(
                "[dau] typing fail-open: callback budget exceeded gen=\(generation) " +
                    "bucket=\(TypingCallbackDurationBucket.bucket(nanoseconds: elapsed, budgetNanoseconds: callbackBudgetNanoseconds).rawValue)\n",
                stderr
            )
            return TypingSessionDecision(
                consumeOriginal: false,
                result: .passthrough,
                injectScheduled: false,
                timedOut: true
            )
        }

        let decision = box.decision
        if let completed = box.completedSync {
            onInjectCompleted?(completed)
        } else if let payload = box.asyncInject {
            let method = payload.method
            let delays = payload.delays
            let gen = generation
            queue.async { [weak self] in
                guard let self else { return }
                guard self.isGenerationLive(gen) else {
                    self.pipeline.resetCompose()
                    return
                }
                let injectResult = self.injector.inject(
                    backspace: payload.backspace,
                    text: payload.text,
                    method: method,
                    delays: delays
                )
                if case .failure = injectResult {
                    self.pipeline.clearProvisionalOnly()
                    self.pipeline.resetCompose()
                }
                self.onInjectCompleted?(injectResult)
            }
        }

        emitTelemetry(
            phase: decision.injectScheduled ? "map-inject" : "map",
            generation: generation,
            nanoseconds: elapsed,
            timedOut: false
        )
        return decision
    }

    /// Map-only (no inject). Used by unit tests and by callers that inject manually.
    func mapKey(_ key: ClassifiedKey) -> BridgeResult {
        queue.sync {
            mapOnQueue(key).result
        }
    }

    /// Clear compose on the session queue (focus change, EN toggle, tap restart).
    func resetCompose() {
        queue.sync {
            pipeline.resetCompose()
        }
    }

    /// Async clear — used when the hot path must not wait on `dau.typing`.
    func resetComposeAsync() {
        scheduleComposeResetAsync()
    }

    // MARK: - Queue-safe configuration (AppDelegate / tests)

    /// Hot-path profile + typing master switch. All fields applied atomically on the session queue.
    func applyRuntimeSettings(
        typingEnabled: Bool,
        injectionMethod: InjectionMethod,
        delays: DelayPreset,
        engineMethod: DauMethod
    ) {
        stateLock.lock()
        typingEnabledCached = typingEnabled
        stateLock.unlock()
        queue.sync {
            self.typingEnabled = typingEnabled
            self.injectionMethod = injectionMethod
            self.delays = delays
            self.pipeline.core.setMethod(engineMethod)
        }
    }

    func setTypingEnabled(_ enabled: Bool) {
        stateLock.lock()
        typingEnabledCached = enabled
        stateLock.unlock()
        queue.sync {
            self.typingEnabled = enabled
        }
    }

    func setInjectionMethod(_ method: InjectionMethod) {
        queue.sync {
            self.injectionMethod = method
        }
    }

    func setDelays(_ delays: DelayPreset) {
        queue.sync {
            self.delays = delays
        }
    }

    func setEnabled(_ enabled: Bool) {
        queue.sync {
            pipeline.core.setEnabled(enabled)
        }
    }

    func setMethod(_ method: DauMethod) {
        queue.sync {
            pipeline.core.setMethod(method)
        }
    }

    func setAutoCapitalize(_ on: Bool) {
        queue.sync {
            pipeline.core.setAutoCapitalize(on)
        }
    }

    func setAutoRestore(_ on: Bool) {
        queue.sync {
            pipeline.core.setAutoRestore(on)
        }
    }

    /// Test/diagnostic read of current inject method (queue-safe).
    func currentInjectionMethod() -> InjectionMethod {
        queue.sync { injectionMethod }
    }

    func currentDelays() -> DelayPreset {
        queue.sync { delays }
    }

    func isTypingEnabled() -> Bool {
        queue.sync { typingEnabled }
    }

    /// Hot-path read without entering `dau.typing`.
    func isTypingEnabledCached() -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return typingEnabledCached
    }

    // MARK: - Bounded work (session queue)

    private func performBoundedWork(key: ClassifiedKey, generation: UInt64, box: DecisionBox) {
        // Post-access from cached snapshot only (never CGRequest on this path).
        if !SyntheticPostAccess.isGranted {
            if pipeline.provisionalLength > 0 {
                pipeline.resetCompose()
            }
            box.decision = .passthrough
            fputs("[dau] typing fail-open: post access denied (pass original)\n", stderr)
            return
        }

        guard isGenerationLive(generation) else {
            pipeline.resetCompose()
            return
        }

        var decision = mapOnQueue(key)
        let method = injectionMethod
        let delays = delays

        guard decision.injectScheduled else {
            box.decision = decision
            return
        }

        guard isGenerationLive(generation) else {
            // Map ran but generation was quarantined — drop stale core mutation.
            pipeline.resetCompose()
            box.decision = .passthrough
            return
        }

        let needsSleep =
            delays.backspaceUs > 0 || delays.settleUs > 0 || delays.textUs > 0

        if needsSleep {
            box.asyncInject = AsyncInjectPayload(
                backspace: decision.result.backspace,
                text: decision.result.text,
                method: method,
                delays: delays
            )
            box.decision = decision
            return
        }

        // Zero delay: inject only if generation still live (no late inject after timeout).
        testBeforeZeroDelayInject?()
        guard isGenerationLive(generation) else {
            pipeline.resetCompose()
            box.decision = .passthrough
            return
        }

        let injectResult = injector.inject(
            backspace: decision.result.backspace,
            text: decision.result.text,
            method: method,
            delays: delays
        )

        guard isGenerationLive(generation) else {
            // Quarantined during inject: clear compose; do not consume (callback already may have passed).
            pipeline.clearProvisionalOnly()
            pipeline.resetCompose()
            box.decision = .passthrough
            box.completedSync = injectResult
            return
        }

        box.completedSync = injectResult
        if case .failure = injectResult {
            failOpenAfterInjectFailure(&decision)
            fputs("[dau] typing fail-open: zero-delay inject failed (pass original)\n", stderr)
        }
        box.decision = decision
    }

    // MARK: - Queue-bound map

    private func mapOnQueue(_ key: ClassifiedKey) -> TypingSessionDecision {
        if !typingEnabled {
            if pipeline.provisionalLength > 0 {
                pipeline.resetCompose()
            }
            return .passthrough
        }

        let result = pipeline.handleClassified(key)
        let needsInject = result.backspace > 0 || !result.text.isEmpty
        return TypingSessionDecision(
            consumeOriginal: result.consumeOriginal,
            result: result,
            injectScheduled: needsInject
        )
    }

    /// After zero-delay inject failure: clear compose and force-pass original key (no dead key).
    private func failOpenAfterInjectFailure(_ decision: inout TypingSessionDecision) {
        pipeline.clearProvisionalOnly()
        pipeline.resetCompose()
        decision.consumeOriginal = false
        // Keep injectScheduled true so tests know inject was attempted; original is still passed.
        decision.result = BridgeResult(
            backspace: decision.result.backspace,
            text: decision.result.text,
            consumeOriginal: false,
            capitalizeNext: decision.result.capitalizeNext
        )
    }

    // MARK: - Generation / early path helpers

    private func beginGeneration() -> UInt64 {
        stateLock.lock()
        liveGeneration &+= 1
        let gen = liveGeneration
        stateLock.unlock()
        return gen
    }

    private func currentGeneration() -> UInt64 {
        stateLock.lock()
        defer { stateLock.unlock() }
        return liveGeneration
    }

    private func isGenerationLive(_ generation: UInt64) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return liveGeneration == generation
    }

    private func invalidateGeneration(_ generation: UInt64) {
        stateLock.lock()
        if liveGeneration == generation {
            liveGeneration &+= 1
        }
        stateLock.unlock()
    }

    private func scheduleComposeResetAsync() {
        queue.async { [weak self] in
            self?.pipeline.resetCompose()
        }
    }

    private func emitTelemetry(
        phase: String,
        generation: UInt64,
        nanoseconds: UInt64,
        timedOut: Bool
    ) {
        let bucket = TypingCallbackDurationBucket.bucket(
            nanoseconds: nanoseconds,
            budgetNanoseconds: callbackBudgetNanoseconds
        )
        // Metadata only: phase, generation, duration bucket. No key codes / text / clipboard.
        let line =
            "phase=\(phase) gen=\(generation) bucket=\(bucket.rawValue) timedOut=\(timedOut)"
        onCallbackTelemetry?(line)
    }

    // MARK: - Work-result box (filled on session queue)

    private final class DecisionBox {
        var decision = TypingSessionDecision.passthrough
        var completedSync: Result<Void, InjectionError>?
        var asyncInject: AsyncInjectPayload?
    }

    private struct AsyncInjectPayload {
        var backspace: Int
        var text: String
        var method: InjectionMethod
        var delays: DelayPreset
    }
}
