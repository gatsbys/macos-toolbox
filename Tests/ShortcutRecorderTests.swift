import AppKit
import Carbon
import Foundation
import Testing
@testable import ToolboxCore

private func key(_ code: UInt16, flags: NSEvent.ModifierFlags, chars: String = "v", type: NSEvent.EventType = .keyDown, repeating: Bool = false) throws -> NSEvent {
    try #require(NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0,
                                 context: nil, characters: chars, charactersIgnoringModifiers: chars, isARepeat: repeating, keyCode: code))
}

@Test @MainActor func recordedShortcutPreservesPhysicalKeyAndModifiers() throws {
    let shortcut = try #require(ClipboardShortcut.from(key(11, flags: [.command, .shift], chars: "B")))
    #expect(shortcut.keyCode == 11)
    #expect(shortcut.modifiers == UInt32(cmdKey | shiftKey))
    #expect(shortcut.label == "⇧⌘B")
}

@Test @MainActor func recordedOptionShortcutUsesBaseCharacter() throws {
    let shortcut = try #require(ClipboardShortcut.from(key(9, flags: [.option], chars: "√")))
    #expect(shortcut.keyCode == 9)
    #expect(shortcut.label == "⌥V")
}

@Test @MainActor func recordedShortcutSupportsSpecialKeys() throws {
    #expect(ClipboardShortcut.from(try key(49, flags: [.control], chars: " "))?.label == "⌃␣")
    #expect(ClipboardShortcut.from(try key(123, flags: [.command], chars: ""))?.label == "⌘←")
    #expect(ClipboardShortcut.from(try key(100, flags: [.control, .shift], chars: ""))?.label == "⌃⇧F8")
}

@Test @MainActor func recordedShortcutRejectsTypingAndShiftOnly() throws {
    #expect(ClipboardShortcut.from(try key(9, flags: [])) == nil)
    #expect(ClipboardShortcut.from(try key(9, flags: [.shift])) == nil)
    #expect(ClipboardShortcut.from(try key(9, flags: [.capsLock])) == nil)
}

@Test @MainActor func recordedShortcutRejectsEscapeRepeatsAndKeyUp() throws {
    #expect(ClipboardShortcut.from(try key(53, flags: [.command], chars: "\u{1B}")) == nil)
    #expect(ClipboardShortcut.from(try key(9, flags: [.command], repeating: true)) == nil)
    #expect(ClipboardShortcut.from(try key(9, flags: [.command], type: .keyUp)) == nil)
}

@Test @MainActor func recordedShortcutIgnoresCapsLockAsGlobalModifier() throws {
    let shortcut = try #require(ClipboardShortcut.from(key(9, flags: [.command, .capsLock], chars: "V")))
    #expect(shortcut.modifiers == UInt32(cmdKey))
    #expect(shortcut.label == "⌘V")
}

@Test @MainActor func recordedShortcutPersistsWithoutChangingItsIdentity() throws {
    let original = try #require(ClipboardShortcut.from(key(11, flags: [.command, .option], chars: "B")))
    let saved = try JSONEncoder().encode(original)
    #expect(try JSONDecoder().decode(ClipboardShortcut.self, from: saved) == original)
}
