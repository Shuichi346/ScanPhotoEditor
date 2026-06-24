import Combine
import Foundation
import SwiftUI
import UniformTypeIdentifiers

enum ProjectDocumentError: LocalizedError {
    case invalidPackage
    case unsupportedSchema(Int)
    case missingOriginal(String)

    var errorDescription: String? {
        switch self {
        case .invalidPackage:
            "The selected file is not a valid ScanPhotoEditor project."
        case let .unsupportedSchema(version):
            "This project uses unsupported schema version \(version)."
        case let .missingOriginal(filename):
            "The project is missing original image \(filename)."
        }
    }
}

struct ProjectSnapshot: Sendable {
    let manifest: ProjectManifest
    let originals: [String: Data]
    let thumbnails: [String: Data]
}

final class PhotoProjectDocument: ReferenceFileDocument, @unchecked Sendable {
    static let readableContentTypes: [UTType] = [.scanPhotoProject]

    @Published var manifest: ProjectManifest
    @Published var activityMessage = ""
    @Published var processingProgress: Double = 0
    @Published var isProcessing = false
    @Published var lastImportReport: ImportReport?
    @Published var projectError: String?

    private(set) var originals: [String: Data]
    private(set) var thumbnails: [String: Data]

    init() {
        manifest = .empty()
        originals = [:]
        thumbnails = [:]
    }

    required init(configuration: ReadConfiguration) throws {
        let snapshot = try ProjectPackageCodec.decode(configuration.file)
        manifest = snapshot.manifest
        originals = snapshot.originals
        thumbnails = snapshot.thumbnails
    }

    func snapshot(contentType: UTType) throws -> ProjectSnapshot {
        var savedManifest = manifest
        savedManifest.modifiedAt = Date()
        return ProjectSnapshot(
            manifest: savedManifest,
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

    func originalData(for source: SourceAsset) -> Data? {
        originals[source.storedFilename]
    }

    func thumbnailData(for sourceID: UUID) -> Data? {
        thumbnails["\(sourceID.uuidString).jpg"]
    }

    func setImportedData(
        _ data: Data,
        thumbnailData: Data?,
        source: SourceAsset
    ) {
        originals[source.storedFilename] = data
        if let thumbnailData {
            thumbnails["\(source.id.uuidString).jpg"] = thumbnailData
        }
        manifest.sources.append(source)
        manifest.modifiedAt = Date()
    }

    func replaceRegions(for sourceID: UUID, with regions: [PhotoRegion]) {
        guard let index = manifest.sources.firstIndex(where: { $0.id == sourceID }) else { return }
        let oldIDs = Set(manifest.sources[index].regions.map(\.id))
        manifest.regionOrder.removeAll(where: oldIDs.contains)
        manifest.sources[index].regions = regions
        manifest.regionOrder.append(contentsOf: regions.map(\.id))
        manifest.modifiedAt = Date()
    }

    func updateSource(_ source: SourceAsset) {
        guard let index = manifest.sources.firstIndex(where: { $0.id == source.id }) else { return }
        manifest.sources[index] = source
        manifest.modifiedAt = Date()
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
        let decoded = try decoder.decode(ProjectManifest.self, from: manifestData)
        guard decoded.schemaVersion == ProjectManifest.currentSchemaVersion else {
            throw ProjectDocumentError.unsupportedSchema(decoded.schemaVersion)
        }

        var loadedOriginals: [String: Data] = [:]
        let originalWrappers = wrappers["Originals"]?.fileWrappers ?? [:]
        for source in decoded.sources {
            guard let data = originalWrappers[source.storedFilename]?.regularFileContents else {
                throw ProjectDocumentError.missingOriginal(source.storedFilename)
            }
            loadedOriginals[source.storedFilename] = data
        }

        var loadedThumbnails: [String: Data] = [:]
        let thumbnailWrappers = wrappers["Thumbnails"]?.fileWrappers ?? [:]
        for (filename, wrapper) in thumbnailWrappers {
            if let data = wrapper.regularFileContents {
                loadedThumbnails[filename] = data
            }
        }
        return ProjectSnapshot(
            manifest: decoded,
            originals: loadedOriginals,
            thumbnails: loadedThumbnails
        )
    }

    static func encode(_ snapshot: ProjectSnapshot) throws -> FileWrapper {
        let encoder = JSONEncoder.projectEncoder
        let manifestData = try encoder.encode(snapshot.manifest)

        let root = FileWrapper(directoryWithFileWrappers: [:])
        root.preferredFilename = "Project.scanphoto"

        let manifestWrapper = FileWrapper(regularFileWithContents: manifestData)
        manifestWrapper.preferredFilename = "manifest.json"
        root.addFileWrapper(manifestWrapper)

        let originalWrappers = snapshot.originals.reduce(into: [String: FileWrapper]()) { result, item in
            let wrapper = FileWrapper(regularFileWithContents: item.value)
            wrapper.preferredFilename = item.key
            result[item.key] = wrapper
        }
        let originalsDirectory = FileWrapper(directoryWithFileWrappers: originalWrappers)
        originalsDirectory.preferredFilename = "Originals"
        root.addFileWrapper(originalsDirectory)

        let thumbnailWrappers = snapshot.thumbnails.reduce(into: [String: FileWrapper]()) { result, item in
            let wrapper = FileWrapper(regularFileWithContents: item.value)
            wrapper.preferredFilename = item.key
            result[item.key] = wrapper
        }
        let thumbnailsDirectory = FileWrapper(directoryWithFileWrappers: thumbnailWrappers)
        thumbnailsDirectory.preferredFilename = "Thumbnails"
        root.addFileWrapper(thumbnailsDirectory)

        return root
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
