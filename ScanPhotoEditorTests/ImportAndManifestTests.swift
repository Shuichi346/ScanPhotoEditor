import Foundation
import XCTest
@testable import ScanPhotoEditor

final class ImportAndManifestTests: XCTestCase {
    func testGeometryCanvasLayoutContainsZoomedImageAtOneHundredThirtyPercent() {
        let layout = GeometryCanvasLayout(
            imageSize: CGSize(width: 1002, height: 721),
            viewportSize: CGSize(width: 900, height: 330),
            zoom: 1.3
        )

        XCTAssertGreaterThan(layout.contentSize.height, 330)
        XCTAssertLessThanOrEqual(layout.imageRect.maxX, layout.contentSize.width)
        XCTAssertLessThanOrEqual(layout.imageRect.maxY, layout.contentSize.height)
        XCTAssertGreaterThanOrEqual(layout.imageRect.minX, 0)
        XCTAssertGreaterThanOrEqual(layout.imageRect.minY, 0)
    }

    func testRecursiveDiscoverySkipsHiddenUnsupportedAndSymlinkFiles() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let nested = root.appendingPathComponent("Nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let jpeg = nested.appendingPathComponent("photo.jpg")
        let unsupported = nested.appendingPathComponent("notes.txt")
        let hidden = nested.appendingPathComponent(".hidden.jpg")
        let symlink = root.appendingPathComponent("linked.jpg")
        try Data([0xFF, 0xD8, 0xFF, 0xD9]).write(to: jpeg)
        try Data("text".utf8).write(to: unsupported)
        try Data([0xFF, 0xD8, 0xFF, 0xD9]).write(to: hidden)
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: jpeg)

        let result = ImageImportService.discoverAndRead(urls: [root])

        XCTAssertEqual(
            result.images.map(\.url.lastPathComponent),
            ["photo.jpg"],
            "skipped=\(result.report.skipped), failures=\(result.report.failures)"
        )
        XCTAssertTrue(result.report.skipped.contains("linked.jpg"))
    }

    func testManifestJSONRoundTripPreservesIdentityAndOrdering() throws {
        let sourceID = UUID()
        let regionID = UUID()
        let region = PhotoRegion(
            id: regionID,
            sourceID: sourceID,
            quadrilateral: .centered,
            origin: .manual,
            reviewState: .ready,
            rotation: .clockwise90,
            flipHorizontal: true,
            flipVertical: false,
            order: 0,
            isManuallyEdited: true
        )
        let source = SourceAsset(
            id: sourceID,
            displayName: "Source",
            storedFilename: "\(sourceID).jpg",
            typeIdentifier: "public.jpeg",
            pixelWidth: 100,
            pixelHeight: 80,
            importOrder: 0,
            processingState: .ready,
            processingError: nil,
            regions: [region]
        )
        let manifest = ProjectManifest(
            schemaVersion: 1,
            projectID: UUID(),
            createdAt: Date(timeIntervalSince1970: 100),
            modifiedAt: Date(timeIntervalSince1970: 200),
            sources: [source],
            regionOrder: [regionID]
        )

        let data = try JSONEncoder().encode(manifest)
        let decoded = try JSONDecoder().decode(ProjectManifest.self, from: data)

        XCTAssertEqual(decoded, manifest)
    }

    @MainActor
    func testSortImagesByFileNameUsesNaturalOrderAndIsUndoable() {
        let document = PhotoProjectDocument()
        let first = makeSource(displayName: "Album 10", importOrder: 0, regionCount: 1)
        let second = makeSource(displayName: "Album 2", importOrder: 1, regionCount: 2)
        let third = makeSource(displayName: "Album 1", importOrder: 2, regionCount: 1)
        document.manifest.sources = [first, second, third]
        document.manifest.regionOrder = [
            first.regions[0].id,
            second.regions[1].id,
            third.regions[0].id,
            second.regions[0].id,
        ]
        let originalRegionOrder = document.manifest.regionOrder
        let store = ProjectEditingStore(document: document)
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false

        undoManager.beginUndoGrouping()
        store.sortImagesByFileName(undoManager: undoManager)
        undoManager.endUndoGrouping()

        XCTAssertEqual(
            document.manifest.sources
                .sorted(by: { $0.importOrder < $1.importOrder })
                .map(\.displayName),
            ["Album 1", "Album 2", "Album 10"]
        )
        XCTAssertEqual(
            document.manifest.regionOrder,
            [
                third.regions[0].id,
                second.regions[1].id,
                second.regions[0].id,
                first.regions[0].id,
            ]
        )

        undoManager.undo()

        XCTAssertEqual(
            document.manifest.sources
                .sorted(by: { $0.importOrder < $1.importOrder })
                .map(\.displayName),
            ["Album 10", "Album 2", "Album 1"]
        )
        XCTAssertEqual(document.manifest.regionOrder, originalRegionOrder)
    }

    @MainActor
    func testDocumentStoresImportedOriginalAndThumbnail() {
        let document = PhotoProjectDocument()
        let sourceID = UUID()
        let source = SourceAsset(
            id: sourceID,
            displayName: "Source",
            storedFilename: "\(sourceID).jpg",
            typeIdentifier: "public.jpeg",
            pixelWidth: 10,
            pixelHeight: 10,
            importOrder: 0,
            processingState: .ready,
            processingError: nil,
            regions: []
        )

        document.setImportedData(Data([1, 2, 3]), thumbnailData: Data([4, 5]), source: source)

        XCTAssertEqual(document.originalData(for: source), Data([1, 2, 3]))
        XCTAssertEqual(document.thumbnailData(for: sourceID), Data([4, 5]))
        XCTAssertEqual(document.manifest.sources, [source])
    }

    func testProjectPackageRoundTripPreservesManifestAndBytes() throws {
        let sourceID = UUID()
        let source = SourceAsset(
            id: sourceID,
            displayName: "Source",
            storedFilename: "\(sourceID).png",
            typeIdentifier: "public.png",
            pixelWidth: 40,
            pixelHeight: 30,
            importOrder: 0,
            processingState: .ready,
            processingError: nil,
            regions: [
                PhotoRegion(
                    id: UUID(),
                    sourceID: sourceID,
                    quadrilateral: .centered,
                    origin: .manual,
                    reviewState: .ready,
                    rotation: .clockwise270,
                    flipHorizontal: false,
                    flipVertical: true,
                    order: 0,
                    isManuallyEdited: true
                )
            ]
        )
        var manifest = ProjectManifest.empty()
        manifest.createdAt = Date(timeIntervalSince1970: 100)
        manifest.modifiedAt = Date(timeIntervalSince1970: 200)
        manifest.sources = [source]
        manifest.regionOrder = source.regions.map(\.id)
        let snapshot = ProjectSnapshot(
            manifest: manifest,
            originals: [source.storedFilename: Data([1, 2, 3, 4])],
            thumbnails: ["\(sourceID.uuidString).jpg": Data([5, 6, 7])]
        )

        let wrapper = try ProjectPackageCodec.encode(snapshot)
        let decoded = try ProjectPackageCodec.decode(wrapper)

        XCTAssertEqual(decoded.manifest, snapshot.manifest)
        XCTAssertEqual(decoded.originals, snapshot.originals)
        XCTAssertEqual(decoded.thumbnails, snapshot.thumbnails)
    }

    func testPackageDecodeReportsMissingOriginal() throws {
        let sourceID = UUID()
        let source = SourceAsset(
            id: sourceID,
            displayName: "Missing",
            storedFilename: "\(sourceID).jpg",
            typeIdentifier: "public.jpeg",
            pixelWidth: 1,
            pixelHeight: 1,
            importOrder: 0,
            processingState: .ready,
            processingError: nil,
            regions: []
        )
        var manifest = ProjectManifest.empty()
        manifest.createdAt = Date(timeIntervalSince1970: 100)
        manifest.modifiedAt = Date(timeIntervalSince1970: 200)
        manifest.sources = [source]
        let wrapper = try ProjectPackageCodec.encode(
            ProjectSnapshot(manifest: manifest, originals: [:], thumbnails: [:])
        )

        XCTAssertThrowsError(try ProjectPackageCodec.decode(wrapper)) { error in
            guard case ProjectDocumentError.missingOriginal(source.storedFilename) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    private func makeSource(
        displayName: String,
        importOrder: Int,
        regionCount: Int
    ) -> SourceAsset {
        let sourceID = UUID()
        let regions = (0 ..< regionCount).map { order in
            PhotoRegion(
                id: UUID(),
                sourceID: sourceID,
                quadrilateral: .centered,
                origin: .manual,
                reviewState: .ready,
                rotation: .zero,
                flipHorizontal: false,
                flipVertical: false,
                order: order,
                isManuallyEdited: true
            )
        }
        return SourceAsset(
            id: sourceID,
            displayName: displayName,
            storedFilename: "\(sourceID).jpg",
            typeIdentifier: "public.jpeg",
            pixelWidth: 100,
            pixelHeight: 80,
            importOrder: importOrder,
            processingState: .ready,
            processingError: nil,
            regions: regions
        )
    }
}
