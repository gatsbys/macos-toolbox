import AppKit
import SwiftUI

struct ShortcutRecorder: NSViewRepresentable {
    let shortcut: ClipboardShortcut
    let onBegin: () -> Void
    let onFinish: (ClipboardShortcut?) -> Void
    let onInvalid: () -> Void

    func makeNSView(context: Context) -> ShortcutRecorderButton {
        let button = ShortcutRecorderButton()
        configure(button)
        return button
    }

    func updateNSView(_ button: ShortcutRecorderButton, context: Context) { configure(button) }
    static func dismantleNSView(_ button: ShortcutRecorderButton, coordinator: ()) { button.finishRecording(nil) }

    private func configure(_ button: ShortcutRecorderButton) {
        button.shortcut = shortcut
        button.onBegin = onBegin
        button.onFinish = onFinish
        button.onInvalid = onInvalid
        button.refreshTitle()
    }
}

@MainActor
final class ShortcutRecorderButton: NSButton {
    var shortcut = ClipboardShortcut()
    var onBegin: (() -> Void)?
    var onFinish: ((ClipboardShortcut?) -> Void)?
    var onInvalid: (() -> Void)?
    private(set) var isRecording = false
    private var monitor: Any?
    private var resignObserver: NSObjectProtocol?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        bezelStyle = .rounded
        controlSize = .large
        font = .systemFont(ofSize: 13, weight: .semibold)
        setButtonType(.momentaryPushIn)
        target = self
        action = #selector(toggleRecording)
        setAccessibilityIdentifier("clipboard-shortcut-recorder")
        refreshTitle()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    override var acceptsFirstResponder: Bool { true }

    @objc private func toggleRecording() {
        if isRecording { finishRecording(nil); return }
        guard let window, window.makeFirstResponder(self) else { return }
        isRecording = true
        onBegin?()
        refreshTitle()
        // Only observe events sent to the focused recorder in this application.
        // The global shortcut is suspended until this recording ends.
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            let handled: Bool = MainActor.assumeIsolated {
                guard let self, self.isRecording, let window = self.window,
                      event.window === window, window.firstResponder === self else { return false }
                if event.type == .flagsChanged { return false }
                self.capture(event)
                return true
            }
            return handled ? nil : event
        }
        resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.finishRecording(nil) }
        }
    }

    override func keyDown(with event: NSEvent) {
        if isRecording { capture(event) } else { super.keyDown(with: event) }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if isRecording, window?.firstResponder === self { capture(event); return true }
        return super.performKeyEquivalent(with: event)
    }

    override func resignFirstResponder() -> Bool {
        finishRecording(nil)
        return super.resignFirstResponder()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { finishRecording(nil) }
        super.viewWillMove(toWindow: newWindow)
    }

    private func capture(_ event: NSEvent) {
        if event.keyCode == 53 { finishRecording(nil); return }
        guard !event.isARepeat else { return }
        guard let recorded = ClipboardShortcut.from(event) else { onInvalid?(); return }
        finishRecording(recorded)
    }

    func finishRecording(_ recorded: ClipboardShortcut?) {
        guard isRecording else { return }
        isRecording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        monitor = nil
        resignObserver = nil
        refreshTitle()
        onFinish?(recorded)
    }

    func refreshTitle() {
        title = isRecording ? "Cancelar" : "Grabar atajo"
        image = NSImage(systemSymbolName: isRecording ? "stop.circle" : "record.circle", accessibilityDescription: nil)
        imagePosition = .imageLeading
        imageHugsTitle = true
        bezelColor = isRecording ? .controlAccentColor : nil
        contentTintColor = isRecording ? .white : .labelColor
        setAccessibilityLabel(isRecording ? "Grabando atajo. Pulsa Escape para cancelar." : "Grabar atajo. Actual: \(shortcut.label)")
        toolTip = isRecording ? "Incluye ⌘, ⌃ o ⌥. Escape cancela." : "Pulsa para grabar tu propia combinación de teclas."
    }
}
