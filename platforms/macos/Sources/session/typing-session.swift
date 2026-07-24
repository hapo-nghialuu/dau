// Dấu macOS — serial typing session for EventTap (P0 review).
// Map keys on `dau.typing` via queue.sync; inject async so the tap callback never usleeps.
// Dead-key guard: never consume original unless synthetic inject is ready (or already ran).

import Foundation

/// Decision returned to the EventTap callback after a synchronous map step.
struct TypingSessionDecision: Equatable {
    /// Whether the original keyDown must be suppressed.
    var consumeOriginal: Bool
    /// Full bridge result (for tests / diagnostics; never log `text` in production).
    var result: BridgeResult
    /// True when an inject was scheduled or completed for this key (bs > 0 or non-empty text).
    var injectScheduled: Bool
}

/// Owns bridge pipeline + injector on a private serial queue.
///
/// Hot-path contract (P0):
/// 1. `queue.sync` — pipeline map only when delays may sleep; when delays are zero, inject also runs sync.
/// 2. If inject needed and delays non-zero — `queue.async` — `TextInjector.inject` (delays only here).
/// 3. Never call `usleep` on the EventTap callback thread (non-zero delays stay async).
/// 4. Fail-open: if post access denied or zero-delay inject fails, do **not** consume the original key.
final class TypingSession {
    static let queueLabel = "dau.typing"

    private let queue: DispatchQueue
    private let pipeline: MacKeyPipeline
    private let injector: TextInjector

    /// Injection method for async inject (profile layer sets this; queue-owned).
    private var injectionMethod: InjectionMethod = .backspaceFast
    /// Delays applied only on the inject path (never during pure map when delays > 0).
    private var delays: DelayPreset = .zero

    /// When false, keys pass through and compose is cleared (EN / blocked / per-app off).
    private var typingEnabled: Bool = true

    /// Optional hook after inject (tests / metadata). Not invoked with text content.
    /// Called for both sync (zero-delay) and async inject paths.
    var onInjectCompleted: ((Result<Void, InjectionError>) -> Void)?

    init(
        pipeline: MacKeyPipeline = MacKeyPipeline(),
        injector: TextInjector = TextInjector(),
        queue: DispatchQueue = DispatchQueue(label: TypingSession.queueLabel)
    ) {
        self.pipeline = pipeline
        self.injector = injector
        self.queue = queue
    }

    var provisionalLength: Int {
        queue.sync { pipeline.provisionalLength }
    }

    // MARK: - EventTap entry

    /// Synchronous for consume/pass; schedules inject asynchronously when delays are non-zero.
    /// Zero-delay inject runs inside the session queue sync so fail-open can still pass the original key.
    /// Safe to call from the CGEventTap callback thread.
    @discardableResult
    func handleKey(_ key: ClassifiedKey) -> TypingSessionDecision {
        var decision = TypingSessionDecision(
            consumeOriginal: false,
            result: .passthrough,
            injectScheduled: false
        )
        // Snapshot inject params inside the same sync as map so AppDelegate profile
        // updates cannot race mid-decision.
        var method = InjectionMethod.backspaceFast
        var delays = DelayPreset.zero
        var injectNow: (backspace: Int, text: String)?
        var completedSync: Result<Void, InjectionError>?

        queue.sync {
            // Hard gate: no synthetic posts → never enter consume path (dead-key prevent).
            if !SyntheticPostAccess.isGranted {
                if self.pipeline.provisionalLength > 0 {
                    self.pipeline.resetCompose()
                }
                decision = TypingSessionDecision(
                    consumeOriginal: false,
                    result: .passthrough,
                    injectScheduled: false
                )
                fputs("[dau] typing fail-open: post access denied (pass original)\n", stderr)
                return
            }

            decision = self.mapOnQueue(key)
            method = self.injectionMethod
            delays = self.delays

            guard decision.injectScheduled else { return }

            let needsSleep =
                delays.backspaceUs > 0 || delays.settleUs > 0 || delays.textUs > 0

            if needsSleep {
                // Keep inject off the EventTap thread (usleep allowed only async).
                injectNow = (decision.result.backspace, decision.result.text)
                return
            }

            // Zero delay: inject before returning so we can fail-open on sink/post failure.
            // EventTap still waits on handleKey → posts complete before original is suppressed.
            let injectResult = self.injector.inject(
                backspace: decision.result.backspace,
                text: decision.result.text,
                method: method,
                delays: delays
            )
            completedSync = injectResult
            if case .failure = injectResult {
                self.failOpenAfterInjectFailure(&decision)
                fputs("[dau] typing fail-open: zero-delay inject failed (pass original)\n", stderr)
            }
        }

        if let completedSync {
            onInjectCompleted?(completedSync)
            return decision
        }

        if let payload = injectNow {
            let method = method
            let delays = delays
            queue.async { [weak self] in
                guard let self else { return }
                let injectResult = self.injector.inject(
                    backspace: payload.backspace,
                    text: payload.text,
                    method: method,
                    delays: delays
                )
                if case .failure = injectResult {
                    // Already consumed: clear compose so next keys are not stuck on stale provisional.
                    self.pipeline.clearProvisionalOnly()
                    self.pipeline.resetCompose()
                }
                self.onInjectCompleted?(injectResult)
            }
        }

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

    // MARK: - Queue-safe configuration (AppDelegate / tests)

    /// Hot-path profile + typing master switch. All fields applied atomically on the session queue.
    func applyRuntimeSettings(
        typingEnabled: Bool,
        injectionMethod: InjectionMethod,
        delays: DelayPreset,
        engineMethod: DauMethod
    ) {
        queue.sync {
            self.typingEnabled = typingEnabled
            self.injectionMethod = injectionMethod
            self.delays = delays
            self.pipeline.core.setMethod(engineMethod)
        }
    }

    func setTypingEnabled(_ enabled: Bool) {
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

    // MARK: - Queue-bound map

    private func mapOnQueue(_ key: ClassifiedKey) -> TypingSessionDecision {
        if !typingEnabled {
            if pipeline.provisionalLength > 0 {
                pipeline.resetCompose()
            }
            return TypingSessionDecision(
                consumeOriginal: false,
                result: .passthrough,
                injectScheduled: false
            )
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
}
