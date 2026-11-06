import Foundation

struct PointerEvent: Sendable {
    enum Kind: Sendable { case down, dragged, up, screensChanged }
    let kind: Kind
    let point: CGPoint
    let timestamp: TimeInterval
    let primaryTop: CGFloat
    let screens: [ScreenGeometry]
}

enum EngineUpdate: Sendable {
    case preview(CGRect?)
    case issue(String?)
    case permissionLost
}

actor SnapEngine {
    private let access: any WindowAccessing
    private let output: @MainActor @Sendable (EngineUpdate) -> Void
    private var configuration = SnapConfiguration()
    private var isRunning = false
    private var current: WindowHandle?
    private var session: DragSession?
    private var lastEvent: PointerEvent?
    private var dwellTask: Task<Void, Never>?
    private var generation = 0
    private var primaryTop: CGFloat = 0
    private struct Record { let originalSize: CGSize; var appliedFrame: CGRect; var isSnapped = true }
    private var records: [WindowHandle: Record] = [:]

    init(access: any WindowAccessing = AXWindowAccess(), output: @escaping @MainActor @Sendable (EngineUpdate) -> Void) {
        self.access = access
        self.output = output
    }

    func start(configuration: SnapConfiguration) {
        self.configuration = configuration
        guard !isRunning else { return }
        isRunning = true
        access.beginObserving { [weak self] window, change in
            Task { await self?.windowChanged(window, change: change) }
        }
    }

    func configure(_ configuration: SnapConfiguration) {
        self.configuration = configuration
        cancelDrag()
    }

    func stop() {
        isRunning = false
        cancelDrag()
        records.removeAll()
        access.stopObserving()
    }

    func handle(_ event: PointerEvent) {
        guard isRunning else { return }
        primaryTop = event.primaryTop
        lastEvent = event
        do {
            switch event.kind {
            case .down:
                cancelDrag()
                lastEvent = event
                if let snapshot = try access.window(at: event.point, primaryTop: event.primaryTop) {
                    current = snapshot.handle
                    session = DragSession(frame: snapshot.frame, mouseDown: event.point)
                    if let record = records[snapshot.handle], !sameSize(record.appliedFrame, snapshot.frame) {
                        forget(snapshot.handle)
                    }
                }
            case .dragged: try updateDrag(event)
            case .up:
                guard let window = current, var drag = session else { cancelDrag(); return }
                // Recompute at mouse-up: stale previews must never move a window.
                drag.update(proposal: proposal(for: event), at: event.timestamp)
                let target = drag.dropTarget
                let original = records[window]?.originalSize ?? drag.initialFrame.size
                cancelDrag()
                guard let target else {
                    if records[window]?.isSnapped == false { forget(window) }
                    return
                }
                let actual = try access.setFrame(target.frame, of: window, primaryTop: event.primaryTop)
                guard actual.approximatelyEquals(target.frame, tolerance: 3) else {
                    forget(window)
                    emit(.issue(WindowAccessError.rejected.localizedDescription))
                    return
                }
                records[window] = Record(originalSize: original, appliedFrame: actual)
                access.watch(window)
                emit(.issue(nil))
            case .screensChanged:
                cancelDrag()
                for window in Array(records.keys) { forget(window) }
            }
        } catch {
            cancelDrag()
            if case WindowAccessError.permission = error { emit(.permissionLost) }
            else { emit(.issue(error.localizedDescription)) }
        }
    }

    private func updateDrag(_ event: PointerEvent) throws {
        guard let window = current, var drag = session else { return }
        let frame = try access.frame(of: window, primaryTop: event.primaryTop)
        let wasCandidate = drag.phase == .candidate
        drag.observe(frame: frame, cursor: event.point)
        if drag.phase == .cancelled { cancelDrag(); return }
        if wasCandidate && drag.phase == .moving,
           let record = records[window], record.isSnapped, configuration.restoresSize,
           let screen = SnapGeometry.screen(at: event.point, in: event.screens) {
            let restored = SnapGeometry.restoredFrame(size: record.originalSize, grabbedAt: drag.mouseDown, in: drag.initialFrame, cursor: event.point, visibleFrame: screen.visibleFrame)
            let actual = try access.setFrame(restored, of: window, primaryTop: event.primaryTop)
            // Keep the original dimensions if this same gesture snaps elsewhere.
            records[window]?.appliedFrame = actual
            records[window]?.isSnapped = false
        }
        let previous = drag.proposal
        drag.update(proposal: proposal(for: event), at: event.timestamp)
        session = drag
        if previous != drag.proposal {
            generation += 1
            dwellTask?.cancel()
            emit(.preview(nil))
            if drag.proposal != nil {
                let token = generation
                dwellTask = Task { [weak self] in
                    do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
                    await self?.armDwell(token: token)
                }
            }
        }
        if drag.isArmed { emit(.preview(configuration.showsPreview ? drag.proposal?.frame : nil)) }
    }

    private func armDwell(token: Int) {
        guard isRunning, token == generation, var drag = session, let event = lastEvent else { return }
        drag.update(proposal: proposal(for: event), at: event.timestamp + SnapGeometry.dwellTime)
        session = drag
        emit(.preview(configuration.showsPreview ? drag.dropTarget?.frame : nil))
    }

    private func proposal(for event: PointerEvent) -> SnapProposal? {
        guard let screen = SnapGeometry.screen(at: event.point, in: event.screens),
              let zone = SnapGeometry.zone(at: event.point, on: screen, configuration: configuration) else { return nil }
        return SnapProposal(screenID: screen.id, zone: zone, frame: SnapGeometry.target(for: zone, on: screen, gap: configuration.clampedGap))
    }

    private func windowChanged(_ window: WindowHandle, change: WindowChange) {
        guard isRunning else { return }
        switch change {
        case .destroyed:
            forget(window)
            if current == window { cancelDrag() }
        case .resized:
            guard let record = records[window] else { return }
            // AX notifications from our own writes arrive after the completed write.
            guard let frame = try? access.frame(of: window, primaryTop: primaryTop), sameSize(frame, record.appliedFrame) else {
                forget(window)
                return
            }
        }
    }

    private func sameSize(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.width - rhs.width) <= 2 && abs(lhs.height - rhs.height) <= 2
    }

    private func forget(_ window: WindowHandle) {
        records.removeValue(forKey: window)
        access.unwatch(window)
    }

    private func cancelDrag() {
        generation += 1
        dwellTask?.cancel()
        dwellTask = nil
        current = nil
        session = nil
        emit(.preview(nil))
    }

    private func emit(_ update: EngineUpdate) {
        Task { @MainActor [output] in output(update) }
    }
}
