import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import ScanPhotoEditor

final class ImagePipelineTests: XCTestCase {
    func testAllEXIFOrientationsNormalizeToExpectedDimensions() throws {
        let image = try makeTestImage(width: 30, height: 20)

        for orientation in 1 ... 8 {
            let data = try encode(image: image, type: .tiff, orientation: orientation)
            let loaded = try ImageLoader.loadUprightImage(data: data)
            if orientation >= 5 {
                XCTAssertEqual(loaded.image.width, 20, "orientation \(orientation)")
                XCTAssertEqual(loaded.image.height, 30, "orientation \(orientation)")
            } else {
                XCTAssertEqual(loaded.image.width, 30, "orientation \(orientation)")
                XCTAssertEqual(loaded.image.height, 20, "orientation \(orientation)")
            }
        }
    }

    func testIdentityPerspectiveRenderPreservesDimensions() throws {
        let image = try makeTestImage(width: 80, height: 50)
        let region = PhotoRegion(
            id: UUID(),
            sourceID: UUID(),
            quadrilateral: .fullFrame,
            origin: .manual,
            reviewState: .ready,
            rotation: .zero,
            flipHorizontal: false,
            flipVertical: false,
            order: 0,
            isManuallyEdited: true
        )

        let rendered = try PerspectiveRenderer.render(source: image, region: region)

        XCTAssertEqual(rendered.width, image.width)
        XCTAssertEqual(rendered.height, image.height)
    }

    func testVisionDetectsGeneratedRectangle() async throws {
        let image = try makeRectangleFixture()

        let candidates = try await RectangleDetectionService.detect(in: image)

        XCTAssertFalse(candidates.isEmpty)
        XCTAssertLessThanOrEqual(
            candidates.count,
            DetectionPreferences.defaultMaximumDetections
        )
        XCTAssertTrue(candidates.allSatisfy { $0.quadrilateral.isValid() })
    }

    func testMaximumDetectionPreferenceIsClampedToSupportedRange() {
        XCTAssertGreaterThan(DetectionPreferences.defaultMaximumDetections, 1)
        XCTAssertEqual(
            DetectionPreferences.normalizedMaximumDetections(0),
            DetectionPreferences.maximumDetectionsRange.lowerBound
        )
        XCTAssertEqual(
            DetectionPreferences.normalizedMaximumDetections(100),
            DetectionPreferences.maximumDetectionsRange.upperBound
        )
    }

    func testExportQualityPreferenceIsClampedToSupportedRange() {
        XCTAssertEqual(
            ExportPreferences.normalizedQualityPercent(0),
            ExportPreferences.qualityPercentRange.lowerBound
        )
        XCTAssertEqual(
            ExportPreferences.normalizedQualityPercent(101),
            ExportPreferences.qualityPercentRange.upperBound
        )
        XCTAssertEqual(ExportPreferences.quality(from: 80), 0.8, accuracy: 0.001)
    }

    func testEveryImageExportFormatDecodes() throws {
        let image = try makeTestImage(width: 64, height: 48)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        for format in ExportImageFormat.allCases {
            let output = try ImageExportService.export(
                image: image,
                format: format,
                quality: 0.95,
                baseName: "test",
                destinationDirectory: directory
            )
            XCTAssertTrue(FileManager.default.fileExists(atPath: output.path))
            let source = CGImageSourceCreateWithURL(output as CFURL, nil)
            XCTAssertNotNil(source, format.label)
            XCTAssertNotNil(source.flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) })
        }
    }

    func testOpaqueEncodingImageDoesNotCarryAlpha() throws {
        let image = try makeTestImage(width: 64, height: 48)
        let opaqueImage = try XCTUnwrap(ImageRenderingContext.opaqueImage(from: image))

        XCTAssertTrue(
            [.none, .noneSkipFirst, .noneSkipLast].contains(opaqueImage.alphaInfo)
        )
    }

    func testPDFPageCountMatchesOrderedImages() throws {
        let first = try makeTestImage(width: 60, height: 40)
        let second = try makeTestImage(width: 40, height: 60)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let output = try PDFExportService.export(
            images: [("first", first), ("second", second)],
            quality: 0.8,
            destinationDirectory: directory
        )
        let document = CGPDFDocument(output as CFURL)
        let pdfData = try Data(contentsOf: output)

        XCTAssertEqual(document?.numberOfPages, 2)
        XCTAssertTrue(
            String(decoding: pdfData, as: UTF8.self).contains("/DCTDecode"),
            "PDF page images should use JPEG compression."
        )
    }

    @MainActor
    func testProcessingCoordinatorCompletesOneHundredSmallImages() async throws {
        let image = try makeTestImage(width: 64, height: 48)
        let data = try encode(image: image, type: .png, orientation: 1)
        let localURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")
        try data.write(to: localURL)
        defer { try? FileManager.default.removeItem(at: localURL) }
        let images = (0 ..< 100).map { index in
            ImportedImage(
                url: URL(fileURLWithPath: "/tmp/synthetic-\(index).png"),
                localURL: localURL,
                typeIdentifier: UTType.png.identifier
            )
        }
        let coordinator = ProcessingCoordinator()
        let collector = ProcessedImportCollector()

        let completed = await coordinator.process(
            images: images,
            startingImportOrder: 0,
            maximumDetections: DetectionPreferences.defaultMaximumDetections,
            onProcessed: { item, _, _ in
                collector.items.append(item)
            }
        )
        let processed = collector.items

        XCTAssertEqual(completed, 100)
        XCTAssertEqual(processed.count, 100)
        XCTAssertEqual(Set(processed.map(\.source.importOrder)), Set(0 ..< 100))
        XCTAssertTrue(processed.allSatisfy { $0.source.processingState == .ready })
    }

    func testPDFExportRemovesPartialFileWhenPageRenderingFails() throws {
        let image = try makeTestImage(width: 64, height: 48)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        XCTAssertThrowsError(
            try PDFExportService.export(
                pageCount: 2,
                quality: 0.8,
                destinationDirectory: directory,
                imageProvider: { index in
                    if index == 1 {
                        throw TestError.fixtureCreationFailed
                    }
                    return image
                }
            )
        )
        let partials = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "partial" }
        XCTAssertTrue(partials.isEmpty)
    }

    func testMissingThumbnailIsRegeneratedDuringPackageDecode() throws {
        let image = try makeTestImage(width: 64, height: 48)
        let data = try encode(image: image, type: .png, orientation: 1)
        let sourceID = UUID()
        let region = PhotoRegion(
            id: UUID(),
            sourceID: sourceID,
            quadrilateral: .fullFrame,
            origin: .manual,
            reviewState: .ready,
            rotation: .zero,
            flipHorizontal: false,
            flipVertical: false,
            order: 0,
            isManuallyEdited: true
        )
        let source = SourceAsset(
            id: sourceID,
            displayName: "Source",
            storedFilename: "\(sourceID).png",
            typeIdentifier: UTType.png.identifier,
            pixelWidth: 64,
            pixelHeight: 48,
            importOrder: 0,
            processingState: .ready,
            processingError: nil,
            regions: [region]
        )
        var manifest = ProjectManifest.empty()
        manifest.sources = [source]
        manifest.regionOrder = [region.id]
        let storage = ProjectFileStorage()
        try storage.prepare()
        let originalURL = try storage.writeOriginal(data, filename: source.storedFilename)
        let snapshot = ProjectSnapshot(
            manifest: manifest,
            storage: storage,
            originals: [source.storedFilename: originalURL],
            thumbnails: [:]
        )

        let decoded = try ProjectPackageCodec.decode(ProjectPackageCodec.encode(snapshot))

        XCTAssertNotNil(decoded.thumbnails["\(sourceID.uuidString).jpg"])
    }

    @MainActor
    func testPDFOnlyExportSupportsMultipleRegionsFromOneSource() async throws {
        let image = try makeTestImage(width: 64, height: 48)
        let data = try encode(image: image, type: .png, orientation: 1)
        let stagedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")
        try data.write(to: stagedURL)
        let outputDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: stagedURL)
            try? FileManager.default.removeItem(at: outputDirectory)
        }

        let sourceID = UUID()
        let regions = (0 ..< 2).map { order in
            PhotoRegion(
                id: UUID(),
                sourceID: sourceID,
                quadrilateral: .fullFrame,
                origin: .manual,
                reviewState: .ready,
                rotation: .zero,
                flipHorizontal: false,
                flipVertical: false,
                order: order,
                isManuallyEdited: true
            )
        }
        let source = SourceAsset(
            id: sourceID,
            displayName: "Source",
            storedFilename: "\(sourceID).png",
            typeIdentifier: UTType.png.identifier,
            pixelWidth: 64,
            pixelHeight: 48,
            importOrder: 0,
            processingState: .ready,
            processingError: nil,
            regions: regions
        )
        let document = PhotoProjectDocument()
        try document.setImportedFile(
            at: stagedURL,
            thumbnailData: nil,
            source: source
        )
        let store = ProjectEditingStore(document: document)
        store.exportOptions = ExportOptions(
            formats: [],
            includePDF: true,
            selectedRegionIDs: nil
        )

        store.export(to: outputDirectory)
        for _ in 0 ..< 500 where store.isExporting {
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertFalse(store.isExporting)
        XCTAssertFalse(store.exportWasCancelled)
        XCTAssertEqual(store.exportProgress, 1, accuracy: 0.000_001)
        let output = try XCTUnwrap(store.exportReport?.exportedURLs.first)
        XCTAssertEqual(CGPDFDocument(output as CFURL)?.numberOfPages, 2)
    }

    private func makeTestImage(width: Int, height: Int) throws -> CGImage {
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw TestError.fixtureCreationFailed
        }
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.7, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(red: 0.9, green: 0.3, blue: 0.1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width / 3, height: height / 2))
        guard let image = context.makeImage() else {
            throw TestError.fixtureCreationFailed
        }
        return image
    }

    private func makeRectangleFixture() throws -> CGImage {
        guard let context = CGContext(
            data: nil,
            width: 800,
            height: 600,
            bitsPerComponent: 8,
            bytesPerRow: 800 * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw TestError.fixtureCreationFailed
        }
        context.setFillColor(CGColor(gray: 0.05, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 800, height: 600))
        context.setFillColor(CGColor(gray: 0.98, alpha: 1))
        context.fill(CGRect(x: 120, y: 90, width: 560, height: 420))
        guard let image = context.makeImage() else {
            throw TestError.fixtureCreationFailed
        }
        return image
    }

    private func encode(
        image: CGImage,
        type: UTType,
        orientation: Int
    ) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            type.identifier as CFString,
            1,
            nil
        ) else {
            throw TestError.fixtureCreationFailed
        }
        CGImageDestinationAddImage(
            destination,
            image,
            [kCGImagePropertyOrientation: orientation] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else {
            throw TestError.fixtureCreationFailed
        }
        return data as Data
    }
}

@MainActor
private final class ProcessedImportCollector {
    var items: [ProcessedImport] = []
}

private enum TestError: Error {
    case fixtureCreationFailed
}
