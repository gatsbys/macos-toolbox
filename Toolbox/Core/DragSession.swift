import Foundation
import CoreGraphics

struct SnapProposal: Equatable, Sendable {
    var screenID: UInt32
    var zone: SnapZone
    var frame: CGRect
}

struct DragSession: Sendable {
    enum Phase: Equatable, Sendable { case candidate, moving, cancelled }
    private(set) var phase: Phase = .candidate
    let initialFrame: CGRect
    let mouseDown: CGPoint
    private(set) var proposal: SnapProposal?
    private var enteredAt: TimeInterval?
    private(set) var isArmed = false

    init(frame: CGRect, mouseDown: CGPoint) {
        initialFrame = frame
        self.mouseDown = mouseDown
    }

    /// Size changes before a confirmed move indicate resizing, not dragging.
    mutating func observe(frame: CGRect, cursor: CGPoint) {
        guard phase != .cancelled else { return }
        if phase == .candidate {
            if abs(frame.width - initialFrame.width) > 2 || abs(frame.height - initialFrame.height) > 2 {
                cancel()
                return
            }
            let cursorMoved = hypot(cursor.x - mouseDown.x, cursor.y - mouseDown.y) >= 6
            let windowMoved = hypot(frame.minX - initialFrame.minX, frame.minY - initialFrame.minY) > 2
            if cursorMoved && windowMoved { phase = .moving }
        }
    }

    mutating func update(proposal newProposal: SnapProposal?, at time: TimeInterval) {
        guard phase == .moving else { return }
        if proposal != newProposal {
            proposal = newProposal
            enteredAt = newProposal == nil ? nil : time
            isArmed = false
        }
        if let enteredAt, proposal != nil, time - enteredAt >= SnapGeometry.dwellTime - 0.000_001 {
            isArmed = true
        }
    }

    mutating func cancel() {
        phase = .cancelled
        proposal = nil
        enteredAt = nil
        isArmed = false
    }

    var dropTarget: SnapProposal? { phase == .moving && isArmed ? proposal : nil }
}
