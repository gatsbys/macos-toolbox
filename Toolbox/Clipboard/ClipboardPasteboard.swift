import AppKit
import Foundation

enum ClipboardAccess: Sendable, Equatable { case allowed, needsPermission, denied }

// AppKit's lazy pasteboard providers require a main-thread run loop. Keep only
// pasteboard IPC here; hashing, thumbnails and persistence run in ClipboardStore.
@MainActor
final class ClipboardPasteboard {
    private let name: String?
    private var gate: ClipboardCaptureGate?
    init(name: String? = nil) { self.name = name }
    private var pasteboard: NSPasteboard { name.map { NSPasteboard(name: .init($0)) } ?? .general }

    func access() -> ClipboardAccess {
        switch pasteboard.accessBehavior {
        case .alwaysAllow: .allowed
        case .alwaysDeny: .denied
        case .ask, .default: .needsPermission
        @unknown default: .needsPermission
        }
    }

    func resetBaseline() { gate = ClipboardCaptureGate(initialCount: pasteboard.changeCount) }

    func capture(sourceBundleID: String?, explicitRequest: Bool = false) throws -> ClipboardContent? {
        let board = pasteboard
        guard explicitRequest || access() == .allowed else { return nil }
        let count = board.changeCount
        if gate == nil { gate = ClipboardCaptureGate(initialCount: count); if !explicitRequest { return nil } }
        if !explicitRequest && gate?.shouldRead(changeCount: count) != true { return nil }
        gate?.ignoreOwnWrite(changeCount: count)
        // Inspect type identifiers before requesting any content from providers.
        guard let types = board.types, ClipboardContent.mayCapture(types: Set(types.map(\.rawValue)), sourceBundleID: sourceBundleID),
              let pasteboardItems = board.pasteboardItems else { return nil }
        var size = 0
        var items: [ClipboardPart] = []
        for item in pasteboardItems {
            guard Set(item.types.map(\.rawValue)).isDisjoint(with: ClipboardContent.ignoredTypes) else { return nil }
            var representations: [ClipboardRepresentation] = []
            let captureTypes = Set(ClipboardContent.captureTypes(from: item.types.map(\.rawValue)))
            for type in item.types where captureTypes.contains(type.rawValue) {
                guard let data = item.data(forType: type), !data.isEmpty else { continue }
                size += data.count
                guard size <= ClipboardContent.maximumCopyBytes else { throw ClipboardStoreError.tooLarge }
                representations.append(.init(type: type.rawValue, data: data))
            }
            if !representations.isEmpty { items.append(.init(representations: representations)) }
        }
        // If ownership changed while providers fulfilled data, discard a mixed snapshot.
        guard board.changeCount == count else { return nil }
        let content = ClipboardContent(items: items)
        return content.isEmpty ? nil : content
    }

    func copy(_ content: ClipboardContent) throws {
        guard !content.isEmpty else { throw ClipboardStoreError.missing }
        let items = content.items.map { part in
            let item = NSPasteboardItem()
            for rep in part.representations { item.setData(rep.data, forType: .init(rep.type)) }
            return item
        }
        let board = pasteboard
        board.clearContents()
        guard board.writeObjects(items) else { throw ClipboardStoreError.missing }
        if gate == nil { gate = ClipboardCaptureGate(initialCount: board.changeCount) }
        gate?.ignoreOwnWrite(changeCount: board.changeCount)
    }
}
