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

    func isValid(
        minimumArea: CGFloat = 0.015,
        minimumEdgeLength: CGFloat = 0.01
    ) -> Bool {
        let edgeLengths = zip(points, points.dropFirst() + [topLeft]).map {
            hypot($1.x - $0.x, $1.y - $0.y)
        }
        let crossProducts = zip(points, points.dropFirst() + [topLeft]).enumerated().map {
            index, edge in
            let nextPoint = points[(index + 2) % points.count]
            return Self.cross(edge.0, edge.1, nextPoint)
        }
        let hasSemanticOrdering = topLeft.x <= topRight.x
            && bottomLeft.x <= bottomRight.x
            && topLeft.y <= bottomLeft.y
            && topRight.y <= bottomRight.y

        return isInBounds
            && !isSelfIntersecting
            && signedArea > 0
            && area >= minimumArea
            && edgeLengths.allSatisfy { $0 >= minimumEdgeLength }
            && crossProducts.allSatisfy { $0 > 0.000_001 }
            && hasSemanticOrdering
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

    func intersectionOverUnion(with other: NormalizedQuadrilateral) -> CGFloat {
        guard isValid(), other.isValid() else { return 0 }
        let intersection = Self.clippedPolygon(subject: points, clip: other.points)
        let intersectionArea = Self.polygonArea(intersection)
        let union = area + other.area - intersectionArea
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
        let first = cross(firstStart, firstEnd, secondStart)
        let second = cross(firstStart, firstEnd, secondEnd)
        let third = cross(secondStart, secondEnd, firstStart)
        let fourth = cross(secondStart, secondEnd, firstEnd)
        let epsilon: CGFloat = 0.000_001

        if first * second < -epsilon, third * fourth < -epsilon {
            return true
        }
        return (abs(first) <= epsilon && point(secondStart, liesOn: firstStart, firstEnd))
            || (abs(second) <= epsilon && point(secondEnd, liesOn: firstStart, firstEnd))
            || (abs(third) <= epsilon && point(firstStart, liesOn: secondStart, secondEnd))
            || (abs(fourth) <= epsilon && point(firstEnd, liesOn: secondStart, secondEnd))
    }

    private static func cross(
        _ first: NormalizedPoint,
        _ second: NormalizedPoint,
        _ third: NormalizedPoint
    ) -> CGFloat {
        (second.x - first.x) * (third.y - first.y)
            - (second.y - first.y) * (third.x - first.x)
    }

    private static func point(
        _ point: NormalizedPoint,
        liesOn start: NormalizedPoint,
        _ end: NormalizedPoint
    ) -> Bool {
        let epsilon: CGFloat = 0.000_001
        return point.x >= min(start.x, end.x) - epsilon
            && point.x <= max(start.x, end.x) + epsilon
            && point.y >= min(start.y, end.y) - epsilon
            && point.y <= max(start.y, end.y) + epsilon
    }

    private static func clippedPolygon(
        subject: [NormalizedPoint],
        clip: [NormalizedPoint]
    ) -> [NormalizedPoint] {
        guard subject.count >= 3, clip.count >= 3 else { return [] }
        var output = subject
        let clipEdges = zip(clip, clip.dropFirst() + [clip[0]])

        for edge in clipEdges {
            let input = output
            output.removeAll(keepingCapacity: true)
            guard var previous = input.last else { return [] }
            var previousInside = cross(edge.0, edge.1, previous) >= -0.000_001

            for current in input {
                let currentInside = cross(edge.0, edge.1, current) >= -0.000_001
                if currentInside != previousInside,
                   let intersection = lineIntersection(
                       previous,
                       current,
                       edge.0,
                       edge.1
                   ) {
                    output.append(intersection)
                }
                if currentInside {
                    output.append(current)
                }
                previous = current
                previousInside = currentInside
            }
        }
        return output
    }

    private static func lineIntersection(
        _ firstStart: NormalizedPoint,
        _ firstEnd: NormalizedPoint,
        _ secondStart: NormalizedPoint,
        _ secondEnd: NormalizedPoint
    ) -> NormalizedPoint? {
        let firstX = firstStart.x - firstEnd.x
        let firstY = firstStart.y - firstEnd.y
        let secondX = secondStart.x - secondEnd.x
        let secondY = secondStart.y - secondEnd.y
        let determinant = firstX * secondY - firstY * secondX
        guard abs(determinant) > 0.000_001 else { return nil }

        let firstCross = firstStart.x * firstEnd.y - firstStart.y * firstEnd.x
        let secondCross = secondStart.x * secondEnd.y - secondStart.y * secondEnd.x
        return NormalizedPoint(
            x: (firstCross * secondX - firstX * secondCross) / determinant,
            y: (firstCross * secondY - firstY * secondCross) / determinant
        )
    }

    private static func polygonArea(_ polygon: [NormalizedPoint]) -> CGFloat {
        guard polygon.count >= 3 else { return 0 }
        let closed = polygon + [polygon[0]]
        return abs(
            zip(closed, closed.dropFirst()).reduce(CGFloat.zero) {
                $0 + $1.0.x * $1.1.y - $1.1.x * $1.0.y
            } / 2
        )
    }
}
