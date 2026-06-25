import CoreGraphics
import Foundation

struct ProcessedImport: Sendable {
    let importedImage: ImportedImage
    let source: SourceAsset
    let thumbnailData: Data?
}

actor ProcessingCoordinator {
    private var activeTask: Task<Int, Never>?
    private var activeID: UUID?

    func cancel() {
        activeTask?.cancel()
        activeTask = nil
        activeID = nil
    }

    func process(
        images: [ImportedImage],
        startingImportOrder: Int,
        maximumDetections: Int,
        onProcessed: @escaping @MainActor @Sendable (
            _ item: ProcessedImport,
            _ completed: Int,
            _ total: Int
        ) -> Void
    ) async -> Int {
        activeTask?.cancel()
        let taskID = UUID()
        let task = Task.detached(priority: .userInitiated) {
            await Self.run(
                images: images,
                startingImportOrder: startingImportOrder,
                maximumDetections: maximumDetections,
                onProcessed: onProcessed
            )
        }
        activeTask = task
        activeID = taskID
        let completed = await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        if activeID == taskID {
            activeTask = nil
            activeID = nil
        }
        return completed
    }

    private static func run(
        images: [ImportedImage],
        startingImportOrder: Int,
        maximumDetections: Int,
        onProcessed: @escaping @MainActor @Sendable (
            _ item: ProcessedImport,
            _ completed: Int,
            _ total: Int
        ) -> Void
    ) async -> Int {
        var iterator = images.enumerated().makeIterator()
        var completed = 0

        await withTaskGroup(of: ProcessedImport?.self) { group in
            for _ in 0 ..< min(2, images.count) {
                guard !Task.isCancelled, let item = iterator.next() else { break }
                group.addTask {
                    await processOne(
                        item.element,
                        importOrder: startingImportOrder + item.offset,
                        maximumDetections: maximumDetections
                    )
                }
            }

            while let result = await group.next() {
                if Task.isCancelled {
                    group.cancelAll()
                    break
                }
                if let result {
                    completed += 1
                    await onProcessed(result, completed, images.count)
                }
                guard let item = iterator.next() else { continue }
                group.addTask {
                    await processOne(
                        item.element,
                        importOrder: startingImportOrder + item.offset,
                        maximumDetections: maximumDetections
                    )
                }
            }
        }
        return completed
    }

    private static func processOne(
        _ imported: ImportedImage,
        importOrder: Int,
        maximumDetections: Int
    ) async -> ProcessedImport? {
        guard !Task.isCancelled else { return nil }
        let sourceID = UUID()
        let fileExtension = imported.url.pathExtension.lowercased()
        let storedFilename = "\(sourceID.uuidString).\(fileExtension)"

        do {
            let metadata = try ImageLoader.metadata(url: imported.localURL)
            try Task.checkCancellation()
            let detectionImage = try ImageLoader.loadUprightImage(
                url: imported.localURL,
                maximumDimension: 2_048
            )
            try Task.checkCancellation()
            let thumbnailData = try? ImageLoader.jpegThumbnail(url: imported.localURL)
            let candidates = try await RectangleDetectionService.detect(
                in: detectionImage.image,
                maximumDetections: maximumDetections
            )
            try Task.checkCancellation()
            let regions = makeRegions(candidates: candidates, sourceID: sourceID)
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
        } catch is CancellationError {
            return nil
        } catch {
            let metadata = try? ImageLoader.metadata(url: imported.localURL)
            let source = SourceAsset(
                id: sourceID,
                displayName: imported.url.deletingPathExtension().lastPathComponent,
                storedFilename: storedFilename,
                typeIdentifier: metadata?.typeIdentifier ?? imported.typeIdentifier,
                pixelWidth: Int(metadata?.uprightPixelSize.width ?? 0),
                pixelHeight: Int(metadata?.uprightPixelSize.height ?? 0),
                importOrder: importOrder,
                processingState: .failed,
                processingError: error.localizedDescription,
                regions: makeRegions(candidates: [], sourceID: sourceID)
            )
            return ProcessedImport(
                importedImage: imported,
                source: source,
                thumbnailData: try? ImageLoader.jpegThumbnail(url: imported.localURL)
            )
        }
    }

    private static func makeRegions(
        candidates: [DetectionCandidate],
        sourceID: UUID
    ) -> [PhotoRegion] {
        let values = candidates.isEmpty
            ? [(NormalizedQuadrilateral.fullFrame, RegionOrigin.fallback, ReviewState.needsReview)]
            : candidates.map { ($0.quadrilateral, .automatic, .ready) }
        return values.enumerated().map { index, value in
            PhotoRegion(
                id: UUID(),
                sourceID: sourceID,
                quadrilateral: value.0,
                origin: value.1,
                reviewState: value.2,
                rotation: .zero,
                flipHorizontal: false,
                flipVertical: false,
                order: index,
                isManuallyEdited: false
            )
        }
    }
}
