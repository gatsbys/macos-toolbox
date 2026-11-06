import SwiftUI

enum ToolState: Equatable {
    case inactive, active, requiresPermission, error(String)

    var title: String {
        switch self {
        case .inactive: "Desactivada"
        case .active: "Activa"
        case .requiresPermission: "Requiere permiso"
        case .error: "Necesita atención"
        }
    }
    var color: Color {
        switch self {
        case .inactive: .secondary
        case .active: .green
        case .requiresPermission: .orange
        case .error: .red
        }
    }
}

@MainActor
protocol ToolModule: AnyObject, Identifiable, Observable where ID == String {
    var id: String { get }
    var name: String { get }
    var summary: String { get }
    var symbol: String { get }
    var state: ToolState { get }
    var isEnabled: Bool { get }
    var primaryActionTitle: String? { get }
    func performPrimaryAction()
    func setEnabled(_ enabled: Bool)
    func preferencesView() -> AnyView
    func shutdown()
}

extension ToolModule {
    var primaryActionTitle: String? { nil }
    func performPrimaryAction() {}
}

@MainActor @Observable
final class ToolRegistry {
    let tools: [any ToolModule]
    init(tools: [any ToolModule]) { self.tools = tools }
    var activeCount: Int { tools.filter { $0.state == .active }.count }
    func shutdown() { tools.forEach { $0.shutdown() } }
}
