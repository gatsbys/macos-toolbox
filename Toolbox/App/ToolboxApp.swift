import AppKit
import ServiceManagement
import SwiftUI

@main
struct ToolboxApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            ToolboxPanel(model: delegate.model)
                .onAppear { delegate.model.permissions.refresh(); delegate.model.login.refresh() }
        } label: {
            Image(systemName: "square.grid.2x2")
                .accessibilityLabel("Toolbox, \(delegate.model.registry.activeCount) herramientas activas")
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if !UserDefaults.standard.bool(forKey: "app.hasSeenWelcome") || !model.permissions.isTrusted {
            model.showPreferences(section: "general")
            UserDefaults.standard.set(true, forKey: "app.hasSeenWelcome")
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        model.showPreferences()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) { model.registry.shutdown() }
}

@MainActor @Observable
final class AppModel {
    let permissions: PermissionService
    let registry: ToolRegistry
    let login = LoginSettings()
    var selectedSection: String? = "general"
    @ObservationIgnored private var preferencesWindow: NSWindow?

    init() {
        let permissions = PermissionService()
        self.permissions = permissions
        registry = ToolRegistry(tools: [WindowSnapTool(permissions: permissions), ClipboardHistoryTool(permissions: permissions)])
    }

    func showPreferences(section: String? = nil) {
        if let section { selectedSection = section }
        permissions.refresh()
        login.refresh()
        if preferencesWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 850, height: 650), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "Preferencias de Toolbox"
            window.minSize = NSSize(width: 760, height: 600)
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: PreferencesView(model: self))
            window.center()
            preferencesWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        preferencesWindow?.makeKeyAndOrderFront(nil)
    }
}

@MainActor @Observable
final class LoginSettings {
    private(set) var isEnabled = false
    private(set) var needsApproval = false
    private(set) var error: String?

    init() { refresh() }

    func refresh() {
        let status = SMAppService.mainApp.status
        isEnabled = status == .enabled || status == .requiresApproval
        needsApproval = status == .requiresApproval
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            error = nil
        } catch { self.error = error.localizedDescription }
        refresh()
    }

    func openSettings() { SMAppService.openSystemSettingsLoginItems() }
}
