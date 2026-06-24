import CoreGraphics
import Foundation
import Vision

struct DetectionCandidate: Sendable {
    let quadrilateral: NormalizedQuadrilateral
    let confidence: Float
}

enum RectangleDetectionService {
    static func detect(in image: CGImage) async throws -> [DetectionCandidate] {
        var request = DetectRectanglesRequest()
        request.maximumObservations = 32
        request.minimumSize = 0.05
        request.minimumConfidence = 0.35
        request.minimumAspectRatio = 0.20
        request.maximumAspectRatio = 1.00
        request.quadratureToleranceDegrees = 35

        let observations = try await request.perform(on: image)
        let candidates = observations.compactMap { observation -> DetectionCandidate? in
            let quadrilateral = NormalizedQuadrilateral(
                topLeft: convert(observation.topLeft),
                topRight: convert(observation.topRight),
                bottomRight: convert(observation.bottomRight),
                bottomLeft: convert(observation.bottomLeft)
            )
            guard quadrilateral.isValid() else { return nil }
            return DetectionCandidate(
                quadrilateral: quadrilateral,
                confidence: observation.confidence
            )
        }
        return deduplicate(candidates)
            .sorted {
                let lhs = $0.quadrilateral.centroid
                let rhs = $1.quadrilateral.centroid
                if abs(lhs.y - rhs.y) > 0.04 {
                    return lhs.y < rhs.y
                }
                return lhs.x < rhs.x
            }
    }

    private static func convert(_ point: Vision.NormalizedPoint) -> NormalizedPoint {
        NormalizedPoint(x: point.x, y: 1 - point.y)
    }

    private static func deduplicate(_ candidates: [DetectionCandidate]) -> [DetectionCandidate] {
        candidates
            .sorted { $0.confidence > $1.confidence }
            .reduce(into: [DetectionCandidate]()) { accepted, candidate in
                let duplicate = accepted.contains {
                    $0.quadrilateral.boundingBoxIntersectionOverUnion(
                        with: candidate.quadrilateral
                    ) >= 0.80
                }
                if !duplicate {
                    accepted.append(candidate)
                }
            }
    }
}

