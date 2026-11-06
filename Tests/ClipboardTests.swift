import AppKit
import Carbon
import Foundation
import Testing
@testable import ToolboxCore

private func text(_ value: String) -> ClipboardContent {
    ClipboardContent(items: [.init(representations: [.init(type: "public.utf8-plain-text", data: Data(value.utf8))])])
}
private func directory() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("ToolboxClipboardTests-" + UUID().uuidString) }

@Test func clipboardClassifiesTextLinksImagesFilesAndPDF() {
    #expect(text("hola mundo").kind == .text)
    #expect(text("https://example.com/path").kind == .link)
    #expect(text("https://example.com\nmore text").kind == .text)
    for (type, kind) in [("public.png", ClipboardKind.image), ("public.tiff", .image), ("public.file-url", .files), ("com.adobe.pdf", .pdf)] {
        let content = ClipboardContent(items: [.init(representations: [.init(type: type, data: Data("file:///tmp/example.txt".utf8))])])
        #expect(content.kind == kind)
    }
}

@Test func clipboardSkipsConcealedTransientAndPasswordManagers() {
    for marker in ClipboardContent.ignoredTypes {
        #expect(!ClipboardContent.mayCapture(types: [marker, "public.utf8-plain-text"], sourceBundleID: "com.apple.TextEdit"))
    }
    #expect(!ClipboardContent.mayCapture(types: ["public.utf8-plain-text"], sourceBundleID: "com.1password.1password"))
    #expect(ClipboardContent.mayCapture(types: ["public.png"], sourceBundleID: "com.apple.Preview"))
    #expect(!ClipboardContent.mayCapture(types: ["some.private.format"], sourceBundleID: nil))
}

@Test func clipboardPrefersLosslessPNGOverDuplicateLargeTIFF() {
    #expect(ClipboardContent.captureTypes(from: ["public.png", "public.tiff", "public.utf8-plain-text"]) == ["public.png", "public.utf8-plain-text"])
    #expect(ClipboardContent.captureTypes(from: ["public.tiff"]) == ["public.tiff"])
}

@Test func clipboardFingerprintIncludesAllRepresentationsAndItemBoundaries() {
    let a = ClipboardContent(items: [.init(representations: [.init(type: "public.rtf", data: Data([1])), .init(type: "public.utf8-plain-text", data: Data([2]))])])
    let reordered = ClipboardContent(items: [.init(representations: a.items[0].representations.reversed())])
    let split = ClipboardContent(items: a.items[0].representations.map { .init(representations: [$0]) })
    #expect(a.fingerprint == reordered.fingerprint)
    #expect(a.fingerprint != split.fingerprint)
    #expect(text("abc").fingerprint != text("abcd").fingerprint)
}

@Test func clipboardGateIgnoresOwnCopiesAndInitialContents() {
    var gate = ClipboardCaptureGate(initialCount: 10)
    let initial = gate.shouldRead(changeCount: 10)
    let changed = gate.shouldRead(changeCount: 11)
    let duplicate = gate.shouldRead(changeCount: 11)
    #expect(!initial)
    #expect(changed)
    #expect(!duplicate)
    gate.ignoreOwnWrite(changeCount: 12)
    let own = gate.shouldRead(changeCount: 12)
    let next = gate.shouldRead(changeCount: 13)
    #expect(!own)
    #expect(next)
}

@Test func clipboardPersistsAndPromotesDuplicates() async throws {
    let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
    let store = ClipboardStore(directory: dir)
    let first = try await store.insert(text("primero"), sourceApp: "TextEdit", limit: 500, date: Date(timeIntervalSince1970: 1))
    let id = try #require(first.first?.id)
    _ = try await store.insert(text("segundo"), sourceApp: "Safari", limit: 500)
    let promoted = try await store.insert(text("primero"), sourceApp: "Finder", limit: 500, date: Date(timeIntervalSince1970: 3))
    #expect(promoted.count == 2)
    #expect(promoted.first?.id == id)
    #expect(promoted.first?.sourceApp == "Finder")
    let reopened = ClipboardStore(directory: dir)
    #expect(try await reopened.load() == promoted)
    #expect(try await reopened.content(for: id) == text("primero"))
}

@Test func clipboardLimitDeletesOldPayloadsAndAllowsSmallerLimits() async throws {
    let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
    let store = ClipboardStore(directory: dir)
    let first = try await store.insert(text("uno"), sourceApp: nil, limit: 2)
    let removedID = try #require(first.first?.id)
    _ = try await store.insert(text("dos"), sourceApp: nil, limit: 2)
    let last = try await store.insert(text("tres"), sourceApp: nil, limit: 2)
    #expect(last.count == 2)
    #expect(last.map(\.preview) == ["tres", "dos"])
    #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent(removedID.uuidString + ".json").path))
    #expect(try await store.setLimit(1).count == 1)
}

@Test func clipboardClearRemovesPayloadsAndIndexPersistsEmpty() async throws {
    let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
    let store = ClipboardStore(directory: dir)
    let entries = try await store.insert(text("copiado"), sourceApp: nil, limit: 500)
    let id = try #require(entries.first?.id)
    #expect(try await store.clear().isEmpty)
    #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent(id.uuidString + ".json").path))
    let reopened = ClipboardStore(directory: dir)
    #expect(try await reopened.load().isEmpty)
}

@Test func clipboardRejectsOversizedCopiesWithoutLosingHistory() async throws {
    let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
    let store = ClipboardStore(directory: dir, budget: 500)
    _ = try await store.insert(text("guardado"), sourceApp: nil, limit: 500)
    await #expect(throws: ClipboardStoreError.self) { try await store.insert(text(String(repeating: "a", count: 1_000)), sourceApp: nil, limit: 500) }
    #expect(try await store.load().map(\.preview) == ["guardado"])
}

@Test func clipboardBudgetEvictsOldestEntries() async throws {
    let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
    let store = ClipboardStore(directory: dir, budget: 550)
    for index in 0..<6 { _ = try await store.insert(text(String(repeating: "a", count: 90) + String(index)), sourceApp: nil, limit: 500) }
    let entries = try await store.load()
    #expect(entries.count < 6)
    #expect(entries.reduce(0) { $0 + $1.byteCount } <= 550)
    #expect(entries.first?.preview.hasSuffix("5") == true)
}

@Test func clipboardCorruptIndexIsNotOverwritten() async throws {
    let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let original = Data("corrupted index".utf8)
    try original.write(to: dir.appendingPathComponent("index.json"))
    let store = ClipboardStore(directory: dir)
    await #expect(throws: ClipboardStoreError.self) { try await store.load() }
    await #expect(throws: ClipboardStoreError.self) { try await store.insert(text("no sobrescribir"), sourceApp: nil, limit: 500) }
    #expect(try Data(contentsOf: dir.appendingPathComponent("index.json")) == original)
}

@Test func clipboardSearchMatchesTextAppAndTypeFilter() async throws {
    let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
    let store = ClipboardStore(directory: dir)
    let entries = try await store.insert(text("Información importante"), sourceApp: "TextEdit", limit: 500)
    let entry = try #require(entries.first)
    #expect(entry.matches("informacion", kind: .text))
    #expect(entry.matches("textedit", kind: nil))
    #expect(!entry.matches("importante", kind: .image))
}

@Test @MainActor func clipboardNamedPasteboardRoundTripsFormattedTextAndIgnoresOwnWrite() async throws {
    let name = "ToolboxTests-" + UUID().uuidString
    let board = ClipboardPasteboard(name: name)
    let content = ClipboardContent(items: [.init(representations: [.init(type: "public.utf8-plain-text", data: Data("Hola".utf8)), .init(type: "public.rtf", data: Data("{\\rtf1 Hola}".utf8))])])
    try board.copy(content)
    #expect(try board.capture(sourceBundleID: nil) == nil)
    let copied = try board.capture(sourceBundleID: nil, explicitRequest: true)
    // AppKit also supplies a UTF-16 conversion. Preserve all original formats
    // without requiring the pasteboard to expose exactly the same type list.
    for expected in content.items[0].representations {
        #expect(copied?.items.first?.representations.contains(expected) == true)
    }
}

@Test func clipboardImageCreatesThumbnailAndSurvivesRestart() async throws {
    let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 8, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
    let png = try #require(bitmap.representation(using: .png, properties: [:]))
    let content = ClipboardContent(items: [.init(representations: [.init(type: "public.png", data: png)])])
    let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
    let store = ClipboardStore(directory: dir)
    let entries = try await store.insert(content, sourceApp: "Preview", limit: 500)
    let entry = try #require(entries.first)
    #expect(entry.hasThumbnail)
    #expect(await store.thumbnail(for: entry.id) != nil)
    let reopened = ClipboardStore(directory: dir)
    #expect(try await reopened.content(for: entry.id) == content)
}

@Test func clipboardShortcutLabelsReflectModifiers() {
    #expect(ClipboardShortcut().label == "⇧⌘V")
    #expect(ClipboardShortcut(keyCode: 9, modifiers: UInt32(controlKey | optionKey), keyLabel: "V").label == "⌃⌥V")
}

@Test func clipboardDuplicateSaveFailureRollsBackMemory() async throws {
    let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
    let store = ClipboardStore(directory: dir)
    _ = try await store.insert(text("uno"), sourceApp: "Original", limit: 500)
    let original = try await store.insert(text("dos"), sourceApp: nil, limit: 500)
    let index = dir.appendingPathComponent("index.json")
    try FileManager.default.removeItem(at: index)
    try FileManager.default.createDirectory(at: index, withIntermediateDirectories: false)
    await #expect(throws: (any Error).self) { try await store.insert(text("uno"), sourceApp: "Otro", limit: 500) }
    #expect(try await store.load() == original)
}

@Test @MainActor func clipboardHotKeyRegistersExclusivelyAndDispatchesItsEvent() throws {
    let shortcut = ClipboardShortcut(keyCode: 90, modifiers: UInt32(cmdKey | controlKey | shiftKey), keyLabel: "F20")
    let hotKey = ClipboardHotKey()
    let conflict = ClipboardHotKey()
    defer { conflict.stop(); hotKey.stop() }
    var triggered = 0
    hotKey.action = { triggered += 1 }
    #expect(hotKey.register(shortcut))
    #expect(!conflict.register(shortcut))
    var event: EventRef?
    #expect(CreateEvent(nil, OSType(kEventClassKeyboard), UInt32(kEventHotKeyPressed), GetCurrentEventTime(), 0, &event) == noErr)
    let actual = try #require(event)
    var id = EventHotKeyID(signature: 0x54424348, id: 1)
    #expect(SetEventParameter(actual, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), MemoryLayout<EventHotKeyID>.size, &id) == noErr)
    #expect(SendEventToEventTarget(actual, GetApplicationEventTarget()) == noErr)
    #expect(triggered == 1)
}
