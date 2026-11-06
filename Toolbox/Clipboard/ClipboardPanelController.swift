import AppKit
import SwiftUI

private final class HistoryPanel: NSPanel {
    var routeKey: ((NSEvent) -> Bool)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, routeKey?(event) == true { return }
        super.sendEvent(event)
    }
}

@MainActor
final class ClipboardPanelController: NSObject, NSWindowDelegate {
    private let tool: ClipboardHistoryTool
    private var panel: HistoryPanel?
    private var keyboardMonitor: Any?
    private weak var searchField: NSSearchField?
    var keyPressed: ((UInt16) -> Bool)?
    var isVisible: Bool { panel?.isVisible == true }

    init(tool: ClipboardHistoryTool) { self.tool = tool }

    func show() {
        if panel == nil {
            let panel = HistoryPanel(contentRect: NSRect(x: 0, y: 0, width: 900, height: 540), styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.title = "Historial de portapapeles"
            panel.titleVisibility = .hidden
            panel.titlebarAppearsTransparent = true
            panel.isReleasedWhenClosed = false
            panel.hidesOnDeactivate = false
            panel.level = .floating
            panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            panel.delegate = self
            panel.routeKey = { [weak self] in self?.routeKey($0) ?? false }
            self.panel = panel
        }
        guard let panel else { return }
        panel.contentView = NSHostingView(rootView: ClipboardHistoryView(tool: tool, controller: self))
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) {
            let visible = screen.visibleFrame
            let width = min(900, visible.width - 32)
            let height = min(540, visible.height - 32)
            panel.setFrame(NSRect(x: visible.midX - width / 2, y: visible.midY - height / 2, width: width, height: height), display: false)
        }
        if let keyboardMonitor { NSEvent.removeMonitor(keyboardMonitor) }
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let handled: Bool = MainActor.assumeIsolated {
                guard let self, let panel = self.panel, panel.isVisible,
                      event.window === panel || panel.isKeyWindow else { return false }
                return self.routeKey(event)
            }
            return handled ? nil : event
        }
        panel.makeKeyAndOrderFront(nil)
        focusSearch()
    }

    func hide() {
        if let keyboardMonitor { NSEvent.removeMonitor(keyboardMonitor) }
        keyboardMonitor = nil
        keyPressed = nil
        searchField = nil
        panel?.orderOut(nil)
    }

    func attachSearchField(_ field: NSSearchField) { searchField = field }
    func closeFromKeyboard() { tool.closeHistory() }

    func focusSearch() {
        guard let panel, let field = searchField, field.window === panel else { return }
        if panel.firstResponder === field { return }
        if let editor = field.currentEditor(), panel.firstResponder === editor { return }
        if panel.makeFirstResponder(field), let editor = field.currentEditor() as? NSTextView {
            // Continue the existing query after clicking elsewhere. Normal field
            // editing preserves accents, IME composition and the first keystroke.
            editor.setSelectedRange(NSRange(location: (field.stringValue as NSString).length, length: 0))
        }
    }

    private func routeKey(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option])
        if modifiers.isEmpty {
            if event.keyCode == 53 { tool.closeHistory(); return true }
            if [125, 126, 36, 76].contains(event.keyCode), keyPressed?(event.keyCode) == true { return true }
        }
        if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.control) {
            // Paste and Select All target the query; Copy can still copy selected
            // preview text through the normal AppKit responder chain.
            if event.modifierFlags.contains(.command), [0, 9].contains(event.keyCode) { focusSearch() }
            return false
        }
        guard event.keyCode != 48 else { return false }
        if event.characters != nil || [51, 117].contains(event.keyCode) { focusSearch() }
        return false
    }

    func windowDidBecomeKey(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in self?.focusSearch() }
    }
    func windowDidResignKey(_ notification: Notification) {
        // Programmatic hide already removed the keyboard monitor. Only a user
        // dismissal should cancel a selection that is still loading from disk.
        if keyboardMonitor != nil { tool.cancelSelection(); hide() }
    }
    func windowWillClose(_ notification: Notification) { tool.cancelSelection(); hide() }
}
