import AppKit
import SwiftUI

@MainActor
final class PreviewPanel {
    private var panel: NSPanel?

    func show(_ frame: CGRect?) {
        guard let frame else { panel?.orderOut(nil); return }
        if panel == nil {
            let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.hidesOnDeactivate = false
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
            panel.isReleasedWhenClosed = false
            panel.contentView = NSHostingView(rootView: PreviewSilhouette())
            self.panel = panel
        }
        guard let panel else { return }
        if panel.frame != frame { panel.setFrame(frame, display: true) }
        panel.orderFrontRegardless()
    }
}

private struct PreviewSilhouette: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color.accentColor.opacity(0.16))
            .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(Color.accentColor.opacity(0.8), lineWidth: 3) }
            .padding(3)
            .accessibilityHidden(true)
    }
}
