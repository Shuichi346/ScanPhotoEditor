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
    var sourcePreview: CGImage?
    var correctedPreview: CGImage?
    var confirmationMessage: String?

    private let processingCoordinator = ProcessingCoordinator()
    private var importTask: Task<Void, Never>?
    private var exportTask: Task<Void, Never>?

    init(document: PhotoProjectDocument) {
        self.document = document
        selectedRegionID = document.manifest.regionOrder.first
        refreshPreviews()
    }

    var selectedSource: SourceAsset? {
        guard let selectedRegionID else {
            return document.manifest.sources.first
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
        let all = document.manifest.sources.flatMap { source in
            source.regions.map { (source, $0) }
        }
        let lookup = Dictionary(uniqueKeysWithValues: all.map { ($0.1.id, $0) })
        return document.manifest.regionOrder.compactMap { lookup[$0] }
    }

    func select(regionID: UUID?) {
        selectedRegionID = regionID
        refreshPreviews()
    }

    func importDroppedURLs(_ urls: [URL]) {
        importTask?.cancel()
        document.isProcessing = true
        document.activityMessage = "Discovering images…"
        document.processingProgress = 0

        importTask = Task {
            let discovery = await Task.detached(priority: .userInitiated) {
                ImageImportService.discoverAndRead(urls: urls)
            }.value
            guard !Task.isCancelled else { return }

            document.lastImportReport = discovery.report
            guard !discovery.images.isEmpty else {
                document.isProcessing = false
                document.activityMessage = "No supported images found."
                return
            }

            document.activityMessage = "Detecting photographs…"
            let processed = await processingCoordinator.process(
                images: discovery.images,
                startingImportOrder: document.manifest.sources.count,
                maximumDetections: DetectionPreferences.maximumDetections
            )
            guard !Task.isCancelled else { return }

            for (index, item) in processed.enumerated() {
                document.setImportedData(
                    item.importedImage.data,
                    thumbnailData: item.thumbnailData,
                    source: item.source
                )
                document.manifest.regionOrder.append(contentsOf: item.source.regions.map(\.id))
                document.processingProgress = Double(index + 1) / Double(processed.count)
                if selectedRegionID == nil, let first = item.source.regions.first {
                    selectedRegionID = first.id
                }
            }
            document.isProcessing = false
            document.activityMessage = "Imported \(processed.count) image\(processed.count == 1 ? "" : "s")."
            refreshPreviews()
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
        guard var source = selectedSource,
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
        guard var source = selectedSource ?? document.manifest.sources.first else { return }
        let region = PhotoRegion(
            id: UUID(),
            sourceID: source.id,
            quadrilateral: .centered,
            origin: .manual,
            reviewState: .needsReview,
            rotation: .zero,
            flipHorizontal: false,
            flipVertical: false,
            order: document.manifest.regionOrder.count,
            isManuallyEdited: true
        )
        source.regions.append(region)
        document.updateSource(source)
        document.manifest.regionOrder.append(region.id)
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
        guard let source = selectedSource, let data = document.originalData(for: source) else { return }
        if !force, source.regions.contains(where: \.isManuallyEdited) {
            confirmationMessage = "Rerunning detection replaces manually edited regions for this source."
            return
        }

        Task {
            do {
                let loaded = try ImageLoader.loadUprightImage(data: data, maximumDimension: 2_048)
                let candidates = try await RectangleDetectionService.detect(
                    in: loaded.image,
                    maximumDetections: DetectionPreferences.maximumDetections
                )
                let regions = Self.makeRegions(
                    candidates: candidates,
                    sourceID: source.id
                )
                let previous = source.regions
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
            } catch {
                document.projectError = error.localizedDescription
            }
        }
    }

    func moveRegions(from offsets: IndexSet, to destination: Int, undoManager: UndoManager?) {
        let previous = document.manifest.regionOrder
        document.manifest.regionOrder.move(fromOffsets: offsets, toOffset: destination)
        document.manifest.modifiedAt = Date()
        let next = document.manifest.regionOrder
        undoManager?.registerUndo(withTarget: self) { target in
            target.setRegionOrder(previous, inverse: next, undoManager: undoManager)
        }
        undoManager?.setActionName("Reorder Regions")
    }

    func sortImagesByFileName(undoManager: UndoManager?) {
        let previousSources = document.manifest.sources
        let previousRegionOrder = document.manifest.regionOrder
        guard previousSources.count > 1 else { return }

        let sortedSources = previousSources.sorted { lhs, rhs in
            let comparison = lhs.displayName.localizedStandardCompare(rhs.displayName)
            if comparison != .orderedSame {
                return comparison == .orderedAscending
            }
            if lhs.importOrder != rhs.importOrder {
                return lhs.importOrder < rhs.importOrder
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }

        var updatedSources = previousSources
        for (importOrder, source) in sortedSources.enumerated() {
            guard let index = updatedSources.firstIndex(where: { $0.id == source.id }) else {
                continue
            }
            updatedSources[index].importOrder = importOrder
        }

        let currentPositions = Dictionary(
            uniqueKeysWithValues: previousRegionOrder.enumerated().map { ($0.element, $0.offset) }
        )
        let sortedRegionOrder = sortedSources.flatMap { source in
            source.regions
                .sorted {
                    currentPositions[$0.id, default: Int.max]
                        < currentPositions[$1.id, default: Int.max]
                }
                .map(\.id)
        }
        let sortedRegionIDs = Set(sortedRegionOrder)
        let nextRegionOrder = sortedRegionOrder
            + previousRegionOrder.filter { !sortedRegionIDs.contains($0) }

        setImageOrdering(
            sources: updatedSources,
            regionOrder: nextRegionOrder,
            inverseSources: previousSources,
            inverseRegionOrder: previousRegionOrder,
            undoManager: undoManager
        )
        undoManager?.setActionName("Sort Images by File Name")
    }

    func refreshPreviews() {
        guard let source = selectedSource, let data = document.originalData(for: source) else {
            sourcePreview = nil
            correctedPreview = nil
            return
        }
        do {
            sourcePreview = try ImageLoader.loadUprightImage(
                data: data,
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
        isExporting = true
        exportProgress = 0
        exportReport = nil
        let options = exportOptions
        let items = orderedRegions.filter { item in
            options.selectedRegionIDs?.contains(item.region.id) ?? true
        }
        let originals = Dictionary(
            uniqueKeysWithValues: items.compactMap { item in
                document.originalData(for: item.source).map { (item.source.id, $0) }
            }
        )

        exportTask = Task {
            var report = ExportReport()
            var pdfImages: [(name: String, image: CGImage)] = []
            let totalSteps = max(1, items.count * max(1, options.formats.count) + (options.includePDF ? 1 : 0))
            var completedSteps = 0

            for (index, item) in items.enumerated() {
                if Task.isCancelled { break }
                autoreleasepool {
                    guard let data = originals[item.source.id] else {
                        report.failures.append(
                            ExportFailure(
                                item: item.source.displayName,
                                message: "Original image is missing."
                            )
                        )
                        return
                    }
                    do {
                        let source = try ImageLoader.loadUprightImage(data: data).image
                        let rendered = try PerspectiveRenderer.render(
                            source: source,
                            region: item.region
                        )
                        let baseName = "\(item.source.displayName)_\(index + 1)"
                        for format in options.formats {
                            if Task.isCancelled { return }
                            do {
                                let url = try ImageExportService.export(
                                    image: rendered,
                                    format: format,
                                    quality: options.quality(for: format),
                                    baseName: baseName,
                                    destinationDirectory: directory
                                )
                                report.exportedURLs.append(url)
                            } catch {
                                report.failures.append(
                                    ExportFailure(
                                        item: "\(baseName).\(format.fileExtension)",
                                        message: error.localizedDescription
                                    )
                                )
                            }
                            completedSteps += 1
                            exportProgress = Double(completedSteps) / Double(totalSteps)
                        }
                        if options.includePDF {
                            pdfImages.append((baseName, rendered))
                        }
                    } catch {
                        report.failures.append(
                            ExportFailure(
                                item: item.source.displayName,
                                message: error.localizedDescription
                            )
                        )
                    }
                }
            }

            if options.includePDF, !Task.isCancelled {
                do {
                    let url = try PDFExportService.export(
                        images: pdfImages,
                        quality: options.pdfQuality,
                        destinationDirectory: directory
                    )
                    report.exportedURLs.append(url)
                } catch {
                    report.failures.append(
                        ExportFailure(item: "Combined PDF", message: error.localizedDescription)
                    )
                }
                completedSteps += 1
                exportProgress = Double(completedSteps) / Double(totalSteps)
            }

            if Task.isCancelled {
                document.activityMessage = "Export cancelled."
            } else {
                document.activityMessage = "Exported \(report.exportedURLs.count) file\(report.exportedURLs.count == 1 ? "" : "s")."
            }
            exportReport = report
            isExporting = false
        }
    }

    func cancelExport() {
        exportTask?.cancel()
        isExporting = false
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
        selectedRegionID = region.id
        refreshPreviews()
        undoManager?.registerUndo(withTarget: self) { target in
            target.deleteRegion(id: region.id, undoManager: undoManager)
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
