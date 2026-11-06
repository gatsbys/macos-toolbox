import SwiftUI

struct ClipboardHistoryView: View {
    @Bindable var tool: ClipboardHistoryTool
    let controller: ClipboardPanelController
    @State private var query = ""
    @State private var kind: ClipboardKind?
    @State private var selection: UUID?
    private var filtered: [ClipboardEntry] { tool.entries.filter { $0.matches(query, kind: kind) } }
    private var selected: ClipboardEntry? { filtered.first { $0.id == selection } ?? filtered.first }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                ClipboardSearchField(query: $query, controller: controller)
                    .frame(height: 28)
                Text(tool.shortcut.label).font(.caption.monospaced()).foregroundStyle(.secondary)
                    .padding(6).background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 5))
            }.padding(.horizontal, 24).padding(.top, 30).padding(.bottom, 18)

            HStack(spacing: 6) {
                filterButton("Todo", kind: nil)
                ForEach(ClipboardKind.allCases, id: \.self) { filterButton($0.title, kind: $0) }
                Spacer()
                Text("\(filtered.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }.padding(.horizontal, 20).padding(.bottom, 14)
            Divider()

            if tool.isLoading {
                ProgressView("Cargando historial…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filtered.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: query.isEmpty ? "clipboard" : "magnifyingglass").font(.system(size: 38, weight: .light)).foregroundStyle(.tertiary)
                    Text(query.isEmpty ? "Lo que copies aparecerá aquí" : "No hay coincidencias").font(.title3.weight(.semibold))
                    Text(emptyMessage).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    if tool.isEnabled && tool.access != .allowed {
                        HStack {
                            Button("Permitir acceso…") { tool.requestAccess() }.disabled(tool.isBusy || tool.access == .denied).buttonStyle(.borderedProminent)
                            Button("Abrir Privacidad…") { tool.openPrivacySettings() }
                        }
                    }
                }.padding(30).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 0) {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 3) {
                                ForEach(filtered) { entry in
                                    Button { selection = entry.id; tool.selectEntry(entry) } label: {
                                        ClipboardEntryRow(entry: entry, tool: tool, selected: selected?.id == entry.id)
                                    }
                                    .buttonStyle(.plain).id(entry.id)
                                    .accessibilityAddTraits(selected?.id == entry.id ? .isSelected : [])
                                    .contextMenu {
                                        Button("Volver a copiar") { tool.copyEntry(entry) }
                                        Button("Eliminar del historial", role: .destructive) { tool.removeEntry(entry) }
                                    }
                                }
                            }.padding(10)
                        }
                        .onChange(of: selection) { _, id in if let id { withAnimation(.easeOut(duration: 0.1)) { proxy.scrollTo(id) } } }
                    }.frame(maxWidth: .infinity)
                    Divider()
                    if let selected {
                        ClipboardEntryPreview(entry: selected, tool: tool)
                            .frame(width: 330).padding(20)
                    }
                }
            }

            if let issue = tool.issue {
                HStack {
                    Label(issue, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                    Spacer()
                    Button { tool.dismissIssue() } label: { Image(systemName: "xmark") }.buttonStyle(.plain).accessibilityLabel("Cerrar aviso")
                }.padding(.horizontal, 20).padding(.vertical, 8)
            }
            Divider()
            HStack {
                Label(tool.pastesOnSelection ? "↑ ↓ elegir   ↩ pegar en la app anterior" : "↑ ↓ elegir   ↩ copiar   ⌘V pegar", systemImage: "keyboard").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if !tool.isEnabled { Text("Captura en pausa").font(.caption).foregroundStyle(.orange) }
                Button("Cerrar") { tool.closeHistory() }.buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
            }.padding(.horizontal, 22).padding(.vertical, 13)
        }
        .background(.background).tint(.indigo)
        .onAppear {
            controller.focusSearch()
            controller.keyPressed = { key in
                if key == 36 || key == 76 { if let selected { tool.selectEntry(selected) }; return true }
                guard key == 125 || key == 126 else { return false }
                let items = filtered
                guard !items.isEmpty else { return true }
                selection = ClipboardHistoryNavigation.move(from: selection, in: items.map(\.id), by: key == 125 ? 1 : -1)
                return true
            }
        }
        .onChange(of: query) { _, _ in selection = nil }
        .onChange(of: kind) { _, _ in selection = nil }
        .onChange(of: filtered.map(\.id)) { _, ids in if let selection, !ids.contains(selection) { self.selection = nil } }
    }

    private var emptyMessage: String {
        if !query.isEmpty { return "Prueba con otra palabra o cambia el filtro." }
        if !tool.isEnabled { return "Activa la herramienta desde el cajón para guardar nuevas copias." }
        if tool.access != .allowed { return "Permite siempre el acceso al portapapeles para guardar texto e imágenes automáticamente." }
        return "Copia texto, un enlace, una imagen o un archivo.\nTu historial se queda en este Mac."
    }

    private func filterButton(_ title: String, kind value: ClipboardKind?) -> some View {
        Button { kind = value; selection = nil } label: {
            Text(title).font(.caption.weight(kind == value ? .semibold : .regular))
                .padding(.horizontal, 11).padding(.vertical, 6)
                .foregroundStyle(kind == value ? Color.indigo : Color.secondary)
                .background(kind == value ? Color.indigo.opacity(0.1) : Color.clear, in: Capsule())
        }.buttonStyle(.plain).accessibilityAddTraits(kind == value ? .isSelected : [])
    }
}

private struct ClipboardSearchField: NSViewRepresentable {
    @Binding var query: String
    let controller: ClipboardPanelController

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = "Buscar en lo que has copiado…"
        field.font = .systemFont(ofSize: 17)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.sendsSearchStringImmediately = true
        field.sendsWholeSearchString = false
        (field.cell as? NSSearchFieldCell)?.searchButtonCell?.isTransparent = true
        field.delegate = context.coordinator
        field.setAccessibilityLabel("Buscar en el historial")
        field.setAccessibilityIdentifier("clipboard-history-search")
        controller.attachSearchField(field)
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != query { field.stringValue = query }
        controller.attachSearchField(field)
    }

    @MainActor
    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: ClipboardSearchField
        init(parent: ClipboardSearchField) { self.parent = parent }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            parent.query = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch NSStringFromSelector(selector) {
            case "moveDown:": return parent.controller.keyPressed?(125) ?? false
            case "moveUp:": return parent.controller.keyPressed?(126) ?? false
            case "insertNewline:": return parent.controller.keyPressed?(36) ?? false
            case "cancelOperation:": parent.controller.closeFromKeyboard(); return true
            default: return false
            }
        }
    }
}

private struct ClipboardEntryRow: View {
    let entry: ClipboardEntry
    let tool: ClipboardHistoryTool
    let selected: Bool
    @State private var image: NSImage?
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(.primary.opacity(0.035))
                if let image { Image(nsImage: image).resizable().scaledToFit().padding(3) }
                else { Image(systemName: entry.kind.symbol).font(.system(size: 21)).foregroundStyle(.indigo.opacity(0.8)) }
            }.frame(width: 58, height: 54)
            VStack(alignment: .leading, spacing: 7) {
                Text(entry.preview).font(.system(size: 13, weight: .medium)).lineLimit(2).multilineTextAlignment(.leading).foregroundStyle(.primary)
                HStack(spacing: 5) {
                    Text(entry.sourceApp ?? entry.kind.title)
                    Text("·")
                    Text(entry.copiedAt, style: .relative)
                }.font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            if selected { Image(systemName: "return").font(.caption).foregroundStyle(.indigo) }
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(selected ? Color.indigo.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
        .task(id: entry.id) { image = await tool.thumbnail(for: entry) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(entry.kind.title): \(entry.preview)")
    }
}

private struct ClipboardEntryPreview: View {
    let entry: ClipboardEntry
    let tool: ClipboardHistoryTool
    @State private var image: NSImage?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(entry.kind.title, systemImage: entry.kind.symbol).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ScrollView {
                if let image { Image(nsImage: image).resizable().scaledToFit().frame(maxHeight: 210).frame(maxWidth: .infinity) }
                Text(entry.preview).font(.system(size: 14)).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
            }
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 5) {
                Text(entry.sourceApp ?? "Portapapeles")
                Text(entry.copiedAt.formatted(date: .abbreviated, time: .shortened))
                if entry.kind == .files { Text("Referencia al archivo original").foregroundStyle(.orange) }
            }.font(.caption).foregroundStyle(.secondary)
            Button { tool.selectEntry(entry) } label: {
                Label(tool.pastesOnSelection ? "Pegar en la app anterior" : "Volver a copiar", systemImage: "doc.on.clipboard").frame(maxWidth: .infinity)
            }.buttonStyle(.borderedProminent).controlSize(.large).disabled(tool.isBusy)
            Text(tool.pastesOnSelection ? "Se pegará donde estabas antes de abrir el historial." : "Después, pega con ⌘V donde quieras.").font(.caption2).foregroundStyle(.secondary)
        }
        .task(id: entry.id) { image = await tool.thumbnail(for: entry) }
    }
}
