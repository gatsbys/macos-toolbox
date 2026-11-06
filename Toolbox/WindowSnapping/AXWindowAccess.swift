import ApplicationServices
import Foundation

/// AX references are immutable identities; all reads/writes are serialized by SnapEngine.
final class WindowHandle: Hashable, @unchecked Sendable {
    let element: AXUIElement
    let pid: pid_t

    init(_ element: AXUIElement, pid: pid_t) { self.element = element; self.pid = pid }
    static func == (lhs: WindowHandle, rhs: WindowHandle) -> Bool {
        lhs.pid == rhs.pid && CFEqual(lhs.element, rhs.element)
    }
    func hash(into hasher: inout Hasher) { hasher.combine(pid); hasher.combine(CFHash(element)) }
}

struct WindowSnapshot: Sendable {
    let handle: WindowHandle
    let frame: CGRect
}

enum WindowAccessError: Error, LocalizedError {
    case permission, unavailable, cannotResize, rejected
    var errorDescription: String? {
        switch self {
        case .permission: "Toolbox necesita permiso de Accesibilidad."
        case .unavailable: "La ventana ya no está disponible o no responde."
        case .cannotResize: "Esta ventana no permite cambiar su tamaño."
        case .rejected: "La aplicación ha limitado el tamaño o la posición de la ventana."
        }
    }
}

enum WindowChange: Sendable { case resized, destroyed }

/// Implementations are owned by the engine actor and never accessed concurrently.
protocol WindowAccessing: AnyObject, Sendable {
    func beginObserving(receive: @escaping @Sendable (WindowHandle, WindowChange) -> Void)
    func window(at cursor: CGPoint, primaryTop: CGFloat) throws -> WindowSnapshot?
    func frame(of window: WindowHandle, primaryTop: CGFloat) throws -> CGRect
    @discardableResult func setFrame(_ target: CGRect, of window: WindowHandle, primaryTop: CGFloat) throws -> CGRect
    func watch(_ window: WindowHandle)
    func unwatch(_ window: WindowHandle)
    func stopObserving()
}

private final class ObserverRelay: @unchecked Sendable {
    let receive: @Sendable (WindowHandle, WindowChange) -> Void
    init(receive: @escaping @Sendable (WindowHandle, WindowChange) -> Void) { self.receive = receive }
}

private let windowObserverCallback: AXObserverCallback = { _, element, notification, context in
    guard let context else { return }
    let relay = Unmanaged<ObserverRelay>.fromOpaque(context).takeUnretainedValue()
    var pid: pid_t = 0
    AXUIElementGetPid(element, &pid)
    relay.receive(WindowHandle(element, pid: pid), notification as String == kAXUIElementDestroyedNotification as String ? .destroyed : .resized)
}

/// Owned exclusively by SnapEngine. The relay has immutable, thread-safe state.
final class AXWindowAccess: WindowAccessing, @unchecked Sendable {
    private var observers: [pid_t: AXObserver] = [:]
    private var watched: Set<WindowHandle> = []
    private var relay: ObserverRelay?

    func beginObserving(receive: @escaping @Sendable (WindowHandle, WindowChange) -> Void) {
        relay = ObserverRelay(receive: receive)
    }

    func window(at cursor: CGPoint, primaryTop: CGFloat) throws -> WindowSnapshot? {
        guard AXIsProcessTrusted() else { throw WindowAccessError.permission }
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.2)
        let p = SnapGeometry.accessibilityPoint(from: cursor, primaryTop: primaryTop)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(p.x), Float(p.y), &hit) == .success, var element = hit else { return nil }
        // Hit testing may return a title, toolbar, content view, or AXWindow itself.
        for _ in 0..<24 {
            if stringAttribute(element, kAXRoleAttribute) == kAXWindowRole as String { break }
            if let window = elementAttribute(element, kAXWindowAttribute) { element = window; break }
            guard let parent = elementAttribute(element, kAXParentAttribute) else { return nil }
            element = parent
        }
        guard stringAttribute(element, kAXRoleAttribute) == kAXWindowRole as String,
              stringAttribute(element, kAXSubroleAttribute) == kAXStandardWindowSubrole as String,
              !boolAttribute(element, kAXMinimizedAttribute),
              !boolAttribute(element, "AXFullScreen" as CFString) else { return nil }
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success, pid != getpid() else { return nil }
        AXUIElementSetMessagingTimeout(element, 0.2)
        var positionSettable: DarwinBoolean = false
        var sizeSettable: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(element, kAXPositionAttribute as CFString, &positionSettable) == .success,
              AXUIElementIsAttributeSettable(element, kAXSizeAttribute as CFString, &sizeSettable) == .success,
              positionSettable.boolValue, sizeSettable.boolValue else { return nil }
        let handle = WindowHandle(element, pid: pid)
        return WindowSnapshot(handle: handle, frame: try frame(of: handle, primaryTop: primaryTop))
    }

    func frame(of window: WindowHandle, primaryTop: CGFloat) throws -> CGRect {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window.element, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(window.element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue, let sizeValue,
              CFGetTypeID(positionValue) == AXValueGetTypeID(), CFGetTypeID(sizeValue) == AXValueGetTypeID() else {
            throw AXIsProcessTrusted() ? WindowAccessError.unavailable : WindowAccessError.permission
        }
        var origin = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &origin),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size), size.width > 0, size.height > 0 else {
            throw WindowAccessError.unavailable
        }
        return SnapGeometry.appKitRect(from: CGRect(origin: origin, size: size), primaryTop: primaryTop)
    }

    @discardableResult
    func setFrame(_ target: CGRect, of window: WindowHandle, primaryTop: CGFloat) throws -> CGRect {
        guard AXIsProcessTrusted() else { throw WindowAccessError.permission }
        let ax = SnapGeometry.accessibilityRect(from: target, primaryTop: primaryTop)
        var origin = ax.origin
        var size = ax.size
        guard let sizeValue = AXValueCreate(.cgSize, &size), let originValue = AXValueCreate(.cgPoint, &origin) else {
            throw WindowAccessError.cannotResize
        }
        // Move first so display-specific size constraints apply to the destination.
        guard AXUIElementSetAttributeValue(window.element, kAXPositionAttribute as CFString, originValue) == .success,
              AXUIElementSetAttributeValue(window.element, kAXSizeAttribute as CFString, sizeValue) == .success,
              AXUIElementSetAttributeValue(window.element, kAXPositionAttribute as CFString, originValue) == .success else {
            throw WindowAccessError.cannotResize
        }
        return try frame(of: window, primaryTop: primaryTop)
    }

    func watch(_ window: WindowHandle) {
        guard !watched.contains(window), let relay else { return }
        let observer: AXObserver
        if let existing = observers[window.pid] { observer = existing }
        else {
            var created: AXObserver?
            guard AXObserverCreate(window.pid, windowObserverCallback, &created) == .success, let created else { return }
            observer = created
            observers[window.pid] = observer
            CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        let context = Unmanaged.passUnretained(relay).toOpaque()
        AXObserverAddNotification(observer, window.element, kAXUIElementDestroyedNotification as CFString, context)
        AXObserverAddNotification(observer, window.element, kAXWindowResizedNotification as CFString, context)
        watched.insert(window)
    }

    func unwatch(_ window: WindowHandle) {
        guard watched.remove(window) != nil, let observer = observers[window.pid] else { return }
        AXObserverRemoveNotification(observer, window.element, kAXWindowResizedNotification as CFString)
        AXObserverRemoveNotification(observer, window.element, kAXUIElementDestroyedNotification as CFString)
        if !watched.contains(where: { $0.pid == window.pid }) {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
            observers.removeValue(forKey: window.pid)
        }
    }

    func stopObserving() {
        for window in Array(watched) { unwatch(window) }
        // Release on the callback's run loop so an in-flight callback retains its context.
        let oldRelay = relay
        relay = nil
        DispatchQueue.main.async { _ = oldRelay }
    }

    private func value(_ element: AXUIElement, _ attribute: CFString) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
        return value
    }
    private func elementAttribute(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let v = value(element, attribute as CFString), CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return (v as! AXUIElement)
    }
    private func stringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        value(element, attribute as CFString) as? String
    }
    private func boolAttribute(_ element: AXUIElement, _ attribute: CFString) -> Bool {
        value(element, attribute) as? Bool ?? false
    }
    private func boolAttribute(_ element: AXUIElement, _ attribute: String) -> Bool {
        boolAttribute(element, attribute as CFString)
    }
}
