import Carbon
import Combine
import Foundation

struct GlobalShortcutOption: Identifiable, Hashable {
    let id: String
    let keyCode: UInt32
    let modifiers: UInt32
    let displayName: String

    static let all: [GlobalShortcutOption] = [
        GlobalShortcutOption(
            id: "control-option-command-e",
            keyCode: UInt32(kVK_ANSI_E),
            modifiers: UInt32(controlKey | optionKey | cmdKey),
            displayName: "⌃⌥⌘E"
        ),
        GlobalShortcutOption(
            id: "control-option-command-space",
            keyCode: UInt32(kVK_Space),
            modifiers: UInt32(controlKey | optionKey | cmdKey),
            displayName: "⌃⌥⌘Space"
        ),
        GlobalShortcutOption(
            id: "control-option-command-k",
            keyCode: UInt32(kVK_ANSI_K),
            modifiers: UInt32(controlKey | optionKey | cmdKey),
            displayName: "⌃⌥⌘K"
        ),
        GlobalShortcutOption(
            id: "control-option-command-l",
            keyCode: UInt32(kVK_ANSI_L),
            modifiers: UInt32(controlKey | optionKey | cmdKey),
            displayName: "⌃⌥⌘L"
        ),
        GlobalShortcutOption(
            id: "disabled",
            keyCode: UInt32.max,
            modifiers: 0,
            displayName: "Off"
        )
    ]

    static let disabled = all[4]
    static let defaultEnabled = disabled
    static let defaultGlobalLock = disabled

    static func option(for id: String, fallback: GlobalShortcutOption) -> GlobalShortcutOption {
        all.first(where: { $0.id == id }) ?? fallback
    }
}

private func globalHotKeyEventHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }

    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr else { return status }

    let manager = Unmanaged<GlobalHotKeyManager>.fromOpaque(userData).takeUnretainedValue()
    Task { @MainActor in
        manager.performAction(for: hotKeyID.id)
    }
    return noErr
}

@MainActor
final class GlobalHotKeyManager: ObservableObject {
    static let shared = GlobalHotKeyManager()

    private let signature: OSType = 0x49535754 // ISWT
    private var eventHandler: EventHandlerRef?
    private var hotKeys: [UInt32: EventHotKeyRef] = [:]
    private var actions: [UInt32: () -> Void] = [:]
    private var enabledShortcut = GlobalShortcutOption.defaultEnabled
    private var globalLockShortcut = GlobalShortcutOption.defaultGlobalLock
    @Published private(set) var registrationFailed = false

    private init() {}

    func start(toggleEnabled: @escaping () -> Void, toggleGlobalLock: @escaping () -> Void) {
        stop()
        actions = [1: toggleEnabled, 2: toggleGlobalLock]
        enabledShortcut = RuleStore.shared.enabledShortcut
        globalLockShortcut = RuleStore.shared.globalLockShortcut

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            globalHotKeyEventHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )

        guard status == noErr, eventHandler != nil else {
            registrationFailed = true
            return
        }

        registerConfiguredShortcuts()
    }

    func updateShortcuts(enabled: GlobalShortcutOption, globalLock: GlobalShortcutOption) {
        enabledShortcut = enabled
        globalLockShortcut = globalLock
        guard eventHandler != nil else { return }
        hotKeys.values.forEach { UnregisterEventHotKey($0) }
        hotKeys.removeAll()
        registerConfiguredShortcuts()
    }

    func stop() {
        hotKeys.values.forEach { UnregisterEventHotKey($0) }
        hotKeys.removeAll()
        actions.removeAll()
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    fileprivate func performAction(for id: UInt32) {
        guard let action = actions[id] else { return }
        action()
    }

    private func registerConfiguredShortcuts() {
        registrationFailed = false
        if enabledShortcut.keyCode != UInt32.max {
            register(id: 1, keyCode: enabledShortcut.keyCode, modifiers: enabledShortcut.modifiers)
        }
        if globalLockShortcut.keyCode != UInt32.max,
           globalLockShortcut != enabledShortcut {
            register(id: 2, keyCode: globalLockShortcut.keyCode, modifiers: globalLockShortcut.modifiers)
        }
    }

    private func register(id: UInt32, keyCode: UInt32, modifiers: UInt32) {
        var reference: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: signature, id: id)
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &reference
        )
        if status == noErr, let reference {
            hotKeys[id] = reference
        } else {
            registrationFailed = true
            NSLog("Unable to register global shortcut %u: %d", id, status)
        }
    }
}
