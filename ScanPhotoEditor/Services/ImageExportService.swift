import CoreGraphics
import Foundation
import ImageIO

enum ImageExportError: LocalizedError {
    case destinationCreationFailed
    case finalizationFailed

    var errorDescription: String? {
        switch self {
        case .destinationCreationFailed: "The export encoder could not be created."
        case .finalizationFailed: "The export encoder could not finish the file."
        }
    }
}

enum ImageExportService {
    static func export(
        image: CGImage,
        format: ExportImageFormat,
        quality: Double,
        baseName: String,
        destinationDirectory: URL
    ) throws -> URL {
        let outputURL = conflictSafeURL(
            baseName: baseName,
            fileExtension: format.fileExtension,
            directory: destinationDirectory
        )
        let temporaryURL = outputURL.appendingPathExtension("partial")
        try? FileManager.default.removeItem(at: temporaryURL)

        guard let destination = CGImageDestinationCreateWithURL(
            temporaryURL as CFURL,
            format.contentType.identifier as CFString,
            1,
            nil
        ) else {
            throw ImageExportError.destinationCreationFailed
        }

        var properties: [CFString: Any] = [
            kCGImagePropertyOrientation: 1
        ]
        switch format {
        case .jpeg, .heic:
            properties[kCGImageDestinationLossyCompressionQuality] = quality
        case .png:
            break
        case .tiff:
            properties[kCGImagePropertyTIFFCompression] = 5
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw ImageExportError.finalizationFailed
        }
        try FileManager.default.moveItem(at: temporaryURL, to: outputURL)
        return outputURL
    }

    static func conflictSafeURL(
        baseName: String,
        fileExtension: String,
        directory: URL
    ) -> URL {
        let sanitized = baseName
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        var candidate = directory
            .appendingPathComponent(sanitized)
            .appendingPathExtension(fileExtension)
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory
                .appendingPathComponent("\(sanitized)-\(suffix)")
                .appendingPathExtension(fileExtension)
            suffix += 1
        }
        return candidate
    }
}

