import SwiftUI

struct ClipboardSettingsView: View {
    @Bindable var tool: ClipboardHistoryTool
    @State private var confirmClear = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                SettingsHeading(eyebrow: "HERRAMIENTA 02", title: "Una copia nunca\nse pierde.", subtitle: "Texto, imágenes y enlaces, a un atajo de distancia.", symbol: tool.symbol)
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(tool.name).font(.headline)
                        StatusBadge(title: tool.state.title, color: tool.state.color)
                    }
                    Spacer()
                    Toggle("Activar historial de portapapeles", isOn: Binding(get: { tool.isEnabled }, set: { tool.setEnabled($0) })).labelsHidden().toggleStyle(.switch)
                }.settingsCard()

                if tool.isEnabled && tool.access != .allowed {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Acceso al portapapeles", systemImage: "hand.raised").font(.headline)
                        Text("Para guardar nuevas copias automáticamente, permite siempre que Toolbox lea el portapapeles. Este permiso es independiente del ajuste de ventanas.").font(.callout).foregroundStyle(.secondary)
                        HStack {
                            Button("Permitir acceso…") { tool.requestAccess() }.buttonStyle(.borderedProminent).disabled(tool.isBusy || tool.access == .denied)
                            Button("Abrir Privacidad…") { tool.openPrivacySettings() }
                        }
                        Text("Si macOS mantiene la opción Preguntar o Denegar, revisa Pegar desde otras apps en Privacidad y seguridad. Toolbox no solicitará permiso repetidamente en segundo plano.").font(.caption).foregroundStyle(.secondary)
                    }.settingsCard()
                }

                ClipboardShortcutSettingsCard(tool: tool)

                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        Image(systemName: "doc.on.clipboard").font(.title3).foregroundStyle(.tint)
                            .frame(width: 36, height: 36)
                            .background(.tint.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Pegar al seleccionar").font(.headline)
                            Text("Del historial al lugar donde estabas escribiendo.").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("Pegar al seleccionar", isOn: $tool.pastesOnSelection)
                            .labelsHidden().toggleStyle(.switch)
                            .accessibilityIdentifier("clipboard-paste-on-selection")
                    }
                    Text("Al hacer clic en una entrada o pulsar Intro, se cierra el historial y se pega en el campo que tenía el foco antes de abrirlo. El contenido también queda en el portapapeles. Desactivado, solo se copia para que pegues tú con ⌘V.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Text("Necesita permiso de Accesibilidad. La app de destino debe admitir el contenido. Para copiar sin pegar, usa «Volver a copiar» en el menú contextual.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if tool.pastesOnSelection && !tool.permissions.isTrusted {
                        HStack {
                            Label("Accesibilidad pendiente", systemImage: "hand.raised").font(.caption).foregroundStyle(.orange)
                            Spacer()
                            Button(tool.permissions.actionTitle) { tool.permissions.request() }
                                .disabled(tool.permissions.isRequestInFlight)
                            Button("Comprobar") { tool.permissions.refresh() }
                        }
                    }
                }.settingsCard()

                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        Image(systemName: "speaker.wave.2").font(.title3).foregroundStyle(.tint)
                            .frame(width: 36, height: 36)
                            .background(.tint.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Sonido al copiar").font(.headline)
                            Text("Una confirmación breve y discreta.").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("Sonido al copiar", isOn: $tool.playsCopySound).labelsHidden().toggleStyle(.switch)
                    }
                    HStack(alignment: .center, spacing: 16) {
                        Text("Suena al guardar una copia nueva y al copiar desde el historial.")
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Button { tool.previewCopySound() } label: { Label("Probar", systemImage: "play.fill") }
                            .controlSize(.small).disabled(!tool.playsCopySound)
                    }
                }.settingsCard()

                VStack(alignment: .leading, spacing: 16) {
                    Text("Lo que guardas").font(.headline)
                    Picker("Máximo de entradas", selection: Binding(get: { tool.limit }, set: { tool.setLimit($0) })) {
                        ForEach([100, 250, 500, 1000], id: \.self) { Text("\($0) entradas").tag($0) }
                    }
                    Text("\(tool.entries.count) entradas guardadas en este Mac. Se conservan al cerrar Toolbox. Al alcanzar el límite se eliminan las más antiguas.").font(.caption).foregroundStyle(.secondary)
                    Divider()
                    Label("Texto y formato, enlaces, imágenes, PDF y archivos", systemImage: "doc.on.clipboard").font(.callout)
                    Text("Los archivos se guardan como referencias: deben seguir en su ubicación original. Las imágenes y el texto se conservan completos. Límite de 25 MB por copia y 250 MB de historial.").font(.caption).foregroundStyle(.secondary)
                    Text("Se omiten copias marcadas como confidenciales o temporales y las procedentes de 1Password.").font(.caption).foregroundStyle(.secondary)
                    Button("Vaciar historial…", role: .destructive) { confirmClear = true }.disabled(tool.entries.isEmpty)
                }.settingsCard()

                if let issue = tool.issue { Label(issue, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange).settingsCard() }
            }.padding(30).frame(maxWidth: 760, alignment: .leading)
        }
        .navigationTitle(tool.name)
        .confirmationDialog("¿Vaciar el historial de portapapeles?", isPresented: $confirmClear) {
            Button("Vaciar historial", role: .destructive) { tool.clearHistory() }
        } message: { Text("Se borrarán las entradas guardadas en Toolbox. El contenido actual del portapapeles se conserva.") }
    }
}

private struct ClipboardShortcutSettingsCard: View {
    @Bindable var tool: ClipboardHistoryTool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "keyboard").font(.title3).foregroundStyle(.tint)
                    .frame(width: 36, height: 36)
                    .background(.tint.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Atajo de teclado").font(.headline)
                    Text("Tu historial, desde cualquier app.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Button { tool.setShortcut(.init()) } label: {
                    Label("Restablecer", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
                .disabled(tool.isRecordingShortcut || tool.shortcut == ClipboardShortcut())
                .help("Restablecer ⇧⌘V")
            }

            HStack(alignment: .center, spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("ATAJO ACTUAL")
                        .font(.system(size: 9, weight: .semibold)).tracking(1.25).foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        ForEach(Array(tool.shortcut.keyCaps.enumerated()), id: \.offset) { index, key in
                            Text(key)
                                .font(.system(size: 18, weight: .medium, design: .rounded))
                                .padding(.horizontal, index == tool.shortcut.keyCaps.count - 1 ? 12 : 8)
                                .frame(minWidth: 36, minHeight: 36)
                                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
                                .overlay { RoundedRectangle(cornerRadius: 7).strokeBorder(.primary.opacity(0.09)) }
                                .shadow(color: .black.opacity(0.07), radius: 0, x: 0, y: 2)
                        }
                    }
                    .fixedSize()
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Atajo actual")
                    .accessibilityValue(tool.shortcut.label)
                }
                Spacer(minLength: 0)
                ShortcutRecorder(shortcut: tool.shortcut,
                                 onBegin: { tool.beginShortcutRecording() },
                                 onFinish: { tool.finishShortcutRecording($0) },
                                 onInvalid: { tool.invalidShortcutRecorded() })
                    .frame(width: 156, height: 34)
            }
            .padding(16)
            .background(Color.accentColor.opacity(tool.isRecordingShortcut ? 0.07 : 0.035), in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.accentColor.opacity(tool.isRecordingShortcut ? 0.38 : 0.1))
            }

            HStack(alignment: .top, spacing: 7) {
                Image(systemName: tool.isRecordingShortcut ? "record.circle" : "info.circle")
                    .foregroundStyle(tool.isRecordingShortcut ? Color.accentColor : .secondary)
                Text(tool.isRecordingShortcut ? "Pulsa la nueva combinación. Escape o hacer clic fuera cancela." : "Usa ⌘, ⌃ o ⌥ junto a otra tecla. El cambio se guarda al instante.")
                    .fixedSize(horizontal: false, vertical: true)
            }.font(.caption).foregroundStyle(.secondary)

            if let message = tool.shortcutIssue {
                Label(message, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
            }

            Divider()
            HStack(spacing: 14) {
                Button { tool.showHistory() } label: { Label("Abrir historial", systemImage: "clipboard") }
                    .buttonStyle(.bordered).controlSize(.small)
                Spacer(minLength: 0)
                Text(tool.pastesOnSelection ? "↑ ↓ elegir  ·  ↩ pegar" : "↑ ↓ elegir  ·  ↩ copiar  ·  ⌘V pegar")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
        .settingsCard()
        .animation(.easeInOut(duration: 0.16), value: tool.isRecordingShortcut)
    }
}
