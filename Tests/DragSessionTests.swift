import Foundation
import CoreGraphics
import Testing
@testable import ToolboxCore

private let initial = CGRect(x: 100, y: 100, width: 800, height: 600)
private let down = CGPoint(x: 400, y: 680)
private let target = SnapProposal(screenID: 1, zone: .left, frame: CGRect(x: 0, y: 0, width: 720, height: 874))

private func movingSession() -> DragSession {
    var session = DragSession(frame: initial, mouseDown: down)
    session.observe(frame: initial.offsetBy(dx: 20, dy: 0), cursor: CGPoint(x: 420, y: 680))
    return session
}

@Test func selectionAndFileDraggingAreNotWindowMoves() {
    var session = DragSession(frame: initial, mouseDown: down)
    session.observe(frame: initial, cursor: CGPoint(x: 0, y: 680))
    session.update(proposal: target, at: 0)
    session.update(proposal: target, at: 1)
    #expect(session.phase == .candidate)
    #expect(session.dropTarget == nil)
}

@Test func resizingCancelsSession() {
    var session = DragSession(frame: initial, mouseDown: down)
    session.observe(frame: CGRect(x: 90, y: 100, width: 810, height: 600), cursor: CGPoint(x: 390, y: 680))
    #expect(session.phase == .cancelled)
    #expect(session.dropTarget == nil)
}

@Test func requiresDwellAndRealMovement() {
    var session = movingSession()
    session.update(proposal: target, at: 1)
    #expect(session.dropTarget == nil)
    session.update(proposal: target, at: 1.149)
    #expect(session.dropTarget == nil)
    session.update(proposal: target, at: 1.15)
    #expect(session.dropTarget == target)
}

@Test func leavingEdgeAndDisablingCancelDrop() {
    var session = movingSession()
    session.update(proposal: target, at: 0)
    session.update(proposal: target, at: 0.2)
    session.update(proposal: nil, at: 0.3)
    #expect(session.dropTarget == nil)
    session.cancel()
    session.update(proposal: target, at: 1)
    #expect(session.dropTarget == nil)
}

@Test func changingMonitorsRestartsDwell() {
    var session = movingSession()
    session.update(proposal: target, at: 0)
    session.update(proposal: target, at: 0.2)
    var other = target
    other.screenID = 2
    other.frame.origin.x = -1440
    session.update(proposal: other, at: 0.21)
    #expect(session.dropTarget == nil)
    session.update(proposal: other, at: 0.36)
    #expect(session.dropTarget == other)
}
