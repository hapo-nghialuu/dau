// Dấu macOS — serial typing session for EventTap (P0 review).
// Map keys on `dau.typing` via queue.sync; inject async so the tap callback never usleeps.

import Foundation

/// Decision returned to the EventTap callback after a synchronous map step.
struct TypingSessionDecision: Equatable {
    /// Whether the original keyDown must be suppressed.
    var consumeOriginal: Bool
    /// Full bridge result (for tests / diagnostics; never log `text` in production).
    var result: BridgeResult
    /// True when an async inject was scheduled (bs > 0 or non-empty text).
    var injectScheduled: Bool
}

/// Owns bridge pipeline + injector on a private serial queue.
///
/// Hot-path contract (P0):
/// 1. `queue.sync` — pipeline map only (no delays / no CGEvent sleep).
/// 2. If inject needed — `queue.async` — `TextInjector.inject` (delays allowed here only).
/// 3. Never call `usleep` on the EventTap callback thread.
final class TypingSession {
    static let queueLabel = "dau.typing"

    private let queue: DispatchQueue
    private let pipeline: MacKeyPipeline
    private let injector: TextInjector

    /// Injection method for async inject (profile layer sets this; queue-owned).
    private var injectionMethod: InjectionMethod = .backspaceFast
    /// Delays applied only on the async inject path (never during sync map).
    private var delays: DelayPreset = .zero

    /// When false, keys pass through and compose is cleared (EN / blocked / per-app off).
    private var typingEnabled: Bool = true

    /// Optional hook after async inject (tests / metadata). Not invoked with text content.
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

    /// Synchronous for consume/pass; schedules inject asynchronously when needed.
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

        queue.sync {
            decision = self.mapOnQueue(key)
            method = self.injectionMethod
            delays = self.delays
        }

        if decision.injectScheduled {
            let result = decision.result
            queue.async { [weak self] in
                guard let self else { return }
                let injectResult = self.injector.inject(
                    backspace: result.backspace,
                    text: result.text,
                    method: method,
                    delays: delays
                )
                if case .failure = injectResult {
                    // Keep bridge coherent if inject failed (already on session queue).
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
}
