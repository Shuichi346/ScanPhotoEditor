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

        let result = try ImageImportService.discoverAndStage(urls: [root])
        defer { try? FileManager.default.removeItem(at: result.stagingDirectory) }

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
    func testDocumentStoresImportedOriginalAndThumbnailOnDisk() throws {
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

        let stagedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try Data([1, 2, 3]).write(to: stagedURL)
        defer { try? FileManager.default.removeItem(at: stagedURL) }
        try document.setImportedFile(
            at: stagedURL,
            thumbnailData: Data([4, 5]),
            source: source
        )

        let originalURL = try XCTUnwrap(document.originalURL(for: source))
        XCTAssertEqual(try Data(contentsOf: originalURL), Data([1, 2, 3]))
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
        let snapshot = try makeSnapshot(
            manifest: manifest,
            originalBytes: [source.storedFilename: Data([1, 2, 3, 4])],
            thumbnails: ["\(sourceID.uuidString).jpg": Data([5, 6, 7])]
        )

        let wrapper = try ProjectPackageCodec.encode(snapshot)
        let decoded = try ProjectPackageCodec.decode(wrapper)

        XCTAssertEqual(decoded.manifest, snapshot.manifest)
        XCTAssertEqual(
            try decoded.originals.mapValues { try Data(contentsOf: $0) },
            [source.storedFilename: Data([1, 2, 3, 4])]
        )
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
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let manifestWrapper = FileWrapper(
            regularFileWithContents: try encoder.encode(manifest)
        )
        manifestWrapper.preferredFilename = "manifest.json"
        let originalsWrapper = FileWrapper(directoryWithFileWrappers: [:])
        originalsWrapper.preferredFilename = "Originals"
        let wrapper = FileWrapper(
            directoryWithFileWrappers: [
                "manifest.json": manifestWrapper,
                "Originals": originalsWrapper,
            ]
        )

        XCTAssertThrowsError(try ProjectPackageCodec.decode(wrapper)) { error in
            guard case ProjectDocumentError.missingOriginal(source.storedFilename) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testPackageEncodeRejectsMissingOriginal() throws {
        let source = makeSource(displayName: "Missing", importOrder: 0, regionCount: 1)
        var manifest = ProjectManifest.empty()
        manifest.sources = [source]
        manifest.regionOrder = source.regions.map(\.id)
        let storage = ProjectFileStorage()
        let snapshot = ProjectSnapshot(
            manifest: manifest,
            storage: storage,
            originals: [:],
            thumbnails: [:]
        )

        XCTAssertThrowsError(try ProjectPackageCodec.encode(snapshot))
    }

    func testPackageDecodeRejectsDuplicateRegionOrderEntries() throws {
        let source = makeSource(displayName: "Duplicate", importOrder: 0, regionCount: 1)
        var manifest = ProjectManifest.empty()
        manifest.sources = [source]
        manifest.regionOrder = [source.regions[0].id, source.regions[0].id]
        let snapshot = try makeSnapshot(
            manifest: manifest,
            originalBytes: [source.storedFilename: Data([1])],
            thumbnails: [:]
        )

        XCTAssertThrowsError(try ProjectPackageCodec.encode(snapshot)) { error in
            guard case ProjectDocumentError.invalidManifest = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testEncodedFileWrapperRemainsReadableAfterSnapshotRelease() throws {
        let source = makeSource(displayName: "Source", importOrder: 0, regionCount: 1)
        var manifest = ProjectManifest.empty()
        manifest.sources = [source]
        manifest.regionOrder = source.regions.map(\.id)

        let wrapper = try makeEncodedWrapper(
            manifest: manifest,
            originalBytes: [source.storedFilename: Data([1, 2, 3])]
        )
        let decoded = try ProjectPackageCodec.decode(wrapper)

        XCTAssertEqual(
            try Data(contentsOf: XCTUnwrap(decoded.originals[source.storedFilename])),
            Data([1, 2, 3])
        )
    }

    func testDocumentSavesAndReloadsFromBackgroundQueue() async throws {
        let source = makeSource(displayName: "Background", importOrder: 0, regionCount: 2)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let stagedURL = root.appendingPathComponent("staged.jpg")
        let packageURL = root.appendingPathComponent("Background.scanphoto", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data([1, 2, 3, 4]).write(to: stagedURL)
        defer { try? FileManager.default.removeItem(at: root) }

        let result = try await Task.detached {
            let document = PhotoProjectDocument()
            try document.setImportedFile(
                at: stagedURL,
                thumbnailData: nil,
                source: source
            )
            let snapshot = try document.snapshot(contentType: .scanPhotoProject)
            let wrapper = try ProjectPackageCodec.encode(snapshot)
            try wrapper.write(
                to: packageURL,
                options: .atomic,
                originalContentsURL: nil
            )
            let reopenedWrapper = try FileWrapper(
                url: packageURL,
                options: [.immediate, .withoutMapping]
            )
            let reopened = try ProjectPackageCodec.decode(reopenedWrapper)
            guard let reopenedOriginalURL = reopened.originals[source.storedFilename] else {
                throw ProjectDocumentError.missingOriginal(source.storedFilename)
            }
            return (
                reopened.manifest,
                try Data(contentsOf: reopenedOriginalURL)
            )
        }.value

        XCTAssertEqual(result.0.sources.map(\.id), [source.id])
        XCTAssertEqual(result.0.regionOrder, source.regions.map(\.id))
        XCTAssertEqual(result.1, Data([1, 2, 3, 4]))
    }

    @MainActor
    func testReplacingRegionsPreservesSourcePositionInGlobalOrder() {
        let document = PhotoProjectDocument()
        let first = makeSource(displayName: "First", importOrder: 0, regionCount: 1)
        let middle = makeSource(displayName: "Middle", importOrder: 1, regionCount: 1)
        let last = makeSource(displayName: "Last", importOrder: 2, regionCount: 1)
        document.manifest.sources = [first, middle, last]
        document.manifest.regionOrder = [
            first.regions[0].id,
            middle.regions[0].id,
            last.regions[0].id,
        ]
        let replacements = makeSource(
            displayName: "Replacement",
            importOrder: 1,
            regionCount: 2
        ).regions.map { region in
            var region = region
            region.sourceID = middle.id
            return region
        }

        document.replaceRegions(for: middle.id, with: replacements)

        XCTAssertEqual(
            document.manifest.regionOrder,
            [first.regions[0].id] + replacements.map(\.id) + [last.regions[0].id]
        )
        XCTAssertEqual(
            document.manifest.sources.first(where: { $0.id == middle.id })?.regions.map(\.order),
            [0, 1]
        )
    }

    @MainActor
    func testOrderedRegionsSupportsMultipleRegionsFromOneSource() {
        let document = PhotoProjectDocument()
        let source = makeSource(displayName: "Multi", importOrder: 0, regionCount: 3)
        document.manifest.sources = [source]
        document.manifest.regionOrder = source.regions.map(\.id)

        let store = ProjectEditingStore(document: document)

        XCTAssertEqual(store.orderedRegions.map(\.region.id), source.regions.map(\.id))
    }

    @MainActor
    func testGeometryActionsMutateTheSelectedRegion() throws {
        let document = PhotoProjectDocument()
        let source = makeSource(displayName: "Source", importOrder: 0, regionCount: 1)
        document.manifest.sources = [source]
        document.manifest.regionOrder = source.regions.map(\.id)
        let store = ProjectEditingStore(document: document)

        store.rotateClockwise(undoManager: nil)
        store.flipHorizontal(undoManager: nil)
        store.flipVertical(undoManager: nil)

        let transformed = try XCTUnwrap(store.selectedRegion)
        XCTAssertEqual(transformed.rotation, .clockwise90)
        XCTAssertTrue(transformed.flipHorizontal)
        XCTAssertTrue(transformed.flipVertical)

        store.resetSelectedRegion(undoManager: nil)

        let reset = try XCTUnwrap(store.selectedRegion)
        XCTAssertEqual(reset.quadrilateral, .fullFrame)
        XCTAssertEqual(reset.rotation, .zero)
        XCTAssertFalse(reset.flipHorizontal)
        XCTAssertFalse(reset.flipVertical)
        XCTAssertEqual(reset.reviewState, .needsReview)
    }

    @MainActor
    func testRemovingAndRestoringSourceMovesOriginalOutOfManifest() throws {
        let document = PhotoProjectDocument()
        let source = makeSource(displayName: "Source", importOrder: 0, regionCount: 1)
        let stagedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try Data([1, 2, 3]).write(to: stagedURL)
        defer { try? FileManager.default.removeItem(at: stagedURL) }
        try document.setImportedFile(
            at: stagedURL,
            thumbnailData: Data([4, 5]),
            source: source
        )

        let record = try XCTUnwrap(document.removeSource(id: source.id))

        XCTAssertTrue(document.manifest.sources.isEmpty)
        XCTAssertTrue(document.manifest.regionOrder.isEmpty)
        XCTAssertNil(document.originalURL(for: source))

        try document.restoreSource(record)

        XCTAssertEqual(document.manifest.sources.map(\.id), [source.id])
        XCTAssertEqual(document.manifest.regionOrder, source.regions.map(\.id))
        XCTAssertEqual(
            try Data(contentsOf: XCTUnwrap(document.originalURL(for: source))),
            Data([1, 2, 3])
        )
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

    private func makeSnapshot(
        manifest: ProjectManifest,
        originalBytes: [String: Data],
        thumbnails: [String: Data]
    ) throws -> ProjectSnapshot {
        let storage = ProjectFileStorage()
        try storage.prepare()
        var originals: [String: URL] = [:]
        for (filename, data) in originalBytes {
            originals[filename] = try storage.writeOriginal(data, filename: filename)
        }
        return ProjectSnapshot(
            manifest: manifest,
            storage: storage,
            originals: originals,
            thumbnails: thumbnails
        )
    }

    private func makeEncodedWrapper(
        manifest: ProjectManifest,
        originalBytes: [String: Data]
    ) throws -> FileWrapper {
        let snapshot = try makeSnapshot(
            manifest: manifest,
            originalBytes: originalBytes,
            thumbnails: [:]
        )
        return try ProjectPackageCodec.encode(snapshot)
    }
}
