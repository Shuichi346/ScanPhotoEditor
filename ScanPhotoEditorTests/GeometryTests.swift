import CoreGraphics
import XCTest
@testable import ScanPhotoEditor

final class GeometryTests: XCTestCase {
    func testFullFrameIsValidAndUsesTopLeftOrigin() {
        let quadrilateral = NormalizedQuadrilateral.fullFrame

        XCTAssertTrue(quadrilateral.isValid())
        XCTAssertEqual(quadrilateral.area, 1, accuracy: 0.000_001)
        XCTAssertEqual(quadrilateral.topLeft, NormalizedPoint(x: 0, y: 0))
        XCTAssertEqual(quadrilateral.bottomRight, NormalizedPoint(x: 1, y: 1))
    }

    func testRejectsSelfIntersectingQuadrilateral() {
        let quadrilateral = NormalizedQuadrilateral(
            topLeft: NormalizedPoint(x: 0, y: 0),
            topRight: NormalizedPoint(x: 1, y: 1),
            bottomRight: NormalizedPoint(x: 1, y: 0),
            bottomLeft: NormalizedPoint(x: 0, y: 1)
        )

        XCTAssertTrue(quadrilateral.isSelfIntersecting)
        XCTAssertFalse(quadrilateral.isValid())
    }

    func testRejectsAreaBelowThreshold() {
        let quadrilateral = NormalizedQuadrilateral(
            topLeft: NormalizedPoint(x: 0.1, y: 0.1),
            topRight: NormalizedPoint(x: 0.11, y: 0.1),
            bottomRight: NormalizedPoint(x: 0.11, y: 0.11),
            bottomLeft: NormalizedPoint(x: 0.1, y: 0.11)
        )

        XCTAssertFalse(quadrilateral.isValid())
    }

    func testCornerMoveClampsToBounds() {
        let moved = NormalizedQuadrilateral.centered.moving(
            corner: .topLeft,
            to: NormalizedPoint(x: -1, y: -1)
        )

        XCTAssertEqual(moved?.topLeft, NormalizedPoint(x: 0, y: 0))
    }

    func testPointCoordinateRoundTrip() {
        let rect = CGRect(x: 20, y: 40, width: 500, height: 300)
        let normalized = NormalizedPoint(x: 0.37, y: 0.62)
        let point = normalized.point(in: rect)
        let roundTrip = NormalizedPoint(
            x: (point.x - rect.minX) / rect.width,
            y: (point.y - rect.minY) / rect.height
        )

        XCTAssertEqual(roundTrip.x, normalized.x, accuracy: 0.000_001)
        XCTAssertEqual(roundTrip.y, normalized.y, accuracy: 0.000_001)
    }
}

