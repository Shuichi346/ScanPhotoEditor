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

    func testRejectsConcaveQuadrilateral() {
        let quadrilateral = NormalizedQuadrilateral(
            topLeft: NormalizedPoint(x: 0.1, y: 0.1),
            topRight: NormalizedPoint(x: 0.9, y: 0.1),
            bottomRight: NormalizedPoint(x: 0.45, y: 0.45),
            bottomLeft: NormalizedPoint(x: 0.1, y: 0.9)
        )

        XCTAssertFalse(quadrilateral.isValid())
    }

    func testRejectsCollapsedEdge() {
        let quadrilateral = NormalizedQuadrilateral(
            topLeft: NormalizedPoint(x: 0.1, y: 0.1),
            topRight: NormalizedPoint(x: 0.105, y: 0.1),
            bottomRight: NormalizedPoint(x: 0.9, y: 0.9),
            bottomLeft: NormalizedPoint(x: 0.1, y: 0.9)
        )

        XCTAssertFalse(quadrilateral.isValid())
    }

    func testRejectsSemanticallySwappedTopCorners() {
        let quadrilateral = NormalizedQuadrilateral(
            topLeft: NormalizedPoint(x: 0.9, y: 0.1),
            topRight: NormalizedPoint(x: 0.1, y: 0.1),
            bottomRight: NormalizedPoint(x: 0.9, y: 0.9),
            bottomLeft: NormalizedPoint(x: 0.1, y: 0.9)
        )

        XCTAssertFalse(quadrilateral.isValid())
    }

    func testPolygonIoUDistinguishesTiltedRegionsWithIdenticalBoundingBoxes() {
        let first = NormalizedQuadrilateral(
            topLeft: NormalizedPoint(x: 0, y: 0),
            topRight: NormalizedPoint(x: 0.6, y: 0),
            bottomRight: NormalizedPoint(x: 1, y: 1),
            bottomLeft: NormalizedPoint(x: 0.4, y: 1)
        )
        let second = NormalizedQuadrilateral(
            topLeft: NormalizedPoint(x: 0.4, y: 0),
            topRight: NormalizedPoint(x: 1, y: 0),
            bottomRight: NormalizedPoint(x: 0.6, y: 1),
            bottomLeft: NormalizedPoint(x: 0, y: 1)
        )

        XCTAssertTrue(first.isValid())
        XCTAssertTrue(second.isValid())
        XCTAssertEqual(first.boundingBoxIntersectionOverUnion(with: second), 1)
        XCTAssertLessThan(first.intersectionOverUnion(with: second), 0.8)
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

    func testCorrectedPreviewLayoutScalesFromFitSizeAndKeepsImageScrollable() {
        let sourceImageSize = CGSize(width: 1_200, height: 800)
        let viewportSize = CGSize(width: 600, height: 400)
        let fitLayout = CorrectedPreviewLayout(
            sourceImageSize: sourceImageSize,
            viewportSize: viewportSize,
            zoom: 1
        )
        let zoomedLayout = CorrectedPreviewLayout(
            sourceImageSize: sourceImageSize,
            viewportSize: viewportSize,
            zoom: 3
        )

        XCTAssertLessThanOrEqual(
            fitLayout.imageSize.width,
            viewportSize.width - CorrectedPreviewLayout.contentPadding * 2
        )
        XCTAssertLessThanOrEqual(
            fitLayout.imageSize.height,
            viewportSize.height - CorrectedPreviewLayout.contentPadding * 2
        )
        XCTAssertEqual(zoomedLayout.imageSize.width, fitLayout.imageSize.width * 3, accuracy: 0.001)
        XCTAssertEqual(zoomedLayout.imageSize.height, fitLayout.imageSize.height * 3, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(
            zoomedLayout.contentSize.width,
            zoomedLayout.imageSize.width + CorrectedPreviewLayout.contentPadding * 2
        )
        XCTAssertGreaterThanOrEqual(
            zoomedLayout.contentSize.height,
            zoomedLayout.imageSize.height + CorrectedPreviewLayout.contentPadding * 2
        )
    }
}
