import Foundation
import CoreGraphics
import Testing
@testable import ToolboxCore

private let main = ScreenGeometry(id: 1, frame: CGRect(x: 0, y: 0, width: 1440, height: 900), visibleFrame: CGRect(x: 0, y: 64, width: 1440, height: 810))

@Test func halvesMeetAndRespectDock() {
    let left = SnapGeometry.target(for: .left, on: main, gap: 0)
    let right = SnapGeometry.target(for: .right, on: main, gap: 0)
    #expect(left == CGRect(x: 0, y: 64, width: 720, height: 810))
    #expect(left.maxX == right.minX)
    #expect(right.maxX == main.visibleFrame.maxX)
    #expect(SnapGeometry.target(for: .maximize, on: main, gap: 0) == main.visibleFrame)
}

@Test func gapIsUniformAndClamped() {
    let left = SnapGeometry.target(for: .left, on: main, gap: 12)
    let right = SnapGeometry.target(for: .right, on: main, gap: 12)
    #expect(left.minX == 12)
    #expect(right.minX - left.maxX == 12)
    #expect(main.visibleFrame.maxX - right.maxX == 12)
    #expect(SnapConfiguration(gap: 99).clampedGap == 24)
    #expect(SnapConfiguration(gap: .nan).clampedGap == 0)
}

@Test func topCornersWinAndBottomCornersAreLateral() {
    #expect(SnapGeometry.zone(at: CGPoint(x: 0, y: 899), on: main, configuration: .init()) == .maximize)
    #expect(SnapGeometry.zone(at: CGPoint(x: 1439, y: 899), on: main, configuration: .init()) == .maximize)
    #expect(SnapGeometry.zone(at: CGPoint(x: 0, y: 0), on: main, configuration: .init()) == .left)
    #expect(SnapGeometry.zone(at: CGPoint(x: 1439, y: 0), on: main, configuration: .init()) == .right)
}

@Test func disabledEdgesAndInteriorDoNothing() {
    let config = SnapConfiguration(leftEnabled: false, rightEnabled: false, topEnabled: false)
    #expect(SnapGeometry.zone(at: CGPoint(x: 0, y: 899), on: main, configuration: config) == nil)
    #expect(SnapGeometry.zone(at: CGPoint(x: 700, y: 500), on: main, configuration: .init()) == nil)
    #expect(SnapGeometry.zone(at: CGPoint(x: -30, y: 500), on: main, configuration: .init()) == nil)
}

@Test func monitorsWithNegativeAndVerticalOrigins() {
    let left = ScreenGeometry(id: 2, frame: CGRect(x: -1920, y: -200, width: 1920, height: 1080), visibleFrame: CGRect(x: -1920, y: -200, width: 1920, height: 1055), scale: 1)
    let above = ScreenGeometry(id: 3, frame: CGRect(x: 0, y: 900, width: 1920, height: 1080), visibleFrame: CGRect(x: 0, y: 900, width: 1920, height: 1055))
    #expect(SnapGeometry.screen(at: CGPoint(x: -100, y: -100), in: [main, left, above])?.id == 2)
    #expect(SnapGeometry.screen(at: CGPoint(x: 400, y: 1200), in: [main, left, above])?.id == 3)
    for screen in [main, left, above] {
        let ax = SnapGeometry.accessibilityRect(from: screen.visibleFrame, primaryTop: 900)
        #expect(SnapGeometry.appKitRect(from: ax, primaryTop: 900) == screen.visibleFrame)
    }
    #expect(SnapGeometry.accessibilityRect(from: above.frame, primaryTop: 900).minY == -1080)
}

@Test func pixelAlignmentAtDifferentScales() {
    for scale: CGFloat in [1, 2] {
        var screen = main
        screen.frame.size.width = 1441
        screen.visibleFrame.size.width = 1441
        screen.scale = scale
        let left = SnapGeometry.target(for: .left, on: screen, gap: 0)
        let right = SnapGeometry.target(for: .right, on: screen, gap: 0)
        #expect(left.maxX == right.minX)
        #expect((left.width * scale).rounded() == left.width * scale)
    }
}

@Test func restoreKeepsGrabPositionAndFitsScreen() {
    let restored = SnapGeometry.restoredFrame(size: CGSize(width: 800, height: 600), grabbedAt: CGPoint(x: 360, y: 860), in: main.visibleFrame, cursor: CGPoint(x: 800, y: 700), visibleFrame: main.visibleFrame)
    #expect(restored.size == CGSize(width: 800, height: 600))
    #expect(main.visibleFrame.contains(restored))
    #expect(abs(restored.maxY - 714) < 1)
}
