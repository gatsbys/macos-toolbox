import SwiftUI

struct ToolboxPanel: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "square.grid.2x2.fill")
                    .font(.system(size: 23, weight: .medium))
                    .foregroundStyle(.tint)
                    .frame(width: 44, height: 44)
                    .background(.tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Toolbox").font(.system(size: 20, weight: .semibold, design: .rounded))
                    Text("Tu Mac, a tu manera.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(model.registry.activeCount) activa\(model.registry.activeCount == 1 ? "" : "s")")
                    .font(.caption.weight(.medium)).foregroundStyle(.secondary)
            }
            .padding(20)

            Text("HERRAMIENTAS").font(.system(size: 10, weight: .semibold)).tracking(1.4)
                .foregroundStyle(.secondary).padding(.horizontal, 20).padding(.bottom, 10)

            ForEach(model.registry.tools, id: \.id) { tool in
                HStack(spacing: 10) {
                    Button {
                        if tool.primaryActionTitle != nil { tool.performPrimaryAction() }
                        else { model.showPreferences(section: tool.id) }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: tool.symbol).font(.system(size: 22)).foregroundStyle(.tint)
                                .frame(width: 42, height: 46)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(tool.name).font(.system(size: 13, weight: .semibold))
                                HStack(spacing: 5) {
                                    Circle().fill(tool.state.color).frame(width: 5, height: 5)
                                    Text(tool.state.title).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if tool.primaryActionTitle != nil {
                        Button { model.showPreferences(section: tool.id) } label: { Image(systemName: "gearshape").foregroundStyle(.secondary) }
                            .buttonStyle(.plain).help("Preferencias de \(tool.name)")
                    }
                    Toggle(tool.name, isOn: Binding(get: { tool.isEnabled }, set: { tool.setEnabled($0) }))
                        .labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
                .padding(12)
                .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 12)
            }

            if model.registry.tools.contains(where: { $0.id == "window-snapping" && $0.state == .requiresPermission }) {
                Button { model.showPreferences(section: "general") } label: {
                    Label("Permitir el ajuste de ventanas", systemImage: "hand.raised")
                        .font(.caption).frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain).foregroundStyle(.orange)
                .padding(.horizontal, 24).padding(.top, 14)
            }

            Divider().padding(.top, 18)
            HStack {
                Button { model.showPreferences() } label: { Label("Preferencias…", systemImage: "gearshape") }
                Spacer()
                Button("Salir") { NSApplication.shared.terminate(nil) }
                    .keyboardShortcut("q")
            }
            .buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
            .padding(.horizontal, 20).padding(.vertical, 14)
        }
        .frame(width: 360)
    }
}
