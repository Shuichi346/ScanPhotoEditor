import AppKit
import CoreGraphics
import Foundation
import Observation

@MainActor
@Observable
final class ProjectEditingStore {
    let document: PhotoProjectDocument

    var selectedRegionID: UUID?
    var showGrid = true
    var zoom: CGFloat = 1
    var isDropTargeted = false
    var isExportPresented = false
    var exportOptions = ExportOptions()
    var exportProgress: Double = 0
    var isExporting = false
    var exportReport: ExportReport?
    var exportWasCancelled = false
    var sourcePreview: CGImage?
    var correctedPreview: CGImage?
    var confirmationMessage: String?

    private let processingCoordinator = ProcessingCoordinator()
    private var pendingDetectionSourceID: UUID?
    private var importTask: Task<Void, Never>?
    private var rerunTask: Task<Void, Never>?
    private var exportTask: Task<Void, Never>?

    init(document: PhotoProjectDocument) {
        self.document = document
        selectedRegionID = document.manifest.regionOrder.first
        refreshPreviews()
    }

    var selectedSource: SourceAsset? {
        guard let selectedRegionID else {
            return document.manifest.sources
                .min(by: { $0.importOrder < $1.importOrder })
        }
        return document.manifest.sources.first {
            $0.regions.contains(where: { $0.id == selectedRegionID })
        }
    }

    var selectedRegion: PhotoRegion? {
        guard let selectedRegionID else { return nil }
        return document.manifest.sources
            .lazy
            .flatMap(\.regions)
            .first(where: { $0.id == selectedRegionID })
    }

    var orderedRegions: [(source: SourceAsset, region: PhotoRegion)] {
        var lookup: [UUID: (source: SourceAsset, region: PhotoRegion)] = [:]
        for source in document.manifest.sources {
            for region in source.regions where lookup[region.id] == nil {
                lookup[region.id] = (source, region)
            }
        }
        return document.manifest.regionOrder.compactMap { lookup[$0] }
    }

    func orderedRegions(for sourceID: UUID) -> [PhotoRegion] {
        orderedRegions.compactMap { item in
            item.source.id == sourceID ? item.region : nil
        }
    }

    func select(regionID: UUID?) {
        selectedRegionID = regionID
        refreshPreviews()
    }

    func importDroppedURLs(_ urls: [URL]) {
        importTask?.cancel()
        Task {
            await processingCoordinator.cancel()
        }
        document.isProcessing = true
        document.activityMessage = "Discovering images…"
        document.processingProgress = 0

        let discoveryTask = Task.detached(priority: .userInitiated) {
            try ImageImportService.discoverAndStage(urls: urls)
        }
        importTask = Task { [weak self] in
            guard let self else { return }
            do {
                let discovery = try await withTaskCancellationHandler {
                    try await discoveryTask.value
                } onCancel: {
                    discoveryTask.cancel()
                }
                defer {
                    try? FileManager.default.removeItem(at: discovery.stagingDirectory)
                }
                try Task.checkCancellation()

                document.lastImportReport = discovery.report
                guard !discovery.images.isEmpty else {
                    document.isProcessing = false
                    document.activityMessage = "No supported images found."
                    return
                }

                document.activityMessage = "Detecting photographs…"
                let completed = await processingCoordinator.process(
                    images: discovery.images,
                    startingImportOrder: nextImportOrder,
                    maximumDetections: DetectionPreferences.maximumDetections
                ) { [weak self] item, completed, total in
                    guard let self else { return }
                    do {
                        try document.setImportedFile(
                            at: item.importedImage.localURL,
                            thumbnailData: item.thumbnailData,
                            source: item.source
                        )
                        document.processingProgress = Double(completed) / Double(total)
                        if selectedRegionID == nil, let first = item.source.regions.first {
                            selectedRegionID = first.id
                            refreshPreviews()
                        }
                    } catch {
                        document.lastImportReport?.failures.append(
                            "\(item.source.displayName): \(error.localizedDescription)"
                        )
                    }
                }
                try Task.checkCancellation()

                document.isProcessing = false
                document.activityMessage = "Imported \(completed) image\(completed == 1 ? "" : "s")."
            } catch is CancellationError {
                return
            } catch {
                document.isProcessing = false
                document.projectError = error.localizedDescription
            }
        }
    }

    func cancelProcessing() {
        importTask?.cancel()
        Task {
            await processingCoordinator.cancel()
        }
        document.isProcessing = false
        document.activityMessage = "Processing cancelled."
    }

    func setQuadrilateral(
        _ quadrilateral: NormalizedQuadrilateral,
        registerUndoFrom previous: NormalizedQuadrilateral? = nil,
        undoManager: UndoManager? = nil
    ) {
        guard quadrilateral.isValid(),
              var source = selectedSource,
              let selectedRegionID,
              let index = source.regions.firstIndex(where: { $0.id == selectedRegionID })
        else {
            return
        }
        let oldValue = previous ?? source.regions[index].quadrilateral
        source.regions[index].quadrilateral = quadrilateral
        source.regions[index].isManuallyEdited = true
        source.regions[index].reviewState = .ready
        source.regions[index].origin = .manual
        document.updateSource(source)
        refreshCorrectedPreview()

        if let undoManager, previous != nil {
            undoManager.registerUndo(withTarget: self) { target in
                target.setQuadrilateral(
                    oldValue,
                    registerUndoFrom: quadrilateral,
                    undoManager: undoManager
                )
            }
            undoManager.setActionName("Adjust Region")
        }
    }

    func addRegion(undoManager: UndoManager?) {
        guard var source = selectedSource else { return }
        let region = PhotoRegion(
            id: UUID(),
            sourceID: source.id,
            quadrilateral: .centered,
            origin: .manual,
            reviewState: .needsReview,
            rotation: .zero,
            flipHorizontal: false,
            flipVertical: false,
            order: source.regions.count,
            isManuallyEdited: true
        )
        source.regions.append(region)
        document.updateSource(source)
        let sourceRegionIDs = Set(source.regions.map(\.id))
        let insertionIndex = document.manifest.regionOrder.lastIndex(where: sourceRegionIDs.contains)
            .map { $0 + 1 }
            ?? document.manifest.regionOrder.count
        document.manifest.regionOrder.insert(region.id, at: insertionIndex)
        document.reconcileRegionOrdering()
        selectedRegionID = region.id
        refreshPreviews()

        undoManager?.registerUndo(withTarget: self) { target in
            target.deleteRegion(id: region.id, undoManager: undoManager)
        }
        undoManager?.setActionName("Add Region")
    }

    func deleteSelectedRegion(undoManager: UndoManager?) {
        guard let selectedRegionID else { return }
        deleteRegion(id: selectedRegionID, undoManager: undoManager)
    }

    func deleteRegion(id: UUID, undoManager: UndoManager?) {
        guard var source = document.manifest.sources.first(where: {
            $0.regions.contains(where: { $0.id == id })
        }), let index = source.regions.firstIndex(where: { $0.id == id }) else {
            return
        }
        let removed = source.regions.remove(at: index)
        let orderIndex = document.manifest.regionOrder.firstIndex(of: id)
            ?? document.manifest.regionOrder.count
        document.manifest.regionOrder.removeAll(where: { $0 == id })
        document.updateSource(source)
        document.reconcileRegionOrdering()
        selectedRegionID = document.manifest.regionOrder.first
        refreshPreviews()

        undoManager?.registerUndo(withTarget: self) { target in
            target.restoreRegion(
                removed,
                sourceID: source.id,
                sourceIndex: index,
                orderIndex: orderIndex,
                undoManager: undoManager
            )
        }
        undoManager?.setActionName("Delete Region")
    }

    func removeSelectedSource(undoManager: UndoManager?) {
        guard let sourceID = selectedSource?.id else { return }
        removeSource(id: sourceID, undoManager: undoManager)
    }

    func rotateClockwise(undoManager: UndoManager?) {
        mutateSelectedRegion(actionName: "Rotate Region", undoManager: undoManager) {
            $0.rotation = $0.rotation.next
            $0.isManuallyEdited = true
        }
    }

    func flipHorizontal(undoManager: UndoManager?) {
        mutateSelectedRegion(actionName: "Flip Region Horizontally", undoManager: undoManager) {
            $0.flipHorizontal.toggle()
            $0.isManuallyEdited = true
        }
    }

    func flipVertical(undoManager: UndoManager?) {
        mutateSelectedRegion(actionName: "Flip Region Vertically", undoManager: undoManager) {
            $0.flipVertical.toggle()
            $0.isManuallyEdited = true
        }
    }

    func resetSelectedRegion(undoManager: UndoManager?) {
        mutateSelectedRegion(actionName: "Reset Region", undoManager: undoManager) {
            $0.quadrilateral = .fullFrame
            $0.rotation = .zero
            $0.flipHorizontal = false
            $0.flipVertical = false
            $0.reviewState = .needsReview
            $0.isManuallyEdited = true
        }
    }

    func rerunDetection(force: Bool = false, undoManager: UndoManager?) {
        let sourceID = force ? (pendingDetectionSourceID ?? selectedSource?.id) : selectedSource?.id
        guard let sourceID,
              let source = document.manifest.sources.first(where: { $0.id == sourceID }),
              let originalURL = document.originalURL(for: source)
        else {
            return
        }
        if !force, source.regions.contains(where: \.isManuallyEdited) {
            pendingDetectionSourceID = source.id
            confirmationMessage = "Rerunning detection replaces manually edited regions for this source."
            return
        }
        pendingDetectionSourceID = nil
        confirmationMessage = nil
        let previous = source.regions
        let maximumDetections = DetectionPreferences.maximumDetections
        rerunTask?.cancel()
        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let loaded = try ImageLoader.loadUprightImage(
                url: originalURL,
                maximumDimension: 2_048
            )
            let candidates = try await RectangleDetectionService.detect(
                in: loaded.image,
                maximumDetections: maximumDetections
            )
            try Task.checkCancellation()
            return Self.makeRegions(candidates: candidates, sourceID: source.id)
        }
        rerunTask = Task { [weak self] in
            guard let self else { return }
            do {
                let regions = try await withTaskCancellationHandler {
                    try await worker.value
                } onCancel: {
                    worker.cancel()
                }
                guard let currentSource = document.manifest.sources.first(where: {
                    $0.id == source.id
                }), currentSource.regions == previous else {
                    document.projectError =
                        "Detection results were not applied because the source changed while detection was running."
                    return
                }
                document.replaceRegions(for: source.id, with: regions)
                selectedRegionID = regions.first?.id
                refreshPreviews()

                undoManager?.registerUndo(withTarget: self) { target in
                    target.replaceRegions(
                        sourceID: source.id,
                        regions: previous,
                        undoManager: undoManager,
                        inverse: regions
                    )
                }
                undoManager?.setActionName("Rerun Detection")
            } catch is CancellationError {
                return
            } catch {
                document.projectError = error.localizedDescription
            }
        }
    }

    func cancelRerunDetectionConfirmation() {
        confirmationMessage = nil
        pendingDetectionSourceID = nil
    }

    func moveRegions(
        in sourceID: UUID,
        from offsets: IndexSet,
        to destination: Int,
        undoManager: UndoManager?
    ) {
        let previous = document.manifest.regionOrder
        var sourceOrder = orderedRegions(for: sourceID).map(\.id)
        sourceOrder.move(fromOffsets: offsets, toOffset: destination)
        let sourceIDs = Set(sourceOrder)
        var iterator = sourceOrder.makeIterator()
        let next = previous.map { id in
            sourceIDs.contains(id) ? (iterator.next() ?? id) : id
        }
        setRegionOrder(next, inverse: previous, undoManager: undoManager)
        undoManager?.setActionName("Reorder Regions")
    }

    func moveSources(
        from offsets: IndexSet,
        to destination: Int,
        undoManager: UndoManager?
    ) {
        let previousSources = document.manifest.sources
        let previousRegionOrder = document.manifest.regionOrder
        var orderedSources = previousSources.sorted { $0.importOrder < $1.importOrder }
        orderedSources.move(fromOffsets: offsets, toOffset: destination)
        for index in orderedSources.indices {
            orderedSources[index].importOrder = index
        }
        let positions = regionPositions(previousRegionOrder)
        let nextRegionOrder = orderedSources.flatMap { source in
            source.regions
                .sorted {
                    positions[$0.id, default: Int.max] < positions[$1.id, default: Int.max]
                }
                .map(\.id)
        }
        setImageOrdering(
            sources: orderedSources,
            regionOrder: nextRegionOrder,
            inverseSources: previousSources,
            inverseRegionOrder: previousRegionOrder,
            undoManager: undoManager
        )
        undoManager?.setActionName("Reorder Images")
    }

    func sortImagesByFileName(undoManager: UndoManager?) {
        let previousSources = document.manifest.sources
        let previousRegionOrder = document.manifest.regionOrder
        guard previousSources.count > 1 else { return }

        var sortedSources = previousSources.sorted { lhs, rhs in
            let comparison = lhs.displayName.localizedStandardCompare(rhs.displayName)
            if comparison != .orderedSame {
                return comparison == .orderedAscending
            }
            if lhs.importOrder != rhs.importOrder {
                return lhs.importOrder < rhs.importOrder
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        for index in sortedSources.indices {
            sortedSources[index].importOrder = index
        }

        let currentPositions = regionPositions(previousRegionOrder)
        let nextRegionOrder = sortedSources.flatMap { source in
            source.regions
                .sorted {
                    currentPositions[$0.id, default: Int.max]
                        < currentPositions[$1.id, default: Int.max]
                }
                .map(\.id)
        }

        setImageOrdering(
            sources: sortedSources,
            regionOrder: nextRegionOrder,
            inverseSources: previousSources,
            inverseRegionOrder: previousRegionOrder,
            undoManager: undoManager
        )
        undoManager?.setActionName("Sort Images by File Name")
    }

    func refreshPreviews() {
        guard let source = selectedSource, let url = document.originalURL(for: source) else {
            sourcePreview = nil
            correctedPreview = nil
            return
        }
        do {
            sourcePreview = try ImageLoader.loadUprightImage(
                url: url,
                maximumDimension: 1_600
            ).image
            refreshCorrectedPreview()
        } catch {
            sourcePreview = nil
            correctedPreview = nil
            document.projectError = error.localizedDescription
        }
    }

    func refreshCorrectedPreview() {
        guard let sourcePreview, let selectedRegion else {
            correctedPreview = nil
            return
        }
        do {
            correctedPreview = try PerspectiveRenderer.render(
                source: sourcePreview,
                region: selectedRegion,
                maximumDimension: 1_200
            )
        } catch {
            correctedPreview = nil
            document.projectError = error.localizedDescription
        }
    }

    func export(to directory: URL) {
        exportTask?.cancel()
        do {
            let options = exportOptions
            let selectedItems = orderedRegions.filter { item in
                options.selectedRegionIDs?.contains(item.region.id) ?? true
            }
            guard !selectedItems.isEmpty else {
                document.projectError = "Select a region before exporting."
                return
            }
            let snapshot = try document.snapshot(contentType: .scanPhotoProject)
            let batchItems = selectedItems.compactMap { item -> ExportWorkItem? in
                guard let originalURL = snapshot.originals[item.source.storedFilename] else {
                    return nil
                }
                return ExportWorkItem(
                    sourceName: item.source.displayName,
                    region: item.region,
                    originalURL: originalURL,
                    baseName: "\(item.source.displayName)_\(item.region.order + 1)"
                )
            }
            let batch = ExportBatch(items: batchItems, storage: snapshot.storage)
            isExporting = true
            exportProgress = 0
            exportReport = nil
            exportWasCancelled = false

            let progress = AsyncStream.makeStream(of: Double.self)
            let worker = Task.detached(priority: .userInitiated) {
                Self.performExport(
                    batch: batch,
                    options: options,
                    directory: directory,
                    progress: progress.continuation
                )
            }
            exportTask = Task { [weak self] in
                guard let self else {
                    worker.cancel()
                    progress.continuation.finish()
                    return
                }
                let progressTask = Task { [weak self] in
                    for await value in progress.stream {
                        self?.exportProgress = value
                    }
                }
                let result = await withTaskCancellationHandler {
                    await worker.value
                } onCancel: {
                    worker.cancel()
                }
                progress.continuation.finish()
                await progressTask.value

                exportReport = result.report
                exportWasCancelled = result.cancelled || Task.isCancelled
                if result.cancelled || Task.isCancelled {
                    document.activityMessage = "Export cancelled."
                } else {
                    let count = result.report.exportedURLs.count
                    document.activityMessage =
                        "Exported \(count) file\(count == 1 ? "" : "s")."
                }
                isExporting = false
            }
        } catch {
            isExporting = false
            document.projectError = error.localizedDescription
        }
    }

    func cancelExport() {
        exportTask?.cancel()
    }

    func prepareForExportPresentation() {
        guard !isExporting else { return }
        exportProgress = 0
        exportReport = nil
        exportWasCancelled = false
    }

    private var nextImportOrder: Int {
        (document.manifest.sources.map(\.importOrder).max() ?? -1) + 1
    }

    private func regionPositions(_ order: [UUID]) -> [UUID: Int] {
        var positions: [UUID: Int] = [:]
        for (index, id) in order.enumerated() where positions[id] == nil {
            positions[id] = index
        }
        return positions
    }

    private func mutateSelectedRegion(
        actionName: String,
        undoManager: UndoManager?,
        mutation: (inout PhotoRegion) -> Void
    ) {
        guard var source = selectedSource,
              let selectedRegionID,
              let index = source.regions.firstIndex(where: { $0.id == selectedRegionID })
        else {
            return
        }
        let previous = source.regions[index]
        mutation(&source.regions[index])
        let next = source.regions[index]
        document.updateSource(source)
        refreshCorrectedPreview()

        undoManager?.registerUndo(withTarget: self) { target in
            target.setRegion(previous, inverse: next, undoManager: undoManager)
        }
        undoManager?.setActionName(actionName)
    }

    private func setRegion(
        _ region: PhotoRegion,
        inverse: PhotoRegion,
        undoManager: UndoManager?
    ) {
        guard var source = document.manifest.sources.first(where: { $0.id == region.sourceID }),
              let index = source.regions.firstIndex(where: { $0.id == region.id })
        else {
            return
        }
        source.regions[index] = region
        document.updateSource(source)
        refreshCorrectedPreview()
        undoManager?.registerUndo(withTarget: self) { target in
            target.setRegion(inverse, inverse: region, undoManager: undoManager)
        }
    }

    private func restoreRegion(
        _ region: PhotoRegion,
        sourceID: UUID,
        sourceIndex: Int,
        orderIndex: Int,
        undoManager: UndoManager?
    ) {
        guard var source = document.manifest.sources.first(where: { $0.id == sourceID }) else {
            return
        }
        source.regions.insert(region, at: min(sourceIndex, source.regions.count))
        document.updateSource(source)
        document.manifest.regionOrder.insert(
            region.id,
            at: min(orderIndex, document.manifest.regionOrder.count)
        )
        document.reconcileRegionOrdering()
        selectedRegionID = region.id
        refreshPreviews()
        undoManager?.registerUndo(withTarget: self) { target in
            target.deleteRegion(id: region.id, undoManager: undoManager)
        }
    }

    private func removeSource(id: UUID, undoManager: UndoManager?) {
        do {
            guard let record = try document.removeSource(id: id) else { return }
            selectedRegionID = document.manifest.regionOrder.first
            refreshPreviews()
            undoManager?.registerUndo(withTarget: self) { target in
                target.restoreSource(record, undoManager: undoManager)
            }
            undoManager?.setActionName("Remove Source")
        } catch {
            document.projectError = error.localizedDescription
        }
    }

    private func restoreSource(
        _ record: RemovedSourceRecord,
        undoManager: UndoManager?
    ) {
        do {
            try document.restoreSource(record)
            selectedRegionID = record.source.regions.first?.id
            refreshPreviews()
            undoManager?.registerUndo(withTarget: self) { target in
                target.removeSource(id: record.source.id, undoManager: undoManager)
            }
        } catch {
            document.projectError = error.localizedDescription
        }
    }

    private func replaceRegions(
        sourceID: UUID,
        regions: [PhotoRegion],
        undoManager: UndoManager?,
        inverse: [PhotoRegion]
    ) {
        document.replaceRegions(for: sourceID, with: regions)
        selectedRegionID = regions.first?.id
        refreshPreviews()
        undoManager?.registerUndo(withTarget: self) { target in
            target.replaceRegions(
                sourceID: sourceID,
                regions: inverse,
                undoManager: undoManager,
                inverse: regions
            )
        }
    }

    private func setRegionOrder(
        _ order: [UUID],
        inverse: [UUID],
        undoManager: UndoManager?
    ) {
        document.manifest.regionOrder = order
        document.reconcileRegionOrdering()
        document.manifest.modifiedAt = Date()
        undoManager?.registerUndo(withTarget: self) { target in
            target.setRegionOrder(inverse, inverse: order, undoManager: undoManager)
        }
    }

    private func setImageOrdering(
        sources: [SourceAsset],
        regionOrder: [UUID],
        inverseSources: [SourceAsset],
        inverseRegionOrder: [UUID],
        undoManager: UndoManager?
    ) {
        document.manifest.sources = sources
        document.manifest.regionOrder = regionOrder
        document.reconcileRegionOrdering()
        document.manifest.modifiedAt = Date()
        undoManager?.registerUndo(withTarget: self) { target in
            target.setImageOrdering(
                sources: inverseSources,
                regionOrder: inverseRegionOrder,
                inverseSources: sources,
                inverseRegionOrder: regionOrder,
                undoManager: undoManager
            )
        }
    }

    private nonisolated static func makeRegions(
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

    private nonisolated static func performExport(
        batch: ExportBatch,
        options: ExportOptions,
        directory: URL,
        progress: AsyncStream<Double>.Continuation
    ) -> ExportWorkResult {
        _ = batch.storage
        var report = ExportReport()
        let formats = ExportImageFormat.allCases.filter(options.formats.contains)
        let stepsPerItem = formats.count + (options.includePDF ? 1 : 0)
        let totalSteps = max(1, batch.items.count * stepsPerItem)
        var completedSteps = 0
        let accessed = directory.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                directory.stopAccessingSecurityScopedResource()
            }
        }

        for item in batch.items {
            if Task.isCancelled {
                return ExportWorkResult(report: report, cancelled: true)
            }
            guard !formats.isEmpty else { continue }
            do {
                let rendered = try autoreleasepool {
                    let source = try ImageLoader.loadUprightImage(url: item.originalURL).image
                    return try PerspectiveRenderer.render(source: source, region: item.region)
                }
                for format in formats {
                    if Task.isCancelled {
                        return ExportWorkResult(report: report, cancelled: true)
                    }
                    do {
                        let url = try ImageExportService.export(
                            image: rendered,
                            format: format,
                            quality: options.quality(for: format),
                            baseName: item.baseName,
                            destinationDirectory: directory
                        )
                        report.exportedURLs.append(url)
                    } catch {
                        report.failures.append(
                            ExportFailure(
                                item: "\(item.baseName).\(format.fileExtension)",
                                message: error.localizedDescription
                            )
                        )
                    }
                    completedSteps += 1
                    progress.yield(Double(completedSteps) / Double(totalSteps))
                }
            } catch {
                for format in formats {
                    report.failures.append(
                        ExportFailure(
                            item: "\(item.baseName).\(format.fileExtension)",
                            message: error.localizedDescription
                        )
                    )
                    completedSteps += 1
                    progress.yield(Double(completedSteps) / Double(totalSteps))
                }
            }
        }

        if options.includePDF, !Task.isCancelled {
            var completedPDFPages = 0
            do {
                let url = try PDFExportService.export(
                    pageCount: batch.items.count,
                    quality: options.pdfQuality,
                    destinationDirectory: directory,
                    imageProvider: { index in
                        try autoreleasepool {
                            try Task.checkCancellation()
                            let item = batch.items[index]
                            let source = try ImageLoader.loadUprightImage(
                                url: item.originalURL
                            ).image
                            return try PerspectiveRenderer.render(
                                source: source,
                                region: item.region
                            )
                        }
                    },
                    didCompletePage: { pages in
                        completedSteps += pages - completedPDFPages
                        completedPDFPages = pages
                        progress.yield(Double(completedSteps) / Double(totalSteps))
                    }
                )
                report.exportedURLs.append(url)
            } catch is CancellationError {
                return ExportWorkResult(report: report, cancelled: true)
            } catch {
                completedSteps += batch.items.count - completedPDFPages
                progress.yield(Double(completedSteps) / Double(totalSteps))
                report.failures.append(
                    ExportFailure(item: "Combined PDF", message: error.localizedDescription)
                )
            }
        }
        return ExportWorkResult(
            report: report,
            cancelled: Task.isCancelled
        )
    }
}

private struct ExportWorkItem: Sendable {
    let sourceName: String
    let region: PhotoRegion
    let originalURL: URL
    let baseName: String
}

private struct ExportBatch: @unchecked Sendable {
    let items: [ExportWorkItem]
    let storage: ProjectFileStorage
}

private struct ExportWorkResult: Sendable {
    let report: ExportReport
    let cancelled: Bool
}
