import ApplicationServices
import CoreGraphics
import Foundation
import Testing
@testable import ToolboxCore

private final class FakeWindowAccess: WindowAccessing, @unchecked Sendable {
    private let lock = NSLock()
    private var storedFrame = CGRect(x: 200, y: 200, width: 800, height: 550)
    private var storedWrites: [CGRect] = []
    private var storedError: WindowAccessError?
    private var changeReceiver: (@Sendable (WindowHandle, WindowChange) -> Void)?
    private var observationCount = 0
    let handle = WindowHandle(AXUIElementCreateApplication(99999), pid: 99999)

    var currentFrame: CGRect { get { lock.withLock { storedFrame } } set { lock.withLock { storedFrame = newValue } } }
    var writes: [CGRect] { lock.withLock { storedWrites } }
    var failure: WindowAccessError? { get { lock.withLock { storedError } } set { lock.withLock { storedError = newValue } } }
    var watchedCount: Int { lock.withLock { observationCount } }

    func beginObserving(receive: @escaping @Sendable (WindowHandle, WindowChange) -> Void) { lock.withLock { changeReceiver = receive } }
    func window(at cursor: CGPoint, primaryTop: CGFloat) throws -> WindowSnapshot? {
        if let failure { throw failure }
        return WindowSnapshot(handle: handle, frame: currentFrame)
    }
    func frame(of window: WindowHandle, primaryTop: CGFloat) throws -> CGRect {
        if let failure { throw failure }
        return currentFrame
    }
    func setFrame(_ target: CGRect, of window: WindowHandle, primaryTop: CGFloat) throws -> CGRect {
        if let failure { throw failure }
        lock.withLock { storedWrites.append(target); storedFrame = target }
        return target
    }
    func watch(_ window: WindowHandle) { lock.withLock { observationCount = 1 } }
    func unwatch(_ window: WindowHandle) { lock.withLock { observationCount = 0 } }
    func stopObserving() { lock.withLock { observationCount = 0; changeReceiver = nil } }
}

private let screen = ScreenGeometry(id: 1, frame: CGRect(x: 0, y: 0, width: 1440, height: 900), visibleFrame: CGRect(x: 0, y: 64, width: 1440, height: 810))
private func event(_ kind: PointerEvent.Kind, _ x: CGFloat, _ y: CGFloat, _ time: Double) -> PointerEvent {
    PointerEvent(kind: kind, point: CGPoint(x: x, y: y), timestamp: time, primaryTop: 900, screens: [screen])
}

private func snapLeft(_ engine: SnapEngine, access: FakeWindowAccess) async {
    await engine.handle(event(.down, 500, 735, 1))
    access.currentFrame = access.currentFrame.offsetBy(dx: -200, dy: 0)
    await engine.handle(event(.dragged, 1, 700, 1.1))
    await engine.handle(event(.up, 1, 700, 1.3))
}

@Test func engineSnapsOnlyAfterReleaseAndDwell() async {
    let access = FakeWindowAccess()
    let engine = SnapEngine(access: access) { _ in }
    await engine.start(configuration: .init())
    await engine.handle(event(.down, 500, 735, 1))
    access.currentFrame = access.currentFrame.offsetBy(dx: -200, dy: 0)
    await engine.handle(event(.dragged, 1, 700, 1.1))
    #expect(access.writes.isEmpty)
    await engine.handle(event(.up, 1, 700, 1.3))
    #expect(access.writes == [SnapGeometry.target(for: .left, on: screen, gap: 0)])
    #expect(access.watchedCount == 1)
    await engine.stop()
    #expect(access.watchedCount == 0)
}

@Test func engineIgnoresSelectionAndFastEdgeCrossings() async {
    let access = FakeWindowAccess()
    let engine = SnapEngine(access: access) { _ in }
    await engine.start(configuration: .init())
    await engine.handle(event(.down, 500, 735, 1))
    await engine.handle(event(.dragged, 1, 700, 1.1))
    await engine.handle(event(.up, 1, 700, 1.4))
    #expect(access.writes.isEmpty)
    await engine.handle(event(.down, 500, 735, 2))
    access.currentFrame = access.currentFrame.offsetBy(dx: 10, dy: 0)
    await engine.handle(event(.dragged, 1, 700, 2.1))
    await engine.handle(event(.up, 1, 700, 2.15))
    #expect(access.writes.isEmpty)
    await engine.stop()
}

@Test func engineRechecksDropPosition() async {
    let access = FakeWindowAccess()
    let engine = SnapEngine(access: access) { _ in }
    await engine.start(configuration: .init())
    await engine.handle(event(.down, 500, 735, 1))
    access.currentFrame = access.currentFrame.offsetBy(dx: 10, dy: 0)
    await engine.handle(event(.dragged, 1, 700, 1.1))
    await engine.handle(event(.up, 500, 700, 1.5))
    #expect(access.writes.isEmpty)
    await engine.stop()
}

@Test func engineRestoresAndPreservesOriginalAcrossConsecutiveSnaps() async {
    let access = FakeWindowAccess()
    let originalSize = access.currentFrame.size
    let engine = SnapEngine(access: access) { _ in }
    await engine.start(configuration: .init())
    await snapLeft(engine, access: access)
    await engine.handle(event(.down, 360, 860, 2))
    access.currentFrame = access.currentFrame.offsetBy(dx: 20, dy: -40)
    await engine.handle(event(.dragged, 1439, 800, 2.1))
    #expect(access.writes.last?.size == originalSize)
    await engine.handle(event(.up, 1439, 800, 2.3))
    #expect(access.writes.last == SnapGeometry.target(for: .right, on: screen, gap: 0))
    await engine.handle(event(.down, 1000, 860, 3))
    access.currentFrame = access.currentFrame.offsetBy(dx: -20, dy: -40)
    await engine.handle(event(.dragged, 800, 700, 3.1))
    #expect(access.writes.last?.size == originalSize)
    await engine.handle(event(.up, 800, 700, 3.3))
    #expect(access.watchedCount == 0)
    await engine.stop()
}

@Test func engineInvalidatesRestorationAfterManualResize() async {
    let access = FakeWindowAccess()
    let engine = SnapEngine(access: access) { _ in }
    await engine.start(configuration: .init())
    await snapLeft(engine, access: access)
    access.currentFrame.size.width = 650
    await engine.handle(event(.down, 300, 860, 2))
    access.currentFrame = access.currentFrame.offsetBy(dx: 20, dy: -20)
    await engine.handle(event(.dragged, 500, 700, 2.1))
    #expect(access.writes.count == 1)
    #expect(access.watchedCount == 0)
    await engine.stop()
}

@Test func engineStopsAndConfigurationChangesCancelPendingDrag() async {
    let access = FakeWindowAccess()
    let engine = SnapEngine(access: access) { _ in }
    await engine.start(configuration: .init())
    await engine.handle(event(.down, 500, 735, 1))
    access.currentFrame = access.currentFrame.offsetBy(dx: 10, dy: 0)
    await engine.handle(event(.dragged, 1, 700, 1.1))
    await engine.configure(.init(leftEnabled: false))
    await engine.handle(event(.up, 1, 700, 1.5))
    #expect(access.writes.isEmpty)
    await engine.stop()
    await snapLeft(engine, access: access)
    #expect(access.writes.isEmpty)
}

@Test func engineCancelsOnUnresponsiveOrDisappearingWindow() async {
    let access = FakeWindowAccess()
    let engine = SnapEngine(access: access) { _ in }
    await engine.start(configuration: .init())
    await engine.handle(event(.down, 500, 735, 1))
    access.failure = .unavailable
    await engine.handle(event(.dragged, 1, 700, 1.1))
    access.failure = nil
    await engine.handle(event(.up, 1, 700, 1.4))
    #expect(access.writes.isEmpty)
    await engine.stop()
}
