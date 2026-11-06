import AppKit
import Carbon

struct ClipboardShortcut: Codable, Hashable, Sendable {
    var keyCode: UInt32 = 9 // V, virtual key code independent of keyboard layout.
    var modifiers: UInt32 = UInt32(cmdKey | shiftKey)
    var keyLabel = "V"
    var keyCaps: [String] {
        var keys: [String] = []
        if modifiers & UInt32(controlKey) != 0 { keys.append("⌃") }
        if modifiers & UInt32(optionKey) != 0 { keys.append("⌥") }
        if modifiers & UInt32(shiftKey) != 0 { keys.append("⇧") }
        if modifiers & UInt32(cmdKey) != 0 { keys.append("⌘") }
        return keys + [keyLabel]
    }
    var label: String { keyCaps.joined() }

    static func from(_ event: NSEvent) -> Self? {
        guard event.type == .keyDown, !event.isARepeat, event.keyCode != 53 else { return nil }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard !flags.intersection([.command, .control, .option]).isEmpty else { return nil }
        let specialKeys: [UInt16: String] = [36: "↩", 48: "⇥", 49: "␣", 51: "⌫", 76: "⌅", 117: "⌦",
            123: "←", 124: "→", 125: "↓", 126: "↑", 115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
            101: "F9", 109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15",
            106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20"]
        let label: String
        if let special = specialKeys[event.keyCode] { label = special }
        else {
            // Show the physical key, not the alternate character produced by Option.
            guard let chars = event.characters(byApplyingModifiers: []) ?? event.charactersIgnoringModifiers,
                  !chars.isEmpty, chars.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else { return nil }
            label = chars.uppercased()
        }
        var mask: UInt32 = 0
        if flags.contains(.command) { mask |= UInt32(cmdKey) }
        if flags.contains(.control) { mask |= UInt32(controlKey) }
        if flags.contains(.option) { mask |= UInt32(optionKey) }
        if flags.contains(.shift) { mask |= UInt32(shiftKey) }
        return Self(keyCode: UInt32(event.keyCode), modifiers: mask, keyLabel: label)
    }
}

@MainActor
final class ClipboardHotKey {
    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    var action: (() -> Void)?

    func register(_ shortcut: ClipboardShortcut) -> Bool {
        if eventHandler == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
                guard let context, let event else { return OSStatus(eventNotHandledErr) }
                var id = EventHotKeyID()
                guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                        MemoryLayout<EventHotKeyID>.size, nil, &id) == noErr,
                      id.signature == 0x54424348 else { return OSStatus(eventNotHandledErr) }
                let owner = Unmanaged<ClipboardHotKey>.fromOpaque(context).takeUnretainedValue()
                MainActor.assumeIsolated { owner.action?() }
                return noErr
            }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
            guard status == noErr else { return false }
        }
        if let hotKey { UnregisterEventHotKey(hotKey); self.hotKey = nil }
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, EventHotKeyID(signature: 0x54424348, id: 1),
                                         GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &ref)
        hotKey = ref
        guard status == noErr else {
            // A failed registration must not leave a handler that consumes
            // events belonging to a successful registration in this process.
            stop()
            return false
        }
        return true
    }

    func stop() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
        hotKey = nil; eventHandler = nil
    }
}
