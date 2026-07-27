// Dấu macOS — global toggle hotkey.
// - Key + modifiers → Carbon RegisterEventHotKey
// - Modifier-only (e.g. ⌘⇧) → CGEventTap flagsChanged (Carbon cannot register mod-only)

import AppKit
import Carbon
import CoreGraphics
import Foundation

/// C callback for Carbon hotkey presses (must not be a Swift closure).
private func dauToggleHotkeyEventHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let userData, let event else {
        return OSStatus(eventNotHandledErr)
    }
    let registrar = Unmanaged<ToggleHotkeyRegistrar>.fromOpaque(userData).takeUnretainedValue()
    var hotKeyID = EventHotKeyID()
    let err = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard err == noErr,
          hotKeyID.signature == ToggleHotkeyRegistrar.signature,
          hotKeyID.id == ToggleHotkeyRegistrar.hotKeyIDValue else {
        return OSStatus(eventNotHandledErr)
    }
    DispatchQueue.main.async {
        registrar.fireHotkey()
    }
    return noErr
}

private func dauModifierChordTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent?,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let event, let refcon else {
        return event.map { Unmanaged.passUnretained($0) }
    }
    let registrar = Unmanaged<ToggleHotkeyRegistrar>.fromOpaque(refcon).takeUnretainedValue()
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let port = registrar.modifierTapPort {
            CGEvent.tapEnable(tap: port, enable: true)
        }
        return Unmanaged.passUnretained(event)
    }
    registrar.handleFlagsEvent(event)
    return Unmanaged.passUnretained(event)
}

/// Registers one system-wide hotkey that invokes `onHotkey` on the main thread.
final class ToggleHotkeyRegistrar {
    static let signature: OSType = 0x4441_5554 // 'DAUT'
    static let hotKeyIDValue: UInt32 = 1

    var onHotkey: (() -> Void)?

    /// True when Carbon hotkey or modifier-only tap is actively installed.
    private(set) var isRegistered = false
    /// True after a valid hotkey failed to install (AX/tap/Carbon). Cleared on success.
    private(set) var lastRegisterAttemptFailed = false
    /// Bumps only on successful install — used by tests to detect tear-down/recreate.
    private(set) var registrationGeneration: UInt = 0

    /// Unit-test override: when set, skips OS registration and forces this result.
    var testForceRegistrationResult: Bool?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var selfPointer: UnsafeMutableRawPointer?
    private var installedHandler = false

    /// Active modifier-only chord (nil when using Carbon key hotkey).
    private var modifierOnlyHotkey: ToggleHotkey?
    /// True after we have seen the exact chord down; fire once on first full match.
    private var modifierChordArmed = false
    private var lastModifierMatch = false
    /// Metadata for retry logs — never key content.
    private var lastRegisterKind: String = "none"

    fileprivate var modifierTapPort: CFMachPort?
    private var modifierRunLoopSource: CFRunLoopSource?

    deinit {
        unregister()
    }

    /// Replace the active global hotkey. Invalid hotkeys clear registration only.
    /// Always tears down first — use `registerIfNeeded` on recovery paths.
    func register(_ hotkey: ToggleHotkey) {
        clearHotKey()
        guard hotkey.isValid else { return }

        if hotkey.isModifierOnly {
            registerModifierOnly(hotkey)
        } else {
            registerCarbonKey(hotkey)
        }
    }

    /// Recovery-safe register: no-op when already registered (does not tear down live tap).
    @discardableResult
    func registerIfNeeded(_ hotkey: ToggleHotkey) -> Bool {
        if isRegistered {
            return true
        }
        let hadFailed = lastRegisterAttemptFailed
        register(hotkey)
        if isRegistered && hadFailed {
            // Metadata only — kind, not key content.
            fputs(
                "[dau] toggle hotkey retry succeeded kind=\(lastRegisterKind) gen=\(registrationGeneration)\n",
                stderr
            )
        }
        return isRegistered
    }

    /// Drop the hotkey only (e.g. while recording). Handler stays for re-register.
    func clearHotKey() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        stopModifierTap()
        modifierOnlyHotkey = nil
        modifierChordArmed = false
        lastModifierMatch = false
        isRegistered = false
    }

    /// Full teardown (app quit).
    func unregister() {
        clearHotKey()
        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
        installedHandler = false
        if let selfPointer {
            Unmanaged<ToggleHotkeyRegistrar>.fromOpaque(selfPointer).release()
            self.selfPointer = nil
        }
    }

    fileprivate func fireHotkey() {
        onHotkey?()
    }

    fileprivate func handleFlagsEvent(_ event: CGEvent) {
        guard let target = modifierOnlyHotkey else { return }
        let flags = event.flags
        let command = flags.contains(.maskCommand)
        let control = flags.contains(.maskControl)
        let option = flags.contains(.maskAlternate)
        let shift = flags.contains(.maskShift)
        let matches = target.matchesModifiers(
            command: command,
            control: control,
            option: option,
            shift: shift
        )
        // Fire once when chord becomes fully held (edge up on match).
        if matches && !lastModifierMatch {
            lastModifierMatch = true
            DispatchQueue.main.async { [weak self] in
                self?.fireHotkey()
            }
        } else if !matches {
            lastModifierMatch = false
        }
    }

    // MARK: - Carbon (key + modifiers)

    private func registerCarbonKey(_ hotkey: ToggleHotkey) {
        lastRegisterKind = "carbon"
        if let forced = testForceRegistrationResult {
            applyForcedRegistrationResult(forced, kind: "carbon")
            return
        }
        guard let code = hotkey.keyCode else {
            markRegistrationFailed(kind: "carbon", detail: "missing keyCode")
            return
        }
        installHandlerIfNeeded()

        var hotKeyID = EventHotKeyID(
            signature: Self.signature,
            id: Self.hotKeyIDValue
        )
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(code),
            hotkey.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        if status == noErr {
            hotKeyRef = ref
            markRegistrationSucceeded(kind: "carbon")
        } else {
            hotKeyRef = nil
            markRegistrationFailed(kind: "carbon", detail: "status=\(status)")
        }
    }

    // MARK: - Modifier-only (flagsChanged tap)

    private func registerModifierOnly(_ hotkey: ToggleHotkey) {
        lastRegisterKind = "modifierOnly"
        if let forced = testForceRegistrationResult {
            applyForcedRegistrationResult(forced, kind: "modifierOnly")
            if forced {
                modifierOnlyHotkey = hotkey
                lastModifierMatch = false
            }
            return
        }
        modifierOnlyHotkey = hotkey
        lastModifierMatch = false
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        let mask = CGEventMask(1) << CGEventType.flagsChanged.rawValue
            | CGEventMask(1) << CGEventType.tapDisabledByTimeout.rawValue
            | CGEventMask(1) << CGEventType.tapDisabledByUserInput.rawValue

        let locations: [CGEventTapLocation] = [.cgSessionEventTap, .cghidEventTap]
        var created: CFMachPort?
        for location in locations {
            if let port = CGEvent.tapCreate(
                tap: location,
                place: .headInsertEventTap,
                options: .listenOnly,
                eventsOfInterest: mask,
                callback: dauModifierChordTapCallback,
                userInfo: pointer
            ) {
                created = port
                break
            }
        }
        guard let port = created else {
            modifierOnlyHotkey = nil
            markRegistrationFailed(kind: "modifierOnly", detail: "tapCreate nil")
            return
        }
        modifierTapPort = port
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        modifierRunLoopSource = source
        if let source {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }
        CGEvent.tapEnable(tap: port, enable: true)
        markRegistrationSucceeded(kind: "modifierOnly")
        fputs("[dau] modifier-only hotkey registered \(hotkey.displayString)\n", stderr)
    }

    private func applyForcedRegistrationResult(_ forced: Bool, kind: String) {
        if forced {
            markRegistrationSucceeded(kind: kind)
        } else {
            markRegistrationFailed(kind: kind, detail: "testForce=false")
        }
    }

    private func markRegistrationSucceeded(kind: String) {
        lastRegisterKind = kind
        isRegistered = true
        lastRegisterAttemptFailed = false
        registrationGeneration &+= 1
    }

    private func markRegistrationFailed(kind: String, detail: String) {
        lastRegisterKind = kind
        isRegistered = false
        lastRegisterAttemptFailed = true
        // Metadata only — kind + detail, never key content.
        fputs("[dau] toggle hotkey register failed kind=\(kind) \(detail)\n", stderr)
    }

    private func stopModifierTap() {
        if let source = modifierRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            modifierRunLoopSource = nil
        }
        if let port = modifierTapPort {
            CGEvent.tapEnable(tap: port, enable: false)
            CFMachPortInvalidate(port)
            modifierTapPort = nil
        }
    }

    private func installHandlerIfNeeded() {
        guard !installedHandler else { return }
        let pointer = Unmanaged.passRetained(self).toOpaque()
        selfPointer = pointer

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        var ref: EventHandlerRef?
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            dauToggleHotkeyEventHandler,
            1,
            &eventType,
            pointer,
            &ref
        )
        if status == noErr {
            handlerRef = ref
            installedHandler = true
        } else {
            fputs("[dau] InstallEventHandler failed status=\(status)\n", stderr)
            Unmanaged<ToggleHotkeyRegistrar>.fromOpaque(pointer).release()
            selfPointer = nil
        }
    }
}

// MARK: - Recovery policy (AX poll / restart / wake)

/// Action for recovery-path hotkey ensure (not settings force-rebind).
enum ToggleHotkeyRecoveryAction: Equatable {
    /// Recording in progress — drop active hotkey so the new combo is not captured.
    case clear
    /// Already installed — do not call `register` (would tear down live tap).
    case noop
    /// Not registered — attempt install.
    case register
}

/// Pure policy used by AppDelegate recovery paths.
enum ToggleHotkeyRecoveryPolicy {
    static func action(isRecording: Bool, isRegistered: Bool) -> ToggleHotkeyRecoveryAction {
        if isRecording { return .clear }
        if isRegistered { return .noop }
        return .register
    }
}

extension ToggleHotkey {
    /// Carbon modifier mask for `RegisterEventHotKey`.
    var carbonModifiers: UInt32 {
        var mods: UInt32 = 0
        if command { mods |= UInt32(cmdKey) }
        if shift { mods |= UInt32(shiftKey) }
        if option { mods |= UInt32(optionKey) }
        if control { mods |= UInt32(controlKey) }
        return mods
    }
}
