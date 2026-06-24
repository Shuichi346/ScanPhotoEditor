import Foundation
import UniformTypeIdentifiers

enum ProcessingState: String, Codable, Sendable {
    case queued
    case processing
    case ready
    case failed
    case cancelled
}

enum RegionOrigin: String, Codable, Sendable {
    case automatic
    case manual
    case fallback
}

enum ReviewState: String, Codable, Sendable {
    case ready
    case needsReview
}

enum QuarterTurn: Int, Codable, CaseIterable, Sendable {
    case zero = 0
    case clockwise90 = 1
    case clockwise180 = 2
    case clockwise270 = 3

    var next: QuarterTurn {
        QuarterTurn(rawValue: (rawValue + 1) % 4) ?? .zero
    }
}

struct SourceAsset: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var displayName: String
    var storedFilename: String
    var typeIdentifier: String
    var pixelWidth: Int
    var pixelHeight: Int
    var importOrder: Int
    var processingState: ProcessingState
    var processingError: String?
    var regions: [PhotoRegion]

    var pixelSize: CGSize {
        CGSize(width: pixelWidth, height: pixelHeight)
    }
}

struct PhotoRegion: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var sourceID: UUID
    var quadrilateral: NormalizedQuadrilateral
    var origin: RegionOrigin
    var reviewState: ReviewState
    var rotation: QuarterTurn
    var flipHorizontal: Bool
    var flipVertical: Bool
    var order: Int
    var isManuallyEdited: Bool
}

struct ProjectManifest: Codable, Hashable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var projectID: UUID
    var createdAt: Date
    var modifiedAt: Date
    var sources: [SourceAsset]
    var regionOrder: [UUID]

    static func empty() -> ProjectManifest {
        let now = Date()
        return ProjectManifest(
            schemaVersion: currentSchemaVersion,
            projectID: UUID(),
            createdAt: now,
            modifiedAt: now,
            sources: [],
            regionOrder: []
        )
    }
}

enum ExportImageFormat: String, Codable, CaseIterable, Identifiable, Sendable {
    case jpeg
    case heic
    case png
    case tiff

    var id: String { rawValue }

    var label: String {
        switch self {
        case .jpeg: "JPEG"
        case .heic: "HEIC"
        case .png: "PNG"
        case .tiff: "TIFF"
        }
    }

    var fileExtension: String { rawValue == "jpeg" ? "jpg" : rawValue }

    var contentType: UTType {
        switch self {
        case .jpeg: .jpeg
        case .heic: .heic
        case .png: .png
        case .tiff: .tiff
        }
    }
}

struct ExportOptions: Sendable {
    var formats: Set<ExportImageFormat> = [.jpeg]
    var includePDF = true
    var selectedRegionIDs: Set<UUID>?
    var jpegQuality = ExportPreferences.defaultQuality
    var heicQuality = ExportPreferences.defaultQuality
    var pdfQuality = ExportPreferences.defaultQuality

    func quality(for format: ExportImageFormat) -> Double {
        switch format {
        case .jpeg:
            jpegQuality
        case .heic:
            heicQuality
        case .png, .tiff:
            1
        }
    }
}

enum ExportPreferences {
    static let jpegQualityKey = "jpegExportQuality"
    static let heicQualityKey = "heicExportQuality"
    static let pdfQualityKey = "pdfExportQuality"
    static let defaultQualityPercent = 80
    static let qualityPercentRange = 1 ... 100
    static let defaultQuality = Double(defaultQualityPercent) / 100

    static func normalizedQualityPercent(_ value: Int) -> Int {
        min(
            max(value, qualityPercentRange.lowerBound),
            qualityPercentRange.upperBound
        )
    }

    static func quality(from percent: Int) -> Double {
        Double(normalizedQualityPercent(percent)) / 100
    }
}

struct ImportReport: Sendable {
    var imported: [String] = []
    var skipped: [String] = []
    var failures: [String] = []
}

struct ExportFailure: Identifiable, Sendable {
    let id = UUID()
    let item: String
    let message: String
}

struct ExportReport: Sendable {
    var exportedURLs: [URL] = []
    var failures: [ExportFailure] = []
}

extension UTType {
    static let scanPhotoProject = UTType(
        exportedAs: "com.shuichi.scanphoto",
        conformingTo: .package
    )
}
