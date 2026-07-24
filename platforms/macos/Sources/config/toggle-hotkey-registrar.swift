// Dấu macOS — global toggle hotkey via Carbon RegisterEventHotKey.
// Works while other apps are focused (menu closed). Original code.

import Carbon
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
        registrar.onHotkey?()
    }
    return noErr
}

/// Registers one system-wide hotkey that invokes `onHotkey` on the main thread.
final class ToggleHotkeyRegistrar {
    /// Four-char signature for `EventHotKeyID` (`DAUT` = Dấu Toggle).
    static let signature: OSType = 0x4441_5554 // 'DAUT'
    static let hotKeyIDValue: UInt32 = 1

    var onHotkey: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var selfPointer: UnsafeMutableRawPointer?
    private var installedHandler = false

    deinit {
        unregister()
    }

    /// Replace the active global hotkey. Invalid hotkeys clear registration only.
    func register(_ hotkey: ToggleHotkey) {
        clearHotKey()
        guard hotkey.isValid else { return }
        installHandlerIfNeeded()

        var hotKeyID = EventHotKeyID(
            signature: Self.signature,
            id: Self.hotKeyIDValue
        )
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(hotkey.keyCode),
            hotkey.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        if status == noErr {
            hotKeyRef = ref
        } else {
            // Conflict / OS rejection — keep previous cleared; caller may re-apply.
            fputs("[dau] RegisterEventHotKey failed status=\(status)\n", stderr)
            hotKeyRef = nil
        }
    }

    /// Drop the hotkey only (e.g. while recording). Handler stays for re-register.
    func clearHotKey() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
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
