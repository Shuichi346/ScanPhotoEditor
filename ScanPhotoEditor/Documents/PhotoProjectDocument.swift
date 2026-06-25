import Combine
import Foundation
import SwiftUI
import UniformTypeIdentifiers

enum ProjectDocumentError: LocalizedError {
    case invalidPackage
    case invalidManifest(String)
    case unsupportedSchema(Int)
    case missingOriginal(String)

    var errorDescription: String? {
        switch self {
        case .invalidPackage:
            "The selected file is not a valid ScanPhotoEditor project."
        case let .invalidManifest(reason):
            "The project manifest is invalid: \(reason)"
        case let .unsupportedSchema(version):
            "This project uses unsupported schema version \(version)."
        case let .missingOriginal(filename):
            "The project is missing original image \(filename)."
        }
    }
}

final class ProjectFileStorage: @unchecked Sendable {
    let rootURL: URL
    let originalsURL: URL
    let removedURL: URL

    init() {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScanPhotoEditor", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        originalsURL = rootURL.appendingPathComponent("Originals", isDirectory: true)
        removedURL = rootURL.appendingPathComponent("Removed", isDirectory: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: rootURL)
    }

    func prepare() throws {
        try FileManager.default.createDirectory(
            at: originalsURL,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: removedURL,
            withIntermediateDirectories: true
        )
    }

    func originalURL(filename: String) -> URL {
        originalsURL.appendingPathComponent(filename, isDirectory: false)
    }

    func adoptOriginal(at sourceURL: URL, filename: String) throws -> URL {
        try prepare()
        let destinationURL = originalURL(filename: filename)
        let partialURL = destinationURL.appendingPathExtension("partial")
        try? FileManager.default.removeItem(at: partialURL)
        try? FileManager.default.removeItem(at: destinationURL)
        do {
            do {
                try FileManager.default.moveItem(at: sourceURL, to: partialURL)
            } catch {
                try FileManager.default.copyItem(at: sourceURL, to: partialURL)
            }
            try FileManager.default.moveItem(at: partialURL, to: destinationURL)
            return destinationURL
        } catch {
            try? FileManager.default.removeItem(at: partialURL)
            throw error
        }
    }

    func writeOriginal(_ data: Data, filename: String) throws -> URL {
        try prepare()
        let destinationURL = originalURL(filename: filename)
        try data.write(to: destinationURL, options: .atomic)
        return destinationURL
    }

    func removeOriginal(filename: String) throws -> URL {
        try prepare()
        let sourceURL = originalURL(filename: filename)
        let destinationURL = removedURL
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(sourceURL.pathExtension)
        try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
        return destinationURL
    }

    func restoreOriginal(from removedOriginalURL: URL, filename: String) throws {
        try prepare()
        let destinationURL = originalURL(filename: filename)
        try? FileManager.default.removeItem(at: destinationURL)
        try FileManager.default.moveItem(at: removedOriginalURL, to: destinationURL)
    }

    func immutableSnapshot(filenames: [String]) throws -> ProjectFileStorage {
        let snapshot = ProjectFileStorage()
        try snapshot.prepare()
        for filename in filenames {
            let sourceURL = originalURL(filename: filename)
            let destinationURL = snapshot.originalURL(filename: filename)
            do {
                try FileManager.default.linkItem(at: sourceURL, to: destinationURL)
            } catch {
                try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            }
        }
        return snapshot
    }
}

struct ProjectSnapshot: @unchecked Sendable {
    let manifest: ProjectManifest
    let storage: ProjectFileStorage
    let originals: [String: URL]
    let thumbnails: [String: Data]
}

struct RemovedSourceRecord {
    let source: SourceAsset
    let sourceIndex: Int
    let previousRegionOrder: [UUID]
    let thumbnailData: Data?
    let removedOriginalURL: URL
}

final class PhotoProjectDocument: ReferenceFileDocument, @unchecked Sendable {
    static let readableContentTypes: [UTType] = [.scanPhotoProject]

    @Published var manifest: ProjectManifest
    @Published var activityMessage = ""
    @Published var processingProgress: Double = 0
    @Published var isProcessing = false
    @Published var lastImportReport: ImportReport?
    @Published var projectError: String?

    private let storage: ProjectFileStorage
    private var thumbnails: [String: Data]

    init() {
        manifest = .empty()
        storage = ProjectFileStorage()
        thumbnails = [:]
    }

    required init(configuration: ReadConfiguration) throws {
        let snapshot = try ProjectPackageCodec.decode(configuration.file)
        manifest = snapshot.manifest
        storage = snapshot.storage
        thumbnails = snapshot.thumbnails
    }

    func snapshot(contentType: UTType) throws -> ProjectSnapshot {
        var savedManifest = manifest
        savedManifest.modifiedAt = Date()
        ProjectPackageCodec.normalizeRegionOrders(in: &savedManifest)
        try ProjectPackageCodec.validate(savedManifest)
        let filenames = savedManifest.sources.map(\.storedFilename)
        let snapshotStorage = try storage.immutableSnapshot(filenames: filenames)
        var originals: [String: URL] = [:]
        for filename in filenames {
            originals[filename] = snapshotStorage.originalURL(filename: filename)
        }
        return ProjectSnapshot(
            manifest: savedManifest,
            storage: snapshotStorage,
            originals: originals,
            thumbnails: thumbnails
        )
    }

    nonisolated func fileWrapper(
        snapshot: ProjectSnapshot,
        configuration: WriteConfiguration
    ) throws -> FileWrapper {
        try ProjectPackageCodec.encode(snapshot)
    }

    func originalURL(for source: SourceAsset) -> URL? {
        let url = storage.originalURL(filename: source.storedFilename)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func thumbnailData(for sourceID: UUID) -> Data? {
        thumbnails["\(sourceID.uuidString).jpg"]
    }

    func setImportedFile(
        at stagedURL: URL,
        thumbnailData: Data?,
        source: SourceAsset
    ) throws {
        _ = try storage.adoptOriginal(at: stagedURL, filename: source.storedFilename)
        if let thumbnailData {
            thumbnails["\(source.id.uuidString).jpg"] = thumbnailData
        }
        manifest.sources.append(source)
        insertRegionIDs(source.regions.map(\.id), forImportOrder: source.importOrder)
        reconcileRegionOrdering()
        manifest.modifiedAt = Date()
    }

    func replaceRegions(for sourceID: UUID, with regions: [PhotoRegion]) {
        guard let index = manifest.sources.firstIndex(where: { $0.id == sourceID }) else { return }
        let oldIDs = Set(manifest.sources[index].regions.map(\.id))
        let insertionIndex = manifest.regionOrder.firstIndex(where: oldIDs.contains)
            ?? insertionIndex(forImportOrder: manifest.sources[index].importOrder)
        manifest.regionOrder.removeAll(where: oldIDs.contains)
        manifest.sources[index].regions = regions
        manifest.regionOrder.insert(
            contentsOf: regions.map(\.id),
            at: min(insertionIndex, manifest.regionOrder.count)
        )
        reconcileRegionOrdering()
        manifest.modifiedAt = Date()
    }

    func updateSource(_ source: SourceAsset) {
        guard let index = manifest.sources.firstIndex(where: { $0.id == source.id }) else { return }
        manifest.sources[index] = source
        reconcileRegionOrdering()
        manifest.modifiedAt = Date()
    }

    func removeSource(id: UUID) throws -> RemovedSourceRecord? {
        guard let sourceIndex = manifest.sources.firstIndex(where: { $0.id == id }) else {
            return nil
        }
        let source = manifest.sources[sourceIndex]
        let record = RemovedSourceRecord(
            source: source,
            sourceIndex: sourceIndex,
            previousRegionOrder: manifest.regionOrder,
            thumbnailData: thumbnails["\(source.id.uuidString).jpg"],
            removedOriginalURL: try storage.removeOriginal(filename: source.storedFilename)
        )
        manifest.sources.remove(at: sourceIndex)
        let regionIDs = Set(source.regions.map(\.id))
        manifest.regionOrder.removeAll(where: regionIDs.contains)
        thumbnails.removeValue(forKey: "\(source.id.uuidString).jpg")
        reconcileRegionOrdering()
        manifest.modifiedAt = Date()
        return record
    }

    func restoreSource(_ record: RemovedSourceRecord) throws {
        try storage.restoreOriginal(
            from: record.removedOriginalURL,
            filename: record.source.storedFilename
        )
        manifest.sources.insert(
            record.source,
            at: min(record.sourceIndex, manifest.sources.count)
        )
        manifest.regionOrder = record.previousRegionOrder
        if let thumbnailData = record.thumbnailData {
            thumbnails["\(record.source.id.uuidString).jpg"] = thumbnailData
        }
        reconcileRegionOrdering()
        manifest.modifiedAt = Date()
    }

    func reconcileRegionOrdering() {
        var positions: [UUID: Int] = [:]
        for (index, id) in manifest.regionOrder.enumerated() where positions[id] == nil {
            positions[id] = index
        }
        for sourceIndex in manifest.sources.indices {
            manifest.sources[sourceIndex].regions.sort {
                positions[$0.id, default: Int.max] < positions[$1.id, default: Int.max]
            }
            for regionIndex in manifest.sources[sourceIndex].regions.indices {
                manifest.sources[sourceIndex].regions[regionIndex].order = regionIndex
            }
        }
    }

    private func insertRegionIDs(_ ids: [UUID], forImportOrder importOrder: Int) {
        let index = insertionIndex(forImportOrder: importOrder)
        manifest.regionOrder.insert(contentsOf: ids, at: index)
    }

    private func insertionIndex(forImportOrder importOrder: Int) -> Int {
        let laterSourceIDs = Set(
            manifest.sources
                .filter { $0.importOrder > importOrder }
                .flatMap(\.regions)
                .map(\.id)
        )
        return manifest.regionOrder.firstIndex(where: laterSourceIDs.contains)
            ?? manifest.regionOrder.count
    }
}

enum ProjectPackageCodec {
    static func decode(_ fileWrapper: FileWrapper) throws -> ProjectSnapshot {
        guard
            fileWrapper.isDirectory,
            let wrappers = fileWrapper.fileWrappers,
            let manifestData = wrappers["manifest.json"]?.regularFileContents
        else {
            throw ProjectDocumentError.invalidPackage
        }

        let decoder = JSONDecoder.projectDecoder
        var decoded = try decoder.decode(ProjectManifest.self, from: manifestData)
        guard decoded.schemaVersion == ProjectManifest.currentSchemaVersion else {
            throw ProjectDocumentError.unsupportedSchema(decoded.schemaVersion)
        }
        try validate(decoded)
        normalizeRegionOrders(in: &decoded)

        let storage = ProjectFileStorage()
        try storage.prepare()
        var loadedOriginals: [String: URL] = [:]
        let originalWrappers = wrappers["Originals"]?.fileWrappers ?? [:]
        for source in decoded.sources {
            guard let data = originalWrappers[source.storedFilename]?.regularFileContents else {
                throw ProjectDocumentError.missingOriginal(source.storedFilename)
            }
            loadedOriginals[source.storedFilename] = try storage.writeOriginal(
                data,
                filename: source.storedFilename
            )
        }

        var loadedThumbnails: [String: Data] = [:]
        let thumbnailWrappers = wrappers["Thumbnails"]?.fileWrappers ?? [:]
        for (filename, wrapper) in thumbnailWrappers {
            if let data = wrapper.regularFileContents {
                loadedThumbnails[filename] = data
            }
        }
        for source in decoded.sources {
            let filename = "\(source.id.uuidString).jpg"
            if loadedThumbnails[filename] == nil,
               let originalURL = loadedOriginals[source.storedFilename],
               let thumbnail = try? ImageLoader.jpegThumbnail(url: originalURL) {
                loadedThumbnails[filename] = thumbnail
            }
        }
        return ProjectSnapshot(
            manifest: decoded,
            storage: storage,
            originals: loadedOriginals,
            thumbnails: loadedThumbnails
        )
    }

    static func encode(_ snapshot: ProjectSnapshot) throws -> FileWrapper {
        try validate(snapshot.manifest)
        let expectedFilenames = Set(snapshot.manifest.sources.map(\.storedFilename))
        guard Set(snapshot.originals.keys) == expectedFilenames else {
            let missing = expectedFilenames.subtracting(snapshot.originals.keys).first ?? "unknown"
            throw ProjectDocumentError.missingOriginal(missing)
        }
        for filename in expectedFilenames {
            guard let url = snapshot.originals[filename],
                  FileManager.default.fileExists(atPath: url.path)
            else {
                throw ProjectDocumentError.missingOriginal(filename)
            }
        }

        let encoder = JSONEncoder.projectEncoder
        let manifestData = try encoder.encode(snapshot.manifest)
        let root = FileWrapper(directoryWithFileWrappers: [:])
        root.preferredFilename = "Project.scanphoto"

        let manifestWrapper = FileWrapper(regularFileWithContents: manifestData)
        manifestWrapper.preferredFilename = "manifest.json"
        root.addFileWrapper(manifestWrapper)

        var originalWrappers: [String: FileWrapper] = [:]
        for (filename, url) in snapshot.originals {
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            let wrapper = FileWrapper(regularFileWithContents: data)
            wrapper.preferredFilename = filename
            originalWrappers[filename] = wrapper
        }
        let originalsDirectory = FileWrapper(directoryWithFileWrappers: originalWrappers)
        originalsDirectory.preferredFilename = "Originals"
        root.addFileWrapper(originalsDirectory)

        let thumbnailWrappers = snapshot.thumbnails.reduce(into: [String: FileWrapper]()) {
            result, item in
            let wrapper = FileWrapper(regularFileWithContents: item.value)
            wrapper.preferredFilename = item.key
            result[item.key] = wrapper
        }
        let thumbnailsDirectory = FileWrapper(directoryWithFileWrappers: thumbnailWrappers)
        thumbnailsDirectory.preferredFilename = "Thumbnails"
        root.addFileWrapper(thumbnailsDirectory)
        return root
    }

    static func validate(_ manifest: ProjectManifest) throws {
        let sourceIDs = manifest.sources.map(\.id)
        guard Set(sourceIDs).count == sourceIDs.count else {
            throw ProjectDocumentError.invalidManifest("source IDs are not unique.")
        }
        let filenames = manifest.sources.map(\.storedFilename)
        guard Set(filenames).count == filenames.count else {
            throw ProjectDocumentError.invalidManifest("original filenames are not unique.")
        }

        var regionIDs: [UUID] = []
        for source in manifest.sources {
            for region in source.regions {
                guard region.sourceID == source.id else {
                    throw ProjectDocumentError.invalidManifest(
                        "region \(region.id) references the wrong source."
                    )
                }
                guard region.quadrilateral.isValid() else {
                    throw ProjectDocumentError.invalidManifest(
                        "region \(region.id) has invalid geometry."
                    )
                }
                regionIDs.append(region.id)
            }
        }
        guard Set(regionIDs).count == regionIDs.count else {
            throw ProjectDocumentError.invalidManifest("region IDs are not unique.")
        }
        guard Set(manifest.regionOrder).count == manifest.regionOrder.count else {
            throw ProjectDocumentError.invalidManifest("region order contains duplicates.")
        }
        guard manifest.regionOrder.count == regionIDs.count,
              Set(manifest.regionOrder) == Set(regionIDs)
        else {
            throw ProjectDocumentError.invalidManifest(
                "region order does not match the project regions."
            )
        }
    }

    static func normalizeRegionOrders(in manifest: inout ProjectManifest) {
        var positions: [UUID: Int] = [:]
        for (index, id) in manifest.regionOrder.enumerated() {
            positions[id] = index
        }
        for sourceIndex in manifest.sources.indices {
            manifest.sources[sourceIndex].regions.sort {
                positions[$0.id, default: Int.max] < positions[$1.id, default: Int.max]
            }
            for regionIndex in manifest.sources[sourceIndex].regions.indices {
                manifest.sources[sourceIndex].regions[regionIndex].order = regionIndex
            }
        }
    }
}

private extension JSONEncoder {
    static var projectEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var projectDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
