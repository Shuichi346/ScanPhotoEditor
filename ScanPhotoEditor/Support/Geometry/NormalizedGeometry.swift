import CoreGraphics
import Foundation

struct NormalizedPoint: Codable, Hashable, Sendable {
    var x: CGFloat
    var y: CGFloat

    static let zero = NormalizedPoint(x: 0, y: 0)

    func clamped() -> NormalizedPoint {
        NormalizedPoint(x: min(max(x, 0), 1), y: min(max(y, 0), 1))
    }

    func point(in rect: CGRect) -> CGPoint {
        CGPoint(
            x: rect.minX + x * rect.width,
            y: rect.minY + y * rect.height
        )
    }
}

enum QuadrilateralCorner: String, CaseIterable, Sendable {
    case topLeft
    case topRight
    case bottomRight
    case bottomLeft
}

enum QuadrilateralEdge: String, CaseIterable, Sendable {
    case top
    case right
    case bottom
    case left
}

struct NormalizedQuadrilateral: Codable, Hashable, Sendable {
    var topLeft: NormalizedPoint
    var topRight: NormalizedPoint
    var bottomRight: NormalizedPoint
    var bottomLeft: NormalizedPoint

    static let fullFrame = NormalizedQuadrilateral(
        topLeft: NormalizedPoint(x: 0, y: 0),
        topRight: NormalizedPoint(x: 1, y: 0),
        bottomRight: NormalizedPoint(x: 1, y: 1),
        bottomLeft: NormalizedPoint(x: 0, y: 1)
    )

    static let centered = NormalizedQuadrilateral(
        topLeft: NormalizedPoint(x: 0.1, y: 0.1),
        topRight: NormalizedPoint(x: 0.9, y: 0.1),
        bottomRight: NormalizedPoint(x: 0.9, y: 0.9),
        bottomLeft: NormalizedPoint(x: 0.1, y: 0.9)
    )

    var points: [NormalizedPoint] {
        [topLeft, topRight, bottomRight, bottomLeft]
    }

    var centroid: NormalizedPoint {
        let sum = points.reduce(CGPoint.zero) { partial, point in
            CGPoint(x: partial.x + point.x, y: partial.y + point.y)
        }
        return NormalizedPoint(x: sum.x / 4, y: sum.y / 4)
    }

    var signedArea: CGFloat {
        let closed = points + [topLeft]
        return zip(closed, closed.dropFirst()).reduce(CGFloat.zero) { result, pair in
            result + pair.0.x * pair.1.y - pair.1.x * pair.0.y
        } / 2
    }

    var area: CGFloat { abs(signedArea) }

    var isInBounds: Bool {
        points.allSatisfy { (0 ... 1).contains($0.x) && (0 ... 1).contains($0.y) }
    }

    var isSelfIntersecting: Bool {
        Self.segmentsIntersect(topLeft, topRight, bottomRight, bottomLeft)
            || Self.segmentsIntersect(topRight, bottomRight, bottomLeft, topLeft)
    }

    func isValid(minimumArea: CGFloat = 0.015) -> Bool {
        isInBounds && !isSelfIntersecting && area >= minimumArea
    }

    func point(for corner: QuadrilateralCorner) -> NormalizedPoint {
        switch corner {
        case .topLeft: topLeft
        case .topRight: topRight
        case .bottomRight: bottomRight
        case .bottomLeft: bottomLeft
        }
    }

    mutating func set(_ point: NormalizedPoint, for corner: QuadrilateralCorner) {
        switch corner {
        case .topLeft: topLeft = point
        case .topRight: topRight = point
        case .bottomRight: bottomRight = point
        case .bottomLeft: bottomLeft = point
        }
    }

    func moving(corner: QuadrilateralCorner, to point: NormalizedPoint) -> NormalizedQuadrilateral? {
        var candidate = self
        candidate.set(point.clamped(), for: corner)
        return candidate.isValid() ? candidate : nil
    }

    func moving(edge: QuadrilateralEdge, by delta: CGPoint) -> NormalizedQuadrilateral? {
        var candidate = self
        let corners: [QuadrilateralCorner] = switch edge {
        case .top: [.topLeft, .topRight]
        case .right: [.topRight, .bottomRight]
        case .bottom: [.bottomRight, .bottomLeft]
        case .left: [.bottomLeft, .topLeft]
        }
        for corner in corners {
            let current = candidate.point(for: corner)
            candidate.set(
                NormalizedPoint(x: current.x + delta.x, y: current.y + delta.y).clamped(),
                for: corner
            )
        }
        return candidate.isValid() ? candidate : nil
    }

    func boundingBoxIntersectionOverUnion(with other: NormalizedQuadrilateral) -> CGFloat {
        let first = boundingBox
        let second = other.boundingBox
        let intersection = first.intersection(second)
        guard !intersection.isNull else { return 0 }
        let intersectionArea = intersection.width * intersection.height
        let union = first.width * first.height + second.width * second.height - intersectionArea
        return union > 0 ? intersectionArea / union : 0
    }

    private var boundingBox: CGRect {
        let xs = points.map(\.x)
        let ys = points.map(\.y)
        return CGRect(
            x: xs.min() ?? 0,
            y: ys.min() ?? 0,
            width: (xs.max() ?? 0) - (xs.min() ?? 0),
            height: (ys.max() ?? 0) - (ys.min() ?? 0)
        )
    }

    private static func segmentsIntersect(
        _ firstStart: NormalizedPoint,
        _ firstEnd: NormalizedPoint,
        _ secondStart: NormalizedPoint,
        _ secondEnd: NormalizedPoint
    ) -> Bool {
        func orientation(_ a: NormalizedPoint, _ b: NormalizedPoint, _ c: NormalizedPoint) -> CGFloat {
            (b.y - a.y) * (c.x - b.x) - (b.x - a.x) * (c.y - b.y)
        }
        let first = orientation(firstStart, firstEnd, secondStart)
        let second = orientation(firstStart, firstEnd, secondEnd)
        let third = orientation(secondStart, secondEnd, firstStart)
        let fourth = orientation(secondStart, secondEnd, firstEnd)
        return first * second < 0 && third * fourth < 0
    }
}

