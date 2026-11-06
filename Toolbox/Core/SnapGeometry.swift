import Foundation
import CoreGraphics

enum SnapZone: String, CaseIterable, Codable, Sendable {
    case left, right, maximize
}

struct SnapConfiguration: Equatable, Codable, Sendable {
    var leftEnabled = true
    var rightEnabled = true
    var topEnabled = true
    var showsPreview = true
    var restoresSize = true
    var gap: Double = 0

    var clampedGap: CGFloat { CGFloat(min(24, max(0, gap.isFinite ? gap : 0))) }
}

struct ScreenGeometry: Equatable, Sendable {
    var id: UInt32
    var frame: CGRect
    var visibleFrame: CGRect
    var scale: CGFloat = 2
}

enum SnapGeometry {
    static let activationWidth: CGFloat = 12
    static let dwellTime: TimeInterval = 0.150

    static func screen(at point: CGPoint, in screens: [ScreenGeometry]) -> ScreenGeometry? {
        // Including outer boundaries also handles a cursor at the last pixel of a screen.
        screens.first { $0.frame.contains(point) }
            ?? screens.first { $0.frame.insetBy(dx: -0.5, dy: -0.5).contains(point) }
    }

    static func zone(at point: CGPoint, on screen: ScreenGeometry, configuration: SnapConfiguration) -> SnapZone? {
        guard screen.frame.insetBy(dx: -0.5, dy: -0.5).contains(point) else { return nil }
        if configuration.topEnabled && point.y >= screen.frame.maxY - activationWidth { return .maximize }
        if configuration.leftEnabled && point.x <= screen.frame.minX + activationWidth { return .left }
        if configuration.rightEnabled && point.x >= screen.frame.maxX - activationWidth { return .right }
        return nil
    }

    static func target(for zone: SnapZone, on screen: ScreenGeometry, gap: CGFloat) -> CGRect {
        let g = min(24, max(0, gap))
        let usable = screen.visibleFrame.insetBy(dx: g, dy: g)
        let raw: CGRect
        switch zone {
        case .maximize: raw = usable
        case .left:
            raw = CGRect(x: usable.minX, y: usable.minY, width: (usable.width - g) / 2, height: usable.height)
        case .right:
            raw = CGRect(x: usable.midX + g / 2, y: usable.minY, width: (usable.width - g) / 2, height: usable.height)
        }
        let scale = max(1, screen.scale)
        func align(_ n: CGFloat) -> CGFloat { (n * scale).rounded() / scale }
        return CGRect(x: align(raw.minX), y: align(raw.minY), width: align(raw.maxX) - align(raw.minX), height: align(raw.maxY) - align(raw.minY))
    }

    // Both coordinate spaces are global. Flip around the PRIMARY display's top,
    // never around the current display: other monitors may have negative origins.
    static func accessibilityRect(from rect: CGRect, primaryTop: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryTop - rect.maxY, width: rect.width, height: rect.height)
    }

    static func appKitRect(from rect: CGRect, primaryTop: CGFloat) -> CGRect {
        accessibilityRect(from: rect, primaryTop: primaryTop)
    }

    static func accessibilityPoint(from point: CGPoint, primaryTop: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: primaryTop - point.y)
    }

    static func restoredFrame(size: CGSize, grabbedAt point: CGPoint, in initialFrame: CGRect, cursor: CGPoint, visibleFrame: CGRect) -> CGRect {
        let fraction = min(1, max(0, (point.x - initialFrame.minX) / max(1, initialFrame.width)))
        let titleOffset = min(36, max(0, initialFrame.maxY - point.y))
        let width = min(size.width, visibleFrame.width)
        let height = min(size.height, visibleFrame.height)
        let x = min(visibleFrame.maxX - width, max(visibleFrame.minX, cursor.x - fraction * width))
        let top = min(visibleFrame.maxY, max(visibleFrame.minY + height, cursor.y + titleOffset))
        return CGRect(x: x, y: top - height, width: width, height: height)
    }
}

extension CGRect {
    func approximatelyEquals(_ other: CGRect, tolerance: CGFloat = 2) -> Bool {
        abs(minX - other.minX) <= tolerance && abs(minY - other.minY) <= tolerance
            && abs(width - other.width) <= tolerance && abs(height - other.height) <= tolerance
    }
}
