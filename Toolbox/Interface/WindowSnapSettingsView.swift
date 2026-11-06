import SwiftUI

struct WindowSnapSettingsView: View {
    @Bindable var tool: WindowSnapTool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                SettingsHeading(eyebrow: "HERRAMIENTA 01", title: "Cada ventana,\nen su sitio.", subtitle: "Arrastra, previsualiza y suelta.", symbol: tool.symbol)
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(tool.name).font(.headline)
                        StatusBadge(title: tool.state.title, color: tool.state.color)
                    }
                    Spacer()
                    Toggle("Activar Ajustar ventanas", isOn: Binding(get: { tool.isEnabled }, set: { tool.setEnabled($0) }))
                        .labelsHidden().toggleStyle(.switch)
                }.settingsCard()

                if tool.state == .requiresPermission {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Un permiso para empezar", systemImage: "hand.raised").font(.headline)
                        Text("Permite que Toolbox coloque las ventanas desde los ajustes de Accesibilidad.")
                            .font(.callout).foregroundStyle(.secondary)
                        HStack {
                            Button(tool.permissions.actionTitle) { tool.permissions.request() }
                                .buttonStyle(.borderedProminent)
                                .disabled(tool.permissions.isRequestInFlight)
                            Button("Comprobar") { tool.permissions.refresh() }
                        }
                        PermissionRecoveryView()
                    }.settingsCard()
                }
                if case .error(let message) = tool.state {
                    Text(message).font(.callout).foregroundStyle(.red).settingsCard()
                }
                if let issue = tool.issue {
                    HStack(alignment: .top) {
                        Label(issue, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                        Spacer()
                        Button { tool.dismissIssue() } label: { Image(systemName: "xmark") }.buttonStyle(.plain).accessibilityLabel("Cerrar aviso")
                    }.settingsCard()
                }

                VStack(alignment: .leading, spacing: 16) {
                    Text("Al acercarte a un borde").font(.headline)
                    HStack(spacing: 12) {
                        EdgeOption(title: "Izquierda", zone: .left, isOn: $tool.configuration.leftEnabled)
                        EdgeOption(title: "Arriba", zone: .maximize, isOn: $tool.configuration.topEnabled)
                        EdgeOption(title: "Derecha", zone: .right, isOn: $tool.configuration.rightEnabled)
                    }
                    Text("Arriba ocupa el escritorio disponible. En las esquinas superiores tiene prioridad el borde de arriba.")
                        .font(.caption).foregroundStyle(.secondary)
                }.settingsCard()

                VStack(alignment: .leading, spacing: 16) {
                    Text("A tu manera").font(.headline)
                    Toggle("Mostrar previsualización", isOn: $tool.configuration.showsPreview)
                    Divider()
                    Toggle("Recuperar el tamaño anterior al mover", isOn: $tool.configuration.restoresSize)
                    Text("Las ventanas ajustadas con Toolbox recuperan su tamaño al sacarlas de su posición.").font(.caption).foregroundStyle(.secondary)
                    Divider()
                    HStack {
                        Text("Separación entre ventanas")
                        Spacer()
                        Text("\(Int(tool.configuration.clampedGap)) pt").monospacedDigit().foregroundStyle(.secondary)
                    }
                    Slider(value: $tool.configuration.gap, in: 0...24, step: 1) { Text("Separación entre ventanas") }
                    HStack { Text("Sin separación"); Spacer(); Text("24 pt") }.font(.caption2).foregroundStyle(.secondary)
                }.settingsCard()
                NativeTilingNote()
            }.padding(30).frame(maxWidth: 760, alignment: .leading)
        }
        .background(.background)
        .navigationTitle(tool.name)
    }
}

private struct EdgeOption: View {
    let title: String
    let zone: SnapZone
    @Binding var isOn: Bool
    var body: some View {
        VStack(spacing: 12) {
            GeometryReader { geometry in
                let size = geometry.size
                ZStack(alignment: zone == .right ? .trailing : .leading) {
                    RoundedRectangle(cornerRadius: 6).fill(.primary.opacity(0.035))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isOn ? Color.indigo.opacity(0.22) : Color.secondary.opacity(0.12))
                        .overlay { RoundedRectangle(cornerRadius: 4).strokeBorder(isOn ? Color.indigo.opacity(0.6) : Color.secondary.opacity(0.2)) }
                        .frame(width: zone == .maximize ? size.width - 8 : (size.width - 12) / 2, height: size.height - 8)
                        .padding(4)
                }
                .overlay(alignment: .topLeading) {
                    HStack(spacing: 2) { ForEach(0..<3) { _ in Circle().fill(.secondary.opacity(0.4)).frame(width: 3, height: 3) } }
                        .padding(8)
                }
            }.frame(height: 64).accessibilityHidden(true)
            Toggle(title, isOn: $isOn).toggleStyle(.checkbox).font(.caption)
        }.frame(maxWidth: .infinity)
    }
}
