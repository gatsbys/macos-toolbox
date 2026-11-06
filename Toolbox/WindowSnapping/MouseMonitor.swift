import AppKit

@MainActor
final class MouseMonitor {
    private var global: Any?
    private var local: Any?
    private var screenObserver: NSObjectProtocol?
    private var lastDragTimestamp: TimeInterval = 0
    var receive: ((PointerEvent) -> Void)?

    func start() -> Bool {
        guard global == nil else { return true }
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        global = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated { self?.forward(event) }
        }
        // A mouse-up over Toolbox itself must also finish an external drag.
        local = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] event in
            MainActor.assumeIsolated { self?.forward(event) }
            return event
        }
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.send(.screensChanged, timestamp: ProcessInfo.processInfo.systemUptime) }
        }
        return global != nil
    }

    func stop() {
        if let global { NSEvent.removeMonitor(global) }
        if let local { NSEvent.removeMonitor(local) }
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        global = nil
        local = nil
        screenObserver = nil
        lastDragTimestamp = 0
    }

    private func forward(_ event: NSEvent) {
        let kind: PointerEvent.Kind
        switch event.type {
        case .leftMouseDown: kind = .down; lastDragTimestamp = 0
        case .leftMouseDragged:
            // Bound AX traffic even on high refresh-rate displays. Releases are never dropped.
            guard event.timestamp - lastDragTimestamp >= 1.0 / 30 else { return }
            lastDragTimestamp = event.timestamp
            kind = .dragged
        case .leftMouseUp: kind = .up
        default: return
        }
        send(kind, timestamp: event.timestamp)
    }

    private func send(_ kind: PointerEvent.Kind, timestamp: TimeInterval) {
        let screens = NSScreen.screens.map { screen in
            ScreenGeometry(id: (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0, frame: screen.frame, visibleFrame: screen.visibleFrame, scale: screen.backingScaleFactor)
        }
        receive?(PointerEvent(kind: kind, point: NSEvent.mouseLocation, timestamp: timestamp, primaryTop: NSScreen.screens.first?.frame.maxY ?? 0, screens: screens))
    }
}
