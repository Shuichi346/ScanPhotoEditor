import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum PDFExportError: LocalizedError {
    case contextCreationFailed
    case imageEncodingFailed
    case noPages

    var errorDescription: String? {
        switch self {
        case .contextCreationFailed: "The PDF could not be created."
        case .imageEncodingFailed: "A PDF page image could not be compressed."
        case .noPages: "There are no regions to export."
        }
    }
}

enum PDFExportService {
    static func export(
        images: [(name: String, image: CGImage)],
        quality: Double,
        destinationDirectory: URL
    ) throws -> URL {
        guard !images.isEmpty else { throw PDFExportError.noPages }
        let outputURL = ImageExportService.conflictSafeURL(
            baseName: "ScanPhotoEditor Export",
            fileExtension: "pdf",
            directory: destinationDirectory
        )
        let temporaryURL = outputURL.appendingPathExtension("partial")
        try? FileManager.default.removeItem(at: temporaryURL)

        guard let consumer = CGDataConsumer(url: temporaryURL as CFURL) else {
            throw PDFExportError.contextCreationFailed
        }
        var initialBox = pageBox(for: images[0].image)
        guard let context = CGContext(consumer: consumer, mediaBox: &initialBox, nil) else {
            throw PDFExportError.contextCreationFailed
        }

        for item in images {
            let compressedImage = try jpegBackedImage(
                from: item.image,
                quality: quality
            )
            var pageBox = pageBox(for: item.image)
            let pageInfo = [
                kCGPDFContextMediaBox: NSData(
                    bytes: &pageBox,
                    length: MemoryLayout<CGRect>.size
                )
            ] as CFDictionary
            context.beginPDFPage(pageInfo)
            context.interpolationQuality = .high
            context.draw(compressedImage, in: pageBox)
            context.endPDFPage()
        }
        context.closePDF()
        try FileManager.default.moveItem(at: temporaryURL, to: outputURL)
        return outputURL
    }

    private static func jpegBackedImage(
        from image: CGImage,
        quality: Double
    ) throws -> CGImage {
        guard let opaqueImage = ImageRenderingContext.opaqueImage(from: image) else {
            throw PDFExportError.imageEncodingFailed
        }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw PDFExportError.imageEncodingFailed
        }
        let properties = [
            kCGImagePropertyOrientation: 1,
            kCGImageDestinationLossyCompressionQuality: min(max(quality, 0.01), 1)
        ] as CFDictionary
        CGImageDestinationAddImage(destination, opaqueImage, properties)
        guard CGImageDestinationFinalize(destination),
              let provider = CGDataProvider(data: data),
              let compressedImage = CGImage(
                  jpegDataProviderSource: provider,
                  decode: nil,
                  shouldInterpolate: true,
                  intent: .defaultIntent
              )
        else {
            throw PDFExportError.imageEncodingFailed
        }
        return compressedImage
    }

    private static func pageBox(for image: CGImage) -> CGRect {
        CGRect(
            x: 0,
            y: 0,
            width: CGFloat(image.width) / 300 * 72,
            height: CGFloat(image.height) / 300 * 72
        )
    }
}
