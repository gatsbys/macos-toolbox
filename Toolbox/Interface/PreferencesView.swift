import SwiftUI

private let toolboxDisplayName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Toolbox"

struct PreferencesView: View {
    @Bindable var model: AppModel

    var body: some View {
        NavigationSplitView {
            List(selection: $model.selectedSection) {
                Label("General", systemImage: "slider.horizontal.3").tag("general")
                Section("Herramientas") {
                    ForEach(model.registry.tools, id: \.id) { tool in
                        Label(tool.name, systemImage: tool.symbol).tag(tool.id)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 190, ideal: 205, max: 250)
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 7) {
                    Image(systemName: "square.grid.2x2.fill").foregroundStyle(.tint)
                    Text("Toolbox").fontWeight(.medium)
                    Spacer()
                    Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0").foregroundStyle(.tertiary)
                }
                .font(.caption).padding(18)
            }
        } detail: {
            if let tool = model.registry.tools.first(where: { $0.id == model.selectedSection }) {
                tool.preferencesView()
            } else { GeneralSettingsView(model: model) }
        }
        .tint(.indigo)
        .frame(minWidth: 760, minHeight: 570)
    }
}

struct GeneralSettingsView: View {
    let model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                SettingsHeading(eyebrow: "TU ESPACIO DE TRABAJO", title: "Pequeñas herramientas.\nUn Mac más cómodo.", subtitle: "Todo a mano en la barra de menús.", symbol: "square.grid.2x2")

                VStack(alignment: .leading, spacing: 14) {
                    Label("Al iniciar tu Mac", systemImage: "power").font(.headline)
                    Toggle("Abrir Toolbox al iniciar sesión", isOn: Binding(get: { model.login.isEnabled }, set: { model.login.setEnabled($0) }))
                    Text("Tus herramientas estarán disponibles al entrar en tu sesión.").font(.caption).foregroundStyle(.secondary)
                    if model.login.needsApproval {
                        Button("Revisar ítems de inicio…") { model.login.openSettings() }
                    }
                    if let error = model.login.error { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
                }.settingsCard()

                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Label("Accesibilidad", systemImage: "hand.raised").font(.headline)
                        Spacer()
                        StatusBadge(title: model.permissions.isTrusted ? "Permitido" : "Pendiente", color: model.permissions.isTrusted ? .green : .orange)
                    }
                    Text("Para colocar ventanas o pegar automáticamente desde el historial, Toolbox necesita permiso de Accesibilidad en los ajustes de macOS.")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button(model.permissions.actionTitle) { model.permissions.request() }
                            .buttonStyle(.borderedProminent)
                            .disabled(model.permissions.isRequestInFlight)
                        Button("Comprobar") { model.permissions.refresh() }.buttonStyle(.bordered)
                    }
                    Text("Activa \(toolboxDisplayName) en la lista y vuelve aquí. El estado se comprueba automáticamente; también puedes pulsar Comprobar.")
                        .font(.caption).foregroundStyle(.secondary)
                    if !model.permissions.isTrusted { PermissionRecoveryView() }
                }.settingsCard()

                NativeTilingNote()

                Link(destination: URL(string: "https://www.buymeacoffee.com/the.gatsbys")!) {
                    Label("Invítame a un café", systemImage: "cup.and.saucer")
                }
                .help("Abre Buy Me a Coffee en el navegador")

                Label("Los ajustes se guardan en este Mac.", systemImage: "internaldrive")
                    .font(.caption).foregroundStyle(.tertiary)
            }.padding(30).frame(maxWidth: 760, alignment: .leading)
        }
        .background(.background)
        .navigationTitle("General")
    }
}

struct PermissionRecoveryView: View {
    var body: some View {
        DisclosureGroup("¿Ya aparece activado y sigue pendiente?") {
            VStack(alignment: .leading, spacing: 10) {
                Text("El permiso puede corresponder a otra copia o a una compilación anterior. En Accesibilidad, selecciona \(toolboxDisplayName), quítala con − y añádela de nuevo con + eligiendo esta copia. Actívala y vuelve a comprobar el permiso.")
                Text(Bundle.main.bundleURL.path)
                    .font(.system(.caption2, design: .monospaced))
                    .textSelection(.enabled)
                Button("Mostrar esta copia en Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
                }
                Text("Si macOS aún no reconoce el cambio, cierra Toolbox desde su cajón y vuelve a abrir esta misma copia. No hace falta borrar otros permisos.")
            }
            .font(.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 10)
        }
        .font(.caption)
    }
}

struct SettingsHeading: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    let symbol: String
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: symbol).font(.system(size: 27, weight: .medium)).foregroundStyle(.tint)
                .frame(width: 58, height: 58).background(.tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
            Text(eyebrow).font(.system(size: 10, weight: .semibold)).tracking(1.4).foregroundStyle(.secondary)
            Text(title).font(.system(size: 28, weight: .semibold, design: .rounded)).fixedSize(horizontal: false, vertical: true)
            Text(subtitle).font(.callout).foregroundStyle(.secondary)
        }.padding(.bottom, 4)
    }
}

struct StatusBadge: View {
    let title: String
    let color: Color
    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(title)
        }.font(.caption.weight(.medium)).foregroundStyle(color)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(color.opacity(0.08), in: Capsule())
    }
}

struct NativeTilingNote: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Un único ajuste por arrastre", systemImage: "info.circle").font(.headline)
            Text("En Ajustes del Sistema → Escritorio y Dock → Ventanas, desactiva el ajuste por arrastre de macOS para que Toolbox gestione los bordes. Si al arrastrar arriba aparece Mission Control, desactiva también ese gesto en la sección Mission Control.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Button("Abrir Escritorio y Dock…") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension") { NSWorkspace.shared.open(url) }
            }.font(.caption)
        }.settingsCard()
    }
}

extension View {
    func settingsCard() -> some View {
        self.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 14))
            .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(.primary.opacity(0.06)) }
    }
}
