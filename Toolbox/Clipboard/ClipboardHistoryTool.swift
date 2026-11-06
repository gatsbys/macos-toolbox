import AppKit
import SwiftUI

@MainActor @Observable
final class ClipboardHistoryTool: ToolModule {
    let id = "clipboard-history"
    let name = "Historial de portapapeles"
    let summary = "Lo que copias, siempre a mano."
    let symbol = "clipboard"
    var primaryActionTitle: String? { "Abrir historial" }
    func performPrimaryAction() { showHistory() }
    private(set) var state: ToolState = .inactive
    private(set) var isEnabled: Bool
    private(set) var entries: [ClipboardEntry] = []
    private(set) var access: ClipboardAccess = .needsPermission
    private(set) var issue: String?
    private(set) var shortcutIssue: String?
    private(set) var isLoading = true
    private(set) var isBusy = false
    private(set) var limit: Int
    private(set) var shortcut: ClipboardShortcut
    private(set) var isRecordingShortcut = false
    let permissions: PermissionService
    var pastesOnSelection: Bool {
        get { pasteController.isEnabled }
        set { pasteController.isEnabled = newValue; permissions.refresh() }
    }
    var playsCopySound: Bool {
        get { copyFeedback.isEnabled }
        set { copyFeedback.isEnabled = newValue }
    }
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let copyFeedback: ClipboardCopyFeedback
    @ObservationIgnored private let pasteController: ClipboardPasteController
    @ObservationIgnored private let board = ClipboardPasteboard()
    @ObservationIgnored private let store: ClipboardStore
    @ObservationIgnored private let hotKey = ClipboardHotKey()
    @ObservationIgnored private var monitor: Task<Void, Never>?
    @ObservationIgnored private var panel: ClipboardPanelController?
    @ObservationIgnored private var epoch = 0
    @ObservationIgnored private var previousApplication: NSRunningApplication?
    @ObservationIgnored private var historyApplication: NSRunningApplication?
    @ObservationIgnored private var selectionTask: Task<Void, Never>?
    @ObservationIgnored private var activationObserver: NSObjectProtocol?

    init(defaults: UserDefaults = .standard, directory: URL? = nil, permissions: PermissionService = PermissionService()) {
        self.defaults = defaults
        self.permissions = permissions
        copyFeedback = ClipboardCopyFeedback(defaults: defaults)
        pasteController = ClipboardPasteController(defaults: defaults)
        if let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != getpid() { previousApplication = front }
        isEnabled = defaults.object(forKey: "tools.clipboard-history.enabled") as? Bool ?? true
        limit = [100, 250, 500, 1000].contains(defaults.integer(forKey: "tools.clipboard-history.limit")) ? defaults.integer(forKey: "tools.clipboard-history.limit") : 500
        shortcut = defaults.data(forKey: "tools.clipboard-history.shortcut").flatMap { try? JSONDecoder().decode(ClipboardShortcut.self, from: $0) } ?? .init()
        let location = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.cristian.Toolbox", isDirectory: true)
            .appendingPathComponent("ClipboardHistory", isDirectory: true)
        store = ClipboardStore(directory: location)
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] notification in
            let pid = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            MainActor.assumeIsolated {
                if let pid, pid != getpid() {
                    self?.previousApplication = NSRunningApplication(processIdentifier: pid)
                }
            }
        }
        hotKey.action = { [weak self] in self?.showHistory() }
        Task {
            do { entries = try await store.load() } catch { issue = error.localizedDescription }
            isLoading = false
            reconcile()
        }
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        defaults.set(enabled, forKey: "tools.clipboard-history.enabled")
        reconcile()
    }

    func preferencesView() -> AnyView { AnyView(ClipboardSettingsView(tool: self)) }

    func showHistory() {
        guard !isRecordingShortcut else { return }
        cancelSelection()
        if panel?.isVisible != true {
            if let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != getpid() { previousApplication = front }
            historyApplication = previousApplication
        }
        permissions.refresh()
        if panel == nil { panel = ClipboardPanelController(tool: self) }
        panel?.show()
    }

    func closeHistory(restoreFocus: Bool = true) {
        cancelSelection()
        panel?.hide()
        if restoreFocus { historyApplication?.activate() }
    }

    func cancelSelection() {
        selectionTask?.cancel()
        selectionTask = nil
    }

    func requestAccess() {
        guard !isBusy else { return }
        isBusy = true
        let front = NSWorkspace.shared.frontmostApplication
        let source = front?.processIdentifier == getpid() ? previousApplication : front
        Task {
            defer { isBusy = false }
            do {
                // Only this explicit user action may trigger the macOS pasteboard alert.
                if access != .denied, let content = try board.capture(sourceBundleID: source?.bundleIdentifier, explicitRequest: true) {
                    entries = try await store.insert(content, sourceApp: source?.localizedName, limit: limit)
                }
                access = board.access()
                updateState()
            } catch { issue = error.localizedDescription }
        }
    }

    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security") { NSWorkspace.shared.open(url) }
    }

    func selectEntry(_ entry: ClipboardEntry) {
        useEntry(entry, paste: pastesOnSelection)
    }

    func copyEntry(_ entry: ClipboardEntry) {
        useEntry(entry, paste: false)
    }

    private func useEntry(_ entry: ClipboardEntry, paste: Bool) {
        guard !isBusy else { return }
        isBusy = true
        epoch += 1
        let destination = historyApplication
        selectionTask = Task {
            defer { isBusy = false }
            do {
                let content = try await store.content(for: entry.id)
                try Task.checkCancellation()
                try board.copy(content)
                copyFeedback.didCopy()
                issue = nil
                if paste {
                    permissions.refresh()
                    try pasteController.validate(target: destination?.processIdentifier)
                    panel?.hide()
                    try await pasteController.paste(to: destination?.processIdentifier)
                } else {
                    panel?.hide()
                    destination?.activate()
                }
            } catch is CancellationError {
                // Closing or reopening the panel cancels the pending selection.
            } catch {
                guard !Task.isCancelled else { return }
                issue = error.localizedDescription
                permissions.refresh()
                // Keep the explanation visible when activation failed after hiding.
                if panel?.isVisible != true { panel?.show() }
            }
        }
    }

    func removeEntry(_ entry: ClipboardEntry) {
        epoch += 1
        Task { do { entries = try await store.remove(entry.id) } catch { issue = error.localizedDescription } }
    }

    func clearHistory() {
        epoch += 1
        Task {
            do {
                board.resetBaseline()
                entries = try await store.clear()
                issue = nil
            } catch { issue = error.localizedDescription }
        }
    }

    func setLimit(_ value: Int) {
        guard [100, 250, 500, 1000].contains(value) else { return }
        epoch += 1
        limit = value
        defaults.set(value, forKey: "tools.clipboard-history.limit")
        Task { do { entries = try await store.setLimit(value) } catch { issue = error.localizedDescription } }
    }

    func beginShortcutRecording() {
        guard !isRecordingShortcut else { return }
        isRecordingShortcut = true
        shortcutIssue = nil
        hotKey.stop()
    }

    func finishShortcutRecording(_ value: ClipboardShortcut?) {
        guard isRecordingShortcut else { return }
        isRecordingShortcut = false
        if let value { setShortcut(value) }
        else if isEnabled {
            shortcutIssue = hotKey.register(shortcut) ? nil : "No se ha podido recuperar el atajo anterior. Elige otra combinación."
        } else { shortcutIssue = nil }
    }

    func invalidShortcutRecorded() {
        shortcutIssue = "Incluye ⌘, ⌃ o ⌥ y otra tecla. Escape cancela la grabación."
    }

    func setShortcut(_ value: ClipboardShortcut) {
        let old = shortcut
        if isEnabled && !hotKey.register(value) {
            shortcutIssue = "Ese atajo está ocupado. Elige otra combinación."
            _ = hotKey.register(old)
            return
        }
        shortcut = value
        shortcutIssue = nil
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: "tools.clipboard-history.shortcut") }
    }

    func thumbnail(for entry: ClipboardEntry) async -> NSImage? {
        guard entry.hasThumbnail, let data = await store.thumbnail(for: entry.id) else { return nil }
        return NSImage(data: data)
    }

    func dismissIssue() { issue = nil }

    func previewCopySound() { copyFeedback.didCopy() }

    func shutdown() {
        cancelSelection()
        isRecordingShortcut = false
        epoch += 1
        monitor?.cancel(); monitor = nil
        hotKey.stop()
        panel?.hide()
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
        activationObserver = nil
    }

    private func reconcile() {
        epoch += 1
        monitor?.cancel(); monitor = nil
        hotKey.stop()
        guard isEnabled else { state = .inactive; return }
        if !isRecordingShortcut {
            shortcutIssue = hotKey.register(shortcut) ? nil : "El atajo está ocupado. Puedes abrir el historial desde el cajón y cambiarlo en preferencias."
        }
        monitor = Task { [weak self] in
            guard let self else { return }
            board.resetBaseline()
            while !Task.isCancelled && isEnabled {
                let token = epoch
                access = board.access()
                updateState()
                if access == .allowed && !isBusy && !isLoading {
                    let source = NSWorkspace.shared.frontmostApplication
                    do {
                        if let content = try board.capture(sourceBundleID: source?.bundleIdentifier), token == epoch, isEnabled {
                            let snapshot = try await store.insert(content, sourceApp: source?.localizedName, limit: limit)
                            if token == epoch && isEnabled {
                                entries = snapshot
                                copyFeedback.didCopy()
                            }
                        }
                    } catch { if token == epoch { issue = error.localizedDescription } }
                }
                do { try await Task.sleep(for: access == .allowed ? .milliseconds(200) : .seconds(2)) } catch { return }
            }
        }
    }

    private func updateState() { state = isEnabled ? (access == .allowed ? .active : .requiresPermission) : .inactive }
}
