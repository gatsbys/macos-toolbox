import SwiftUI

@MainActor @Observable
final class WindowSnapTool: ToolModule {
    let id = "window-snapping"
    let name = "Ajustar ventanas"
    let summary = "Cada ventana, en su sitio."
    let symbol = "rectangle.split.2x1"
    private(set) var state: ToolState = .inactive
    private(set) var isEnabled: Bool
    private(set) var issue: String?
    var configuration: SnapConfiguration {
        didSet {
            if let data = try? JSONEncoder().encode(configuration) { defaults.set(data, forKey: settingsKey) }
            commands.yield(.configure(configuration))
            preview.show(nil)
        }
    }
    let permissions: PermissionService
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let settingsKey = "tools.window-snapping.configuration.v1"
    @ObservationIgnored private let enabledKey = "tools.window-snapping.enabled"
    @ObservationIgnored private let mouse = MouseMonitor()
    @ObservationIgnored private let preview = PreviewPanel()
    @ObservationIgnored private var engine: SnapEngine!
    @ObservationIgnored private var consumer: Task<Void, Never>?
    @ObservationIgnored private let commands: AsyncStream<Command>.Continuation
    private enum Command: Sendable {
        case start(SnapConfiguration), configure(SnapConfiguration), stop, pointer(PointerEvent)
    }

    init(permissions: PermissionService, defaults: UserDefaults = .standard) {
        self.permissions = permissions
        self.defaults = defaults
        isEnabled = defaults.object(forKey: enabledKey) as? Bool ?? true
        configuration = defaults.data(forKey: settingsKey).flatMap { try? JSONDecoder().decode(SnapConfiguration.self, from: $0) } ?? .init()
        let (stream, continuation) = AsyncStream<Command>.makeStream()
        commands = continuation
        engine = SnapEngine { [weak self] update in self?.receive(update) }
        let engine = self.engine!
        consumer = Task {
            for await command in stream {
                switch command {
                case .start(let config): await engine.start(configuration: config)
                case .configure(let config): await engine.configure(config)
                case .stop: await engine.stop()
                case .pointer(let event): await engine.handle(event)
                }
            }
        }
        mouse.receive = { [weak self] in self?.commands.yield(.pointer($0)) }
        permissions.onChange = { [weak self] _ in self?.reconcile() }
        reconcile()
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        defaults.set(enabled, forKey: enabledKey)
        reconcile()
    }

    func preferencesView() -> AnyView { AnyView(WindowSnapSettingsView(tool: self)) }

    func shutdown() {
        mouse.stop()
        preview.show(nil)
        permissions.monitor(whileEnabled: false)
        commands.yield(.stop)
        commands.finish()
    }

    func dismissIssue() { issue = nil }

    private func reconcile() {
        permissions.monitor(whileEnabled: isEnabled)
        guard isEnabled, permissions.isTrusted else {
            mouse.stop()
            preview.show(nil)
            commands.yield(.stop)
            state = isEnabled ? .requiresPermission : .inactive
            return
        }
        commands.yield(.start(configuration))
        if mouse.start() { state = .active }
        else {
            commands.yield(.stop)
            state = .error("No se ha podido observar el arrastre. Prueba a desactivar y activar la herramienta.")
        }
    }

    private func receive(_ update: EngineUpdate) {
        guard isEnabled else { return }
        switch update {
        case .preview(let frame): if state == .active { preview.show(frame) }
        case .issue(let message): issue = message
        case .permissionLost:
            permissions.refresh()
            reconcile()
        }
    }
}
