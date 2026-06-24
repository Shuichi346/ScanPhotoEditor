import CoreGraphics
import Foundation

struct ProcessedImport: Sendable {
    let importedImage: ImportedImage
    let source: SourceAsset
    let thumbnailData: Data?
}

actor ProcessingCoordinator {
    private var isCancelled = false

    func cancel() {
        isCancelled = true
    }

    func process(
        images: [ImportedImage],
        startingImportOrder: Int,
        maximumDetections: Int
    ) async -> [ProcessedImport] {
        isCancelled = false
        var iterator = images.enumerated().makeIterator()
        var results: [ProcessedImport] = []

        await withTaskGroup(of: ProcessedImport?.self) { group in
            for _ in 0 ..< min(2, images.count) {
                if let item = iterator.next() {
                    group.addTask {
                        await Self.processOne(
                            item.element,
                            importOrder: startingImportOrder + item.offset,
                            maximumDetections: maximumDetections
                        )
                    }
                }
            }

            while let result = await group.next() {
                if let result {
                    results.append(result)
                }
                guard !isCancelled, let item = iterator.next() else { continue }
                group.addTask {
                    await Self.processOne(
                        item.element,
                        importOrder: startingImportOrder + item.offset,
                        maximumDetections: maximumDetections
                    )
                }
            }
        }
        return results.sorted { $0.source.importOrder < $1.source.importOrder }
    }

    private static func processOne(
        _ imported: ImportedImage,
        importOrder: Int,
        maximumDetections: Int
    ) async -> ProcessedImport? {
        let sourceID = UUID()
        let fileExtension = imported.url.pathExtension.lowercased()
        let storedFilename = "\(sourceID.uuidString).\(fileExtension)"

        do {
            let metadata = try ImageLoader.metadata(data: imported.data)
            let detectionImage = try ImageLoader.loadUprightImage(
                data: imported.data,
                maximumDimension: 2_048
            )
            let thumbnailData = try? ImageLoader.jpegThumbnail(data: imported.data)
            let candidates = try await RectangleDetectionService.detect(
                in: detectionImage.image,
                maximumDetections: maximumDetections
            )
            let regions: [PhotoRegion]
            if candidates.isEmpty {
                regions = [
                    PhotoRegion(
                        id: UUID(),
                        sourceID: sourceID,
                        quadrilateral: .fullFrame,
                        origin: .fallback,
                        reviewState: .needsReview,
                        rotation: .zero,
                        flipHorizontal: false,
                        flipVertical: false,
                        order: 0,
                        isManuallyEdited: false
                    )
                ]
            } else {
                regions = candidates.enumerated().map { index, candidate in
                    PhotoRegion(
                        id: UUID(),
                        sourceID: sourceID,
                        quadrilateral: candidate.quadrilateral,
                        origin: .automatic,
                        reviewState: .ready,
                        rotation: .zero,
                        flipHorizontal: false,
                        flipVertical: false,
                        order: index,
                        isManuallyEdited: false
                    )
                }
            }
            let source = SourceAsset(
                id: sourceID,
                displayName: imported.url.deletingPathExtension().lastPathComponent,
                storedFilename: storedFilename,
                typeIdentifier: metadata.typeIdentifier ?? imported.typeIdentifier,
                pixelWidth: Int(metadata.uprightPixelSize.width),
                pixelHeight: Int(metadata.uprightPixelSize.height),
                importOrder: importOrder,
                processingState: .ready,
                processingError: nil,
                regions: regions
            )
            return ProcessedImport(
                importedImage: imported,
                source: source,
                thumbnailData: thumbnailData
            )
        } catch {
            let source = SourceAsset(
                id: sourceID,
                displayName: imported.url.deletingPathExtension().lastPathComponent,
                storedFilename: storedFilename,
                typeIdentifier: imported.typeIdentifier,
                pixelWidth: 0,
                pixelHeight: 0,
                importOrder: importOrder,
                processingState: .failed,
                processingError: error.localizedDescription,
                regions: []
            )
            return ProcessedImport(
                importedImage: imported,
                source: source,
                thumbnailData: nil
            )
        }
    }
}
