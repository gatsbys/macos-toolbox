import AppKit
@preconcurrency import ApplicationServices
import Observation

enum ClipboardPasteError: Error, LocalizedError, Equatable {
    case permission, unavailable, focus, event

    var errorDescription: String? {
        switch self {
        case .permission: "El contenido está copiado. Para pegar automáticamente, permite Accesibilidad en las preferencias de Toolbox. También puedes cerrar el historial y pegar con ⌘V."
        case .unavailable: "El contenido está copiado, pero la aplicación anterior ya no está disponible. Cierra el historial y pega con ⌘V donde quieras."
        case .focus: "El contenido está copiado, pero no se ha podido recuperar el foco o sigues pulsando un modificador. Cierra el historial y pega con ⌘V."
        case .event: "El contenido está copiado, pero no se ha podido enviar ⌘V. Cierra el historial y pega manualmente."
        }
    }
}

@MainActor
struct ClipboardPasteClient {
    var isTrusted: () -> Bool
    var isRunning: (pid_t) -> Bool
    var activate: (pid_t) -> Bool
    var frontmostPID: () -> pid_t?
    var modifiersReleased: () -> Bool
    var postPaste: (pid_t) -> Bool
    var pause: () async throws -> Void

    static var live: Self {
        Self(
            isTrusted: { AXIsProcessTrusted() },
            isRunning: { pid in
                guard pid != getpid(), let app = NSRunningApplication(processIdentifier: pid) else { return false }
                return !app.isTerminated
            },
            activate: { NSRunningApplication(processIdentifier: $0)?.activate() ?? false },
            frontmostPID: { NSWorkspace.shared.frontmostApplication?.processIdentifier },
            modifiersReleased: {
                CGEventSource.flagsState(.combinedSessionState)
                    .intersection([.maskCommand, .maskShift, .maskControl, .maskAlternate]).isEmpty
            },
            postPaste: { pid in
                guard let source = CGEventSource(stateID: .privateState),
                      let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
                      let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else { return false }
                down.flags = .maskCommand
                up.flags = .maskCommand
                // Target the saved process, never whichever app happens to be active later.
                down.postToPid(pid)
                up.postToPid(pid)
                return true
            },
            pause: { try await Task.sleep(for: .milliseconds(25)) }
        )
    }
}

@MainActor @Observable
final class ClipboardPasteController {
    static let preferenceKey = "tools.clipboard-history.pasteOnSelection"
    var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Self.preferenceKey) }
    }
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let client: ClipboardPasteClient

    init(defaults: UserDefaults = .standard, client: ClipboardPasteClient = .live) {
        self.defaults = defaults
        self.client = client
        isEnabled = defaults.bool(forKey: Self.preferenceKey)
    }

    func validate(target: pid_t?) throws {
        guard client.isTrusted() else { throw ClipboardPasteError.permission }
        guard let target, client.isRunning(target) else { throw ClipboardPasteError.unavailable }
    }

    // The caller must finish writing the pasteboard and hide its panel first.
    func paste(to target: pid_t?) async throws {
        try Task.checkCancellation()
        try validate(target: target)
        guard let target else { throw ClipboardPasteError.unavailable }
        guard client.activate(target) else { throw ClipboardPasteError.focus }

        var readySamples = 0
        for _ in 0..<40 {
            // Yield even if the destination already appears active: a nonactivating
            // NSPanel must release keyboard focus before the synthetic shortcut.
            try await client.pause()
            try Task.checkCancellation()
            try validate(target: target)
            if client.frontmostPID() == target && client.modifiersReleased() {
                readySamples += 1
                if readySamples >= 2 {
                    guard client.postPaste(target) else { throw ClipboardPasteError.event }
                    return
                }
            } else {
                readySamples = 0
            }
        }
        throw ClipboardPasteError.focus
    }
}
